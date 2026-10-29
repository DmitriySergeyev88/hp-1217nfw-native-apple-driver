#import <Foundation/Foundation.h>
#include <arpa/inet.h>
static inline BOOL validICAAddress(NSString *address) {
    struct in_addr value;
    return [address isKindOfClass:NSString.class]&&inet_pton(AF_INET,address.UTF8String,&value)==1;
}
static inline NSString *icaAddress(void) {
    CFPreferencesAppSynchronize(CFSTR("local.hp-m1217.native-ica-settings"));
    id value=CFBridgingRelease(CFPreferencesCopyAppValue(CFSTR("scannerAddress"),CFSTR("local.hp-m1217.native-ica-settings")));
    return validICAAddress(value)?value:nil;
}
static inline BOOL saveICAAddress(NSString *address) {
    if(!validICAAddress(address))return NO;
    CFPreferencesSetAppValue(CFSTR("scannerAddress"),(__bridge CFStringRef)address,CFSTR("local.hp-m1217.native-ica-settings"));
    return CFPreferencesAppSynchronize(CFSTR("local.hp-m1217.native-ica-settings"));
}
