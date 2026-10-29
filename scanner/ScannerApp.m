#import <AppKit/AppKit.h>
#include <arpa/inet.h>
#include <assert.h>
#import "PDFSession.h"
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

static BOOL validOptions(NSString *ip, NSString *source, NSString *dpi, NSString *color) {
    struct in_addr address;
    return inet_pton(AF_INET, ip.UTF8String, &address)==1 &&
        ([@[@"flatbed",@"adf"] containsObject:source]) &&
        ([@[@"75",@"150",@"300",@"600"] containsObject:dpi]) &&
        ([@[@"color",@"gray"] containsObject:color]) &&
        !([source isEqual:@"adf"] && ([dpi isEqual:@"600"] || [color isEqual:@"gray"]));
}

@interface ScannerApp : NSObject <NSApplicationDelegate, NSWindowDelegate>
@property NSWindow *window;
@property NSTextField *address, *filename;
@property NSButton *save, *resetButton;
@property NSURL *sessionFolder;
@property NSMutableArray<NSURL *> *pdfSources;
@property BOOL unsaved, recoveryRequired;
@property NSPopUpButton *source, *dpi, *color;
@property NSTextField *status;
@property NSButton *scan;
@property BOOL busy;
@end

@implementation ScannerApp
- (void)applicationDidFinishLaunching:(NSNotification *)note {
    (void)note;
    self.window=[[NSWindow alloc] initWithContentRect:NSMakeRect(0,0,580,480)
        styleMask:NSWindowStyleMaskTitled|NSWindowStyleMaskClosable|NSWindowStyleMaskMiniaturizable
        backing:NSBackingStoreBuffered defer:NO];
    self.window.title=@"HP M1217 Native Scan — экспериментальная версия";
    self.window.delegate=self;
    NSView *view=self.window.contentView;
    NSArray *labels=@[@"Адрес сканера",@"Источник",@"Разрешение",@"Режим"];
    for(NSUInteger i=0;i<labels.count;i++) {
        NSTextField *label=[NSTextField labelWithString:labels[i]];
        label.frame=NSMakeRect(24,428-42*i,145,24);[view addSubview:label];
    }
    self.address=[[NSTextField alloc] initWithFrame:NSMakeRect(180,428,365,26)];
    self.address.stringValue=[[NSUserDefaults standardUserDefaults] stringForKey:@"scannerAddress"]?:@"";self.address.accessibilityLabel=labels[0];
    [view addSubview:self.address];
    self.source=[[NSPopUpButton alloc] initWithFrame:NSMakeRect(180,386,365,28)];
    [self.source addItemsWithTitles:@[@"Планшет",@"ADF — все загруженные листы"]];
    self.dpi=[[NSPopUpButton alloc] initWithFrame:NSMakeRect(180,344,365,28)];
    [self.dpi addItemsWithTitles:@[@"75",@"150",@"300",@"600"]];[self.dpi selectItemWithTitle:@"300"];
    self.color=[[NSPopUpButton alloc] initWithFrame:NSMakeRect(180,302,365,28)];
    [self.color addItemsWithTitles:@[@"Цвет",@"Оттенки серого (только планшет)"]];
    NSUInteger i=1;
    for(NSPopUpButton *popup in @[self.source,self.dpi,self.color]) {
        popup.accessibilityLabel=labels[i++];[view addSubview:popup];
    }
    self.pdfSources=[NSMutableArray new];
    NSTextField *nameLabel=[NSTextField labelWithString:@"Имя документа"];nameLabel.frame=NSMakeRect(24,260,145,24);[view addSubview:nameLabel];
    self.filename=[[NSTextField alloc] initWithFrame:NSMakeRect(180,260,365,26)];self.filename.stringValue=@"Скан";self.filename.accessibilityLabel=@"Имя документа";[view addSubview:self.filename];
    self.save=[NSButton buttonWithTitle:@"Сохранить PDF…" target:self action:@selector(savePDF:)];self.save.frame=NSMakeRect(24,105,260,32);self.save.enabled=NO;[view addSubview:self.save];
    self.resetButton=[NSButton buttonWithTitle:@"Новый документ" target:self action:@selector(resetDocument:)];self.resetButton.frame=NSMakeRect(295,105,260,32);[view addSubview:self.resetButton];
    NSTextField *notice=[NSTextField wrappingLabelWithString:@"A4. Планшет: добавляйте листы по одному; ADF: загрузите пачку. Затем сохраните общий PDF (до 100 страниц). Отдельные сканы и журнал остаются в выбранной папке. Закройте «Захват изображений»."];
    notice.frame=NSMakeRect(24,177,530,70);[view addSubview:notice];
    self.scan=[NSButton buttonWithTitle:@"Сканировать / добавить листы…" target:self action:@selector(startScan:)];
    self.scan.frame=NSMakeRect(24,140,530,32);[view addSubview:self.scan];
    self.status=[NSTextField wrappingLabelWithString:@"Готово. ADF: цвет, не более 300 dpi."];
    self.status.frame=NSMakeRect(24,15,530,80);[view addSubview:self.status];
    NSMenu *menu=[NSMenu new];NSMenuItem *item=[NSMenuItem new];[menu addItem:item];
    NSMenu *appMenu=[NSMenu new];[appMenu addItemWithTitle:@"Завершить" action:@selector(terminate:) keyEquivalent:@"q"];
    item.submenu=appMenu;NSApp.mainMenu=menu;
    [self.window center];[self.window makeKeyAndOrderFront:nil];[NSApp activateIgnoringOtherApps:YES];
}
- (int)runTool:(NSString *)name arguments:(NSArray<NSString *> *)args log:(NSFileHandle *)log {
    NSTask *task=[NSTask new];
    task.executableURL=[NSBundle.mainBundle.bundleURL URLByAppendingPathComponent:[@"Contents/MacOS/" stringByAppendingString:name]];
    task.arguments=args;task.standardOutput=log;task.standardError=log;
    NSError *error=nil;
    if(![task launchAndReturnError:&error]) {
        [log writeData:[[NSString stringWithFormat:@"Launch failed: %@\n",error] dataUsingEncoding:NSUTF8StringEncoding]];
        return -1;
    }
    [task waitUntilExit];return task.terminationStatus;
}
- (void)startScan:(id)sender {
    (void)sender;if(self.busy)return;
    NSString *ip=self.address.stringValue;
    NSString *source=self.source.indexOfSelectedItem==0?@"flatbed":@"adf";
    NSString *dpi=self.dpi.titleOfSelectedItem;
    NSString *color=self.color.indexOfSelectedItem==0?@"color":@"gray";
    if(!validOptions(ip,source,dpi,color)) {
        self.status.stringValue=@"Проверьте IPv4. Для ADF доступны цвет и разрешение до 300 dpi.";return;
    }
    [[NSUserDefaults standardUserDefaults] setObject:ip forKey:@"scannerAddress"];
    NSString *stem=documentStem(self.filename.stringValue);
    if(!stem){self.status.stringValue=@"Введите имя без /, :, управляющих символов (до 160 байт).";return;}
    if(!self.sessionFolder) {
        NSOpenPanel *panel=[NSOpenPanel openPanel];panel.canChooseFiles=NO;panel.canChooseDirectories=YES;
        panel.canCreateDirectories=YES;panel.prompt=@"Выбрать папку";
        if([panel runModal]!=NSModalResponseOK)return;
        NSURL *session=[panel.URL URLByAppendingPathComponent:[stem stringByAppendingFormat:@"-%@",NSUUID.UUID.UUIDString] isDirectory:YES];
        NSError *creationError=nil;
        if(![[NSFileManager defaultManager] createDirectoryAtURL:session withIntermediateDirectories:NO attributes:@{NSFilePosixPermissions:@0700} error:&creationError]){self.status.stringValue=creationError.localizedDescription;return;}
        self.sessionFolder=session;self.filename.enabled=NO;
    }
    NSURL *folder=[self.sessionFolder URLByAppendingPathComponent:[@"part-" stringByAppendingString:NSUUID.UUID.UUIDString] isDirectory:YES];
    NSError *error=nil;
    if(![[NSFileManager defaultManager] createDirectoryAtURL:folder withIntermediateDirectories:NO attributes:@{NSFilePosixPermissions:@0700} error:&error]) {
        self.status.stringValue=error.localizedDescription;return;
    }
    NSString *raw=[[folder URLByAppendingPathComponent:@"capture.asp"] path];
    NSString *base=[[folder URLByAppendingPathComponent:stem] path];
    NSURL *logURL=[folder URLByAppendingPathComponent:@"diagnostic.log"];
    if(![[NSData data] writeToURL:logURL options:NSDataWritingWithoutOverwriting error:&error]) {
        self.status.stringValue=error.localizedDescription;return;
    }
    NSFileHandle *log=[NSFileHandle fileHandleForWritingToURL:logURL error:&error];
    if(!log){self.status.stringValue=error.localizedDescription;return;}
    self.busy=YES;self.scan.enabled=NO;self.save.enabled=NO;self.resetButton.enabled=NO;
    self.status.stringValue=@"Сканирование и возврат сканера в исходное состояние…";
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0), ^{
        int capture=[self runTool:@"marvell_capture" arguments:@[ip,raw,dpi,source,color,@"a4"] log:log];
        // A complete stream may survive a cleanup failure; the decoder checks EndJob.
        __block int decode=[self runTool:@"decode_capture" arguments:@[raw,base] log:log];
        [log closeFile];
        dispatch_async(dispatch_get_main_queue(), ^{
            self.busy=NO;self.recoveryRequired=capture!=0&&capture!=3;self.scan.enabled=!self.recoveryRequired;self.resetButton.enabled=YES;
            if(!decode) {
                NSURL *part=[NSURL fileURLWithPath:[base stringByAppendingPathExtension:@"pdf"]];
                NSMutableArray *candidate=[self.pdfSources mutableCopy];[candidate addObject:part];
                if(combinePDFs(candidate)){[self.pdfSources addObject:part];self.unsaved=YES;}
                else {decode=1;}
            }
            self.save.enabled=self.pdfSources.count>0;
            self.status.stringValue=capture==3?@"Нет соединения со сканером. Проверьте адрес и доступ приложения к локальной сети в настройках macOS.":decode?@"Сканирование не завершено. Данные и журнал сохранены; повтор не отправлен.":
                capture?@"Файлы сохранены, но завершение сеанса требует проверки журнала. Не запускайте повтор.":[NSString stringWithFormat:@"В документе %lu страниц. Добавьте листы или нажмите «Сохранить PDF…». Исходные сканы сохранены.",(unsigned long)combinePDFs(self.pdfSources).pageCount];

        });
    });
}
- (void)savePDF:(id)sender {
    (void)sender;if(self.busy||!self.pdfSources.count)return;
    NSSavePanel *panel=[NSSavePanel savePanel];panel.nameFieldStringValue=[documentStem(self.filename.stringValue) stringByAppendingPathExtension:@"pdf"];
    panel.directoryURL=self.sessionFolder;panel.allowedContentTypes=@[UTTypePDF];
    if([panel runModal]!=NSModalResponseOK)return;
    NSError *error=nil;
    if(!saveCombinedPDF(self.pdfSources,panel.URL,&error)) {self.status.stringValue=[@"PDF не сохранён. Выберите новое имя. " stringByAppendingString:error.localizedDescription];return;}
    self.unsaved=NO;self.status.stringValue=[NSString stringWithFormat:@"Сохранён %@ (%lu страниц).",panel.URL.lastPathComponent,(unsigned long)combinePDFs(self.pdfSources).pageCount];
    [[NSWorkspace sharedWorkspace] activateFileViewerSelectingURLs:@[panel.URL]];
}
- (BOOL)confirmLeave {
    if(self.busy)return NO;if(!self.unsaved)return YES;
    NSAlert *alert=[NSAlert new];alert.messageText=@"Общий PDF ещё не сохранён";
    alert.informativeText=@"Отдельные сканы останутся в выбранной папке. Можно вернуться и сохранить общий PDF.";
    [alert addButtonWithTitle:@"Вернуться"];[alert addButtonWithTitle:@"Продолжить без общего PDF"];
    return [alert runModal]==NSAlertSecondButtonReturn;
}
- (void)resetDocument:(id)sender {
    (void)sender;if(![self confirmLeave])return;
    [self.pdfSources removeAllObjects];self.sessionFolder=nil;self.unsaved=NO;self.filename.enabled=YES;self.save.enabled=NO;
    self.status.stringValue=self.recoveryRequired?@"Перед новым сканом проверьте устройство и перезапустите приложение.":@"Новый документ. Готово к сканированию.";
}
- (BOOL)windowShouldClose:(NSWindow *)sender {(void)sender;return [self confirmLeave];}
- (NSApplicationTerminateReply)applicationShouldTerminate:(NSApplication *)sender {
    (void)sender;return [self confirmLeave]?NSTerminateNow:NSTerminateCancel;
}
- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender {(void)sender;self.unsaved=NO;return YES;}
@end

int main(int argc,const char **argv) {
    @autoreleasepool {
        if(argc==3&&!strcmp(argv[1],"--connection-test")) {
            NSString *path=[NSString stringWithUTF8String:argv[2]];
            if(![[NSFileManager defaultManager] createFileAtPath:path contents:nil attributes:nil])return 1;
            NSFileHandle *log=[NSFileHandle fileHandleForWritingAtPath:path];
            if(!log)return 1;
            int result=[[ScannerApp new] runTool:@"marvell_capture" arguments:@[@"--check",[[NSUserDefaults standardUserDefaults] stringForKey:@"scannerAddress"]?:@"127.0.0.1"] log:log];
            [log closeFile];return result;
        }
        if(argc==2&&!strcmp(argv[1],"--test")) {
            assert(validOptions(@"192.0.2.1",@"adf",@"300",@"color"));
            assert(validOptions(@"192.0.2.1",@"flatbed",@"600",@"gray"));
            assert(!validOptions(@"invalid",@"adf",@"300",@"color"));
            assert(!validOptions(@"192.0.2.1",@"adf",@"600",@"color"));
            assert(!validOptions(@"192.0.2.1",@"adf",@"300",@"gray"));
            testPDFSession();
            puts("PASS application options (no network, no scan)");return 0;
        }
        NSApplication *app=NSApplication.sharedApplication;
        app.activationPolicy=NSApplicationActivationPolicyRegular;
        ScannerApp *delegate=[ScannerApp new];app.delegate=delegate;
        if(argc==3&&!strcmp(argv[1],"--ui-test")) {
            [delegate applicationDidFinishLaunching:[NSNotification notificationWithName:NSApplicationDidFinishLaunchingNotification object:app]];
            NSView *view=delegate.window.contentView;[view display];
            NSBitmapImageRep *rep=[view bitmapImageRepForCachingDisplayInRect:view.bounds];
            [view cacheDisplayInRect:view.bounds toBitmapImageRep:rep];
            BOOL ok=[[rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:[NSString stringWithUTF8String:argv[2]] atomically:NO];
            [delegate.window orderOut:nil];return ok?0:1;
        }
        [app run];
    }
    return 0;
}
