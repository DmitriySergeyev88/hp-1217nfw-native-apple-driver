// Test client selects only the native ICA module; never opens the legacy driver.
#import <Foundation/Foundation.h>
#import <ImageCaptureCore/ImageCaptureCore.h>
@interface Browser : NSObject <ICDeviceBrowserDelegate,ICScannerDeviceDelegate>
@property(strong) ICScannerDevice *scanner;
@property(strong) NSURL *output;
@property BOOL requested;
@property BOOL scanStarted;
@property NSUInteger receivedFiles;
@property BOOL hadError;
@property BOOL available;
@property NSTimeInterval started;
@end
@implementation Browser
- (void)deviceBrowser:(ICDeviceBrowser *)browser didAddDevice:(ICDevice *)device moreComing:(BOOL)more {
    (void)browser;(void)more;
    NSLog(@"DEVICE name=%@ transport=%@ type=%lu module=%@",device.name,device.transportType,(unsigned long)device.type,device.modulePath);
    if([device.name isEqualToString:@"HP M1217 Native ICA"] && !self.scanner) {
        self.scanner=(ICScannerDevice *)device;device.delegate=self;[device requestOpenSession];
    }
}
- (void)device:(ICDevice *)device didOpenSessionWithError:(NSError *)error {
    NSLog(@"OPEN %@ error=%@",device.name,error);
    if(!error) {
        self.available=YES;
        NSLog(@"UNITS %@",self.scanner.availableFunctionalUnitTypes);
        if(self.output&&!self.requested) {self.requested=YES;[self.scanner requestSelectFunctionalUnit:ICScannerFunctionalUnitTypeFlatbed];}
    }
}
- (void)device:(ICDevice *)device didCloseSessionWithError:(NSError *)error {
    NSLog(@"CLOSE %@ error=%@",device.name,error);
}
- (void)didRemoveDevice:(ICDevice *)device {NSLog(@"DEVICE REMOVED %@",device.name);}
- (void)device:(ICDevice *)device didEncounterError:(NSError *)error {self.hadError=YES;NSLog(@"ERROR %@ %@",device.name,error);}
- (void)scannerDeviceDidBecomeAvailable:(ICScannerDevice *)scanner {
    self.available=YES;
    NSLog(@"AVAILABLE units=%@ selected=%@",scanner.availableFunctionalUnitTypes,scanner.selectedFunctionalUnit);
    if(self.output&&!self.requested) {
        self.requested=YES;[scanner requestSelectFunctionalUnit:ICScannerFunctionalUnitTypeFlatbed];
    }
}
- (void)scannerDevice:(ICScannerDevice *)scanner didSelectFunctionalUnit:(ICScannerFunctionalUnit *)unit error:(NSError *)error {
    NSLog(@"SELECT error=%@ units=%@ selected=%@ resolution=%lu physical=%@",error,scanner.availableFunctionalUnitTypes,unit,(unsigned long)unit.resolution,NSStringFromSize(unit.physicalSize));
    if(error||!self.output||self.scanStarted)return;
    self.scanStarted=YES;
    unit.measurementUnit=ICScannerMeasurementUnitInches;
    unit.resolution=300;unit.pixelDataType=ICScannerPixelDataTypeRGB;unit.bitDepth=8;
    unit.scanArea=NSMakeRect(0,0,8.27,11.69);
    scanner.transferMode=ICScannerTransferModeFileBased;scanner.downloadsDirectory=self.output;
    scanner.documentName=@"reference-300";scanner.documentUTI=@"public.png";
    NSLog(@"SCAN resolution=%lu area=%@",(unsigned long)unit.resolution,NSStringFromRect(unit.scanArea));
    self.started=NSProcessInfo.processInfo.systemUptime;[scanner requestScan];
}
- (void)scannerDevice:(ICScannerDevice *)scanner didScanToURL:(NSURL *)url {
    (void)scanner;NSLog(@"FILE %@",url.path);
    if([[NSFileManager defaultManager] fileExistsAtPath:url.path])self.receivedFiles++;
}
- (void)scannerDevice:(ICScannerDevice *)scanner didCompleteScanWithError:(NSError *)error {
    NSLog(@"SCAN COMPLETE error=%@ elapsed=%.3f",error,NSProcessInfo.processInfo.systemUptime-self.started);
    [scanner requestCloseSession];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,2*NSEC_PER_SEC),dispatch_get_main_queue(),^{exit(error||self.hadError||!self.receivedFiles?1:0);});
}
- (void)deviceBrowser:(ICDeviceBrowser *)browser didRemoveDevice:(ICDevice *)device moreGoing:(BOOL)more {
    (void)browser;(void)more;NSLog(@"REMOVED %@",device.name);
}
@end
int main(int argc,char **argv) {
    @autoreleasepool {
        Browser *delegate=[Browser new];ICDeviceBrowser *browser=[ICDeviceBrowser new];
        if(argc==2) {
            NSString *path=[NSString stringWithUTF8String:argv[1]];
            if([[NSFileManager defaultManager] fileExistsAtPath:path])return 2;
            NSError *error=nil;
            if(![[NSFileManager defaultManager] createDirectoryAtPath:path withIntermediateDirectories:NO attributes:nil error:&error])return 2;
            delegate.output=[NSURL fileURLWithPath:path isDirectory:YES];
        } else if(argc!=1)return 2;
        browser.delegate=delegate;
        browser.browsedDeviceTypeMask=(ICDeviceTypeMask)(ICDeviceTypeMaskScanner|ICDeviceLocationTypeMaskLocal|ICDeviceLocationTypeMaskBonjour|ICDeviceLocationTypeMaskRemote);
        [browser start];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(delegate.output?180:20)*NSEC_PER_SEC),dispatch_get_main_queue(),^{
            if(delegate.output){NSLog(@"TIMEOUT");[delegate.scanner cancelScan];}
            [delegate.scanner requestCloseSession];[browser stop];
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW,2*NSEC_PER_SEC),dispatch_get_main_queue(),^{exit(delegate.output||!delegate.available?1:0);});
        });
        [[NSRunLoop currentRunLoop] run];
        NSLog(@"Device count: %lu",(unsigned long)browser.devices.count);[browser stop];
    }
    return 0;
}
