// ICA callback contract informed by Apple's VirtualScanner sample (see APPLE_LICENSE.txt).
#import <Foundation/Foundation.h>
#import <ICADevices/ICADevices.h>
#import <ICADevices/ICD_ScannerCalls.h>
#import <ImageCaptureCore/ImageCaptureCore.h>
#include <assert.h>
#include <arpa/inet.h>
#import "ICAConfig.h"

static NSString *const deviceName=@"HP M1217 Native ICA";
static BOOL offlineTest;
static ICAError performScan(const ScannerObjectInfo *info);
static void reportScanFailure(const ScannerObjectInfo *info,ICAError error);

@interface NativeState : NSObject
@property NSString *ip;
@property NSMutableDictionary *units;
@property NSUInteger unit;
@property NSDictionary *request;
@property BOOL session, busy;
@end
@implementation NativeState
@end

static NSDictionary *one(NSNumber *value) {return @{@"type":@"TWON_ONEVALUE",@"value":value};}
static NSMutableDictionary *enumeration(NSArray *values,NSUInteger index) {
    return [@{@"type":@"TWON_ENUMERATION",@"value":values,@"current":@(index),@"default":@(index)} mutableCopy];
}
static NSMutableDictionary *capabilities(NSUInteger unit) {
    return [@{@"functionalUnits":@{@"availableFunctionalUnitTypes":@[@0,@3],@"selectedFunctionalUnitType":@(unit)},
        @"supportsProgressNotificationsWithScanData":@1,
        @"CAP_AUTOFEED":one(@1),@"CAP_DUPLEX":one(@0),@"CAP_DUPLEXENABLED":one(@0),@"CAP_FEEDERENABLED":one(@(unit==3)),
        @"ICAP_BITDEPTH":enumeration(@[@8],0),@"ICAP_PIXELTYPE":enumeration(unit==3?@[@2]:@[@1,@2],unit==3?0:1),
        @"ICAP_UNITS":enumeration(@[@5],0),
        @"ICAP_XNATIVERESOLUTION":one(@300),@"ICAP_YNATIVERESOLUTION":one(@300),
        @"ICAP_XRESOLUTION":enumeration(unit==3?@[@75,@150,@300]:@[@75,@150,@300,@600],2),
        @"ICAP_YRESOLUTION":enumeration(unit==3?@[@75,@150,@300]:@[@75,@150,@300,@600],2),
        @"ICAP_PHYSICALWIDTH":one(@2480),@"ICAP_PHYSICALHEIGHT":one(@3506),
        @"ICAP_XSCALING":one(@1),@"ICAP_YSCALING":one(@1)} mutableCopy];
}
static NativeState *state(const ScannerObjectInfo *info) {
    return info?(__bridge NativeState *)(void *)info->privateData:nil;
}
static ICAError createDevice(ScannerObjectInfo *info,NSString *ip) {
    struct in_addr addr;
    if(!info||inet_pton(AF_INET,ip.UTF8String,&addr)!=1)return paramErr;
    NativeState *s=[NativeState new];s.ip=ip;s.units=[@{@0:capabilities(0),@3:capabilities(3)} mutableCopy];
    info->privateData=(Ptr)CFBridgingRetain(s);
    info->icaObjectInfo.objectType=kICADevice;info->icaObjectInfo.objectSubtype=kICADeviceScanner;
    info->flags=0;info->thumbnailSize=0;info->dataSize=0;
    strlcpy((char *)info->name,deviceName.UTF8String,sizeof(info->name));
    strlcpy((char *)info->creationDate,"2026:10:29 00:00:00",sizeof(info->creationDate));
    NSLog(@"ICA device created %@",ip);return noErr;
}
static ICAError openUSB(UInt32 location,ScannerObjectInfo *info) {
    (void)location;(void)info;return paramErr;
}
static ICAError openTCP(CFDictionaryRef params,ScannerObjectInfo *info) {
    NSDictionary *d=(__bridge NSDictionary *)params;
    if(![d[@"ICABonjourServiceNameKey"] isEqual:deviceName])return paramErr;
    // The dedicated local discovery service represents this configured Ethernet scanner.
    NSString *ip=icaAddress();
    return ip?createDevice(info,ip):paramErr;
}
static ICAError closeDevice(ScannerObjectInfo *info) {
    NativeState *s=state(info);if(s.busy)return kICADeviceInternalErr;
    if(info&&info->privateData){CFRelease((CFTypeRef)info->privateData);info->privateData=NULL;}return noErr;
}
static ICAError periodic(ScannerObjectInfo *info) {(void)info;return noErr;}
static ICAError objectInfo(const ScannerObjectInfo *parent,UInt32 index,ScannerObjectInfo *child) {
    (void)parent;(void)index;(void)child;return paramErr;
}
static ICAError properties(ScannerObjectInfo *info,CFMutableDictionaryRef dictionary) {
    if(!state(info)||!dictionary)return paramErr;
    NSMutableDictionary *d=(__bridge NSMutableDictionary *)dictionary;
    d[(__bridge NSString *)kICAUserAssignedDeviceNameKey]=deviceName;
    d[@"supportsICARawFileFormat"]=@1;return noErr;
}
static BOOL checkConnection(NativeState *s) {
    if(offlineTest)return YES;
    NSString *path=[NSTemporaryDirectory() stringByAppendingPathComponent:[@"HP-ICA-connection-" stringByAppendingFormat:@"%@.log",NSUUID.UUID.UUIDString]];
    if(![[NSFileManager defaultManager] createFileAtPath:path contents:nil attributes:@{NSFilePosixPermissions:@0600}])return NO;
    NSFileHandle *log=[NSFileHandle fileHandleForWritingAtPath:path];if(!log)return NO;
    BOOL connected=NO;
    // macOS may reject the first connection while refreshing an already allowed UUID.
    for(int attempt=0;attempt<2;attempt++) {
        NSTask *task=[NSTask new];task.executableURL=[NSBundle.mainBundle.bundleURL URLByAppendingPathComponent:@"Contents/MacOS/marvell_capture"];
        task.arguments=@[@"--check",s.ip];task.standardOutput=log;task.standardError=log;
        NSError *error=nil;if(![task launchAndReturnError:&error])break;
        [task waitUntilExit];if(task.terminationStatus==0){connected=YES;break;}
        if(task.terminationStatus!=3)break;
        if(attempt==0)[NSThread sleepForTimeInterval:2];
    }
    [log closeFile];NSLog(@"ICA connection check=%d log=%@",connected,path);return connected;
}
static ICAError openSession(const ScannerObjectInfo *info,ICD_ScannerOpenSessionPB *pb) {
    NativeState *s=state(info);if(!s||!pb)return paramErr;
    @synchronized(s){if(s.session)return kICAInvalidSessionErr;
        NSString *configured=icaAddress();if(!configured)return paramErr;s.ip=configured;
        if(!checkConnection(s))return kICADeviceInternalErr;s.session=YES;}
    NSLog(@"ICA session open %u",(unsigned)pb->sessionID);return noErr;
}
static ICAError closeSession(const ScannerObjectInfo *info,ICD_ScannerCloseSessionPB *pb) {
    NativeState *s=state(info);if(!s||!pb)return paramErr;
    @synchronized(s){if(!s.session||s.busy)return kICAInvalidSessionErr;s.session=NO;}
    return noErr;
}
static ICAError getParameters(const ScannerObjectInfo *info,ICD_ScannerGetParametersPB *pb) {
    NativeState *s=state(info);if(!s||!pb||!pb->theDict)return paramErr;
    ((__bridge NSMutableDictionary *)pb->theDict)[@"device"]=s.units[@(s.unit)];return noErr;
}
static ICAError applyParameters(NativeState *s,NSDictionary *parameters) {
    id request=parameters[@"userScanArea"];
    if([request isKindOfClass:NSArray.class])request=[request count]>1?request[1]:nil;
    if(![request isKindOfClass:NSDictionary.class])return paramErr;
    if(request[@"selectedFunctionalUnitType"]) {
        NSUInteger unit=[request[@"selectedFunctionalUnitType"] unsignedIntegerValue];
        if(!s.units[@(unit)])return paramErr;s.unit=unit;s.request=nil;return noErr;
    }
    NSMutableDictionary *caps=s.units[@(s.unit)],*updates=[NSMutableDictionary new];
    for(NSString *key in caps) {
        id entry=caps[key],incoming=request[key];if(!incoming)continue;
        if(![incoming isKindOfClass:NSDictionary.class]||!incoming[@"value"])return paramErr;
        NSNumber *value=incoming[@"value"];
        if([entry[@"type"] isEqual:@"TWON_ENUMERATION"]) {
            NSUInteger index=[entry[@"value"] indexOfObject:value];if(index==NSNotFound)return paramErr;
            NSMutableDictionary *updated=[entry mutableCopy];updated[@"current"]=@(index);updates[key]=updated;
        } else if([entry[@"type"] isEqual:@"TWON_ONEVALUE"]&&![entry[@"value"] isEqual:value])return paramErr;
    }
    [caps addEntriesFromDictionary:updates];s.request=[request copy];return noErr;
}
static ICAError setParameters(const ScannerObjectInfo *info,ICD_ScannerSetParametersPB *pb) {
    NativeState *s=state(info);if(!s||!pb||!pb->theDict||s.busy)return paramErr;
    NSLog(@"ICA set parameters %@",(__bridge NSDictionary *)pb->theDict);
    return applyParameters(s,(__bridge NSDictionary *)pb->theDict);
}
static ICAError status(const ScannerObjectInfo *info,ICD_ScannerStatusPB *pb) {
    if(!state(info)||!pb)return paramErr;pb->status=0;return noErr;
}
static ICAError start(const ScannerObjectInfo *info,ICD_ScannerStartPB *pb) {
    NativeState *s=state(info);if(!s||!pb)return paramErr;
    @synchronized(s){if(!s.session||s.busy)return kICAInvalidSessionErr;s.busy=YES;}
    ICAError result=performScan(info);s.busy=NO;
    if(result)reportScanFailure(info,result);return result;
}
static ICAError message(const ScannerObjectInfo *info,ICD_ScannerObjectSendMessagePB *pb,ICDCompletion completion) {
    (void)completion;if(!state(info)||!pb)return paramErr;
    if(pb->message.messageType==kICAMessageGetLastButtonPressed&&pb->message.dataPtr&&pb->message.dataSize==4) {
        *(UInt32 *)pb->message.dataPtr=0;return noErr;
    }
    return paramErr;
}

// Scan implementation is compiled from the same validated raster decoder as the standalone app.
#include "ScanDelivery.inc"

int main(int argc,const char **argv) {
    @autoreleasepool {
        if(argc==2&&!strcmp(argv[1],"--test")) {
            ScannerObjectInfo info={0};assert(createDevice(&info,@"192.0.2.1")==noErr);
            NativeState *s=state(&info);
            assert(applyParameters(s,@{@"userScanArea":@{@"selectedFunctionalUnitType":@3}})==noErr);
            assert(applyParameters(s,@{@"userScanArea":@{@"ICAP_XRESOLUTION":@{@"value":@600}}})==paramErr);
            assert(applyParameters(s,@{@"userScanArea":@{@"ICAP_XRESOLUTION":@{@"value":@300}}})==noErr);
            assert(applyParameters(s,@{@"userScanArea":@[]})==paramErr);
            offlineTest=YES;
            assert(testDelivery(&info)==0);
            assert(closeDevice(&info)==noErr);puts("PASS ICA capabilities, parameters and file/band delivery");return 0;
        }
        gICDScannerCallbackFunctions=(ICD_scanner_callback_functions){0};
        gICDScannerCallbackFunctions.f_ICD_ScannerOpenUSBDevice=openUSB;
        gICDScannerCallbackFunctions.f_ICD_ScannerOpenTCPIPDevice=openTCP;
        gICDScannerCallbackFunctions.f_ICD_ScannerCloseDevice=closeDevice;
        gICDScannerCallbackFunctions.f_ICD_ScannerCleanup=closeDevice;
        gICDScannerCallbackFunctions.f_ICD_ScannerPeriodicTask=periodic;
        gICDScannerCallbackFunctions.f_ICD_ScannerGetObjectInfo=objectInfo;
        gICDScannerCallbackFunctions.f_ICD_ScannerAddPropertiesToCFDictionary=properties;
        gICDScannerCallbackFunctions.f_ICD_ScannerOpenSession=openSession;
        gICDScannerCallbackFunctions.f_ICD_ScannerCloseSession=closeSession;
        gICDScannerCallbackFunctions.f_ICD_ScannerGetParameters=getParameters;
        gICDScannerCallbackFunctions.f_ICD_ScannerSetParameters=setParameters;
        gICDScannerCallbackFunctions.f_ICD_ScannerStatus=status;
        gICDScannerCallbackFunctions.f_ICD_ScannerStart=start;
        gICDScannerCallbackFunctions.f_ICD_ScannerSendMessage=message;
        return ICD_ScannerMain(argc,argv);
    }
}
