#import <AppKit/AppKit.h>
#import "ICAConfig.h"
#include <assert.h>

@interface Publisher : NSObject <NSNetServiceDelegate,NSApplicationDelegate>
@property NSNetService *service;
@property NSStatusItem *status;
@property NSMenuItem *addressItem;
@end
@implementation Publisher
- (BOOL)configure {
    NSAlert *alert=[NSAlert new];alert.messageText=@"HP M1217 Native ICA";
    alert.informativeText=@"IPv4 сканера / Scanner IPv4. Закройте сеанс сканирования перед изменением адреса / Close the scanning session before changing the address.";
    NSTextField *field=[[NSTextField alloc] initWithFrame:NSMakeRect(0,0,320,26)];field.stringValue=icaAddress()?:@"";field.placeholderString=@"192.168.1.100";
    alert.accessoryView=field;[alert addButtonWithTitle:@"Сохранить / Save"];[alert addButtonWithTitle:@"Отмена / Cancel"];
    [NSApp activateIgnoringOtherApps:YES];
    if([alert runModal]!=NSAlertFirstButtonReturn)return NO;
    NSString *ip=[field.stringValue stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if(!saveICAAddress(ip)) {NSAlert *error=[NSAlert new];error.messageText=@"Адрес не сохранён / Address not saved";error.informativeText=@"Введите корректный IPv4 / Enter a valid IPv4 address.";[error runModal];return NO;}
    return YES;
}
- (void)applicationDidFinishLaunching:(NSNotification *)note {
    (void)note;
    self.status=[[NSStatusBar systemStatusBar] statusItemWithLength:NSVariableStatusItemLength];self.status.button.title=@"HP Scan";
    NSMenu *menu=[NSMenu new];self.addressItem=[menu addItemWithTitle:@"" action:nil keyEquivalent:@""];
    NSMenuItem *edit=[menu addItemWithTitle:@"Адрес сканера… / Scanner address…" action:@selector(changeAddress:) keyEquivalent:@""];edit.target=self;
    [menu addItem:[NSMenuItem separatorItem]];[menu addItemWithTitle:@"Завершить / Quit" action:@selector(terminate:) keyEquivalent:@"q"];
    self.status.menu=menu;
    if(!icaAddress())[self configure];
    [self publish];
}
- (void)changeAddress:(id)sender {(void)sender;if([self configure])[self publish];}
- (void)publish {
    [self.service stop];self.service=nil;
    NSString *ip=icaAddress();self.addressItem.title=ip?:@"Адрес не задан / No address";if(!ip)return;
    self.service=[[NSNetService alloc] initWithDomain:@"local." type:@"_scanner._tcp." name:@"HP M1217 Native ICA" port:8290];
    self.service.delegate=self;
    [self.service setTXTRecordData:[NSNetService dataFromTXTRecordDictionary:@{@"mfg":[@"NativeM1217" dataUsingEncoding:NSUTF8StringEncoding],@"mdl":[@"M1217nfw" dataUsingEncoding:NSUTF8StringEncoding],@"txtvers":[@"1" dataUsingEncoding:NSUTF8StringEncoding]}]];
    [self.service publishWithOptions:NSNetServiceNoAutoRename];
}
- (void)netServiceDidPublish:(NSNetService *)sender {(void)sender;self.status.button.title=@"HP Scan";}
- (void)netService:(NSNetService *)sender didNotPublish:(NSDictionary *)errorDict {
    (void)sender;NSLog(@"Discovery failed %@",errorDict);self.status.button.title=@"HP Scan !";
    self.addressItem.title=@"Ошибка обнаружения / Discovery error (another copy?)";
}
- (void)applicationWillTerminate:(NSNotification *)note {(void)note;[self.service stop];}
@end
int main(int argc,const char **argv) {
    @autoreleasepool {
        if(argc==2&&!strcmp(argv[1],"--test")) {
            assert(validICAAddress(@"192.0.2.1"));assert(!validICAAddress(@""));assert(!validICAAddress(@"999.1.1.1"));assert(!validICAAddress(@"name.local"));
            NSData *txt=[NSNetService dataFromTXTRecordDictionary:@{@"mfg":[@"NativeM1217" dataUsingEncoding:NSUTF8StringEncoding],@"mdl":[@"M1217nfw" dataUsingEncoding:NSUTF8StringEncoding]}];
            assert([NSNetService dictionaryFromTXTRecordData:txt][@"mdl"]);
            puts("PASS IPv4 validation and discovery TXT; no preferences/network changes");return 0;
        }
        if(argc!=1)return 2;
        NSApplication *app=NSApplication.sharedApplication;app.activationPolicy=NSApplicationActivationPolicyAccessory;
        Publisher *publisher=[Publisher new];app.delegate=publisher;[app run];
    }
    return 0;
}
