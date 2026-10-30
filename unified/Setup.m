#import <AppKit/AppKit.h>
#import <ImageCaptureCore/ImageCaptureCore.h>
#import "../scanner/ica/ICAConfig.h"
@interface Observer:NSObject<ICDeviceBrowserDelegate>
@property NSString *uuid;
@end
@implementation Observer
-(void)deviceBrowser:(ICDeviceBrowser*)b didAddDevice:(ICDevice*)d moreComing:(BOOL)m {
 (void)b;(void)m;if([d.name isEqual:@"HP M1217 Native ICA"])self.uuid=d.UUIDString;
}
-(void)deviceBrowser:(ICDeviceBrowser*)b didRemoveDevice:(ICDevice*)d moreGoing:(BOOL)m {(void)b;(void)d;(void)m;}
@end
static void message(NSString *title,NSString *body) {NSAlert *a=[NSAlert new];a.messageText=title;a.informativeText=body;[a runModal];}
int main(int argc,char **argv){@autoreleasepool{
 if(argc==2&&!strcmp(argv[1],"--test")){assert(validICAAddress(@"192.0.2.1"));assert(!validICAAddress(@"1.2.3.999"));puts("PASS setup address validation; no changes");return 0;}
 if(argc!=1)return 2;
 [NSApplication sharedApplication];[NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];[NSApp activateIgnoringOtherApps:YES];
 NSAlert *a=[NSAlert new];a.messageText=@"HP M1217 — печать и сканирование / Print & Scan";
 a.informativeText=@"Введите IPv4 МФУ. Будет создана отдельная очередь PCLm 600 dpi и настроен ICA. Печать/сканирование не запускаются.\nEnter the MFP IPv4 address. Creates a separate print queue and configures ICA. No test pages or scans.";
 NSTextField *field=[[NSTextField alloc]initWithFrame:NSMakeRect(0,0,340,26)];field.placeholderString=@"192.168.1.100";field.stringValue=icaAddress()?:@"";field.accessibilityLabel=@"IPv4";a.accessoryView=field;
 [a addButtonWithTitle:@"Настроить / Configure"];[a addButtonWithTitle:@"Отмена / Cancel"];
 if([a runModal]!=NSAlertFirstButtonReturn)return 0;
 NSString *ip=[field.stringValue stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
 if(!validICAAddress(ip)){message(@"Ошибка / Error",@"Нужен корректный IPv4 / A valid IPv4 address is required.");return 1;}
 NSString *old=icaAddress();if(!saveICAAddress(ip)){message(@"Ошибка / Error",@"Не удалось сохранить адрес / Cannot save address.");return 1;}
 [[NSWorkspace sharedWorkspace]openURL:[NSURL fileURLWithPath:@"/Applications/HP M1217 ICA Discovery.app"]];
 Observer *o=[Observer new];ICDeviceBrowser *browser=[ICDeviceBrowser new];browser.delegate=o;browser.browsedDeviceTypeMask=(ICDeviceTypeMask)(ICDeviceTypeMaskScanner|ICDeviceLocationTypeMaskLocal|ICDeviceLocationTypeMaskBonjour|ICDeviceLocationTypeMaskRemote);[browser start];
 NSDate *until=[NSDate dateWithTimeIntervalSinceNow:12];
 while(!o.uuid&&until.timeIntervalSinceNow>0)[[NSRunLoop currentRunLoop]runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.2]];
 [browser stop];
 NSString *uuid=o.uuid?:@"";
 NSCharacterSet *bad=[[NSCharacterSet characterSetWithCharactersInString:@"0123456789abcdefABCDEF-"]invertedSet];
 if(uuid.length!=36||[uuid rangeOfCharacterFromSet:bad].location!=NSNotFound)uuid=@"";
 NSString *command=[NSString stringWithFormat:@"/bin/sh /Library/Printers/HPNative1217PCLm/configure-queue.sh '%@' '%@'",ip,uuid];
 NSString *script=[NSString stringWithFormat:@"do shell script \"%@\" with administrator privileges",command];
 NSDictionary *error=nil;NSAppleScript *as=[[NSAppleScript alloc]initWithSource:script];[as executeAndReturnError:&error];
 if(error){CFPreferencesSetAppValue(CFSTR("scannerAddress"),(__bridge CFStringRef)old,CFSTR("local.hp-m1217.native-ica-settings"));CFPreferencesAppSynchronize(CFSTR("local.hp-m1217.native-ica-settings"));message(@"Настройка не завершена / Setup incomplete",error.description);return 1;}
 CFPreferencesSetAppValue(CFSTR("scannerAddress"),(__bridge CFStringRef)ip,CFSTR("local.hp-m1217.native-scan"));CFPreferencesAppSynchronize(CFSTR("local.hp-m1217.native-scan"));
 message(@"Готово / Ready",uuid.length?@"Выберите HP M1217 PCLm 600 в Cmd+P. Для ICA оставьте HP Scan запущенным. Разрешите локальную сеть при запросе macOS.\nSelect HP M1217 PCLm 600 in Cmd+P. Keep HP Scan running for ICA discovery. Allow Local Network when prompted.":@"Очередь создана. ICA ещё не обнаружен: разрешите локальную сеть и повторите настройку для привязки сканера.\nQueue created. ICA was not discovered: allow Local Network and run setup again to link the scanner.");
}return 0;}
