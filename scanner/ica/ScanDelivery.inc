#import <ImageIO/ImageIO.h>
static const ScannerObjectInfo *activeInfo;
static NSNumber *setting(NativeState *s,NSString *key) {
    NSDictionary *entry=s.units[@(s.unit)][key];
    return [entry[@"type"] isEqual:@"TWON_ENUMERATION"]?entry[@"value"][[entry[@"current"] unsignedIntegerValue]]:entry[@"value"];
}
static ICAError notifyICA(const ScannerObjectInfo *info,CFStringRef type,NSDictionary *extra,BOOL wait) {
    if(offlineTest)return noErr;
    NSMutableDictionary *d=[@{(__bridge NSString *)kICANotificationICAObjectKey:@(info->icaObject),
        (__bridge NSString *)kICANotificationTypeKey:(__bridge NSString *)type} mutableCopy];
    if(extra)[d addEntriesFromDictionary:extra];
    ICASendNotificationPB pb={0};pb.notificationDictionary=(__bridge CFMutableDictionaryRef)d;
    ICAError err=wait?ICDSendNotificationAndWaitForReply(&pb):ICDSendNotification(&pb);
    return err?err:(wait&&pb.replyCode==(UInt32)userCanceledErr?userCanceledErr:noErr);
}
static void reportScanFailure(const ScannerObjectInfo *info,ICAError error) {
    NSDictionary *details=@{(__bridge NSString *)kICANotificationSubTypeKey:@"kICAErrStrScannerComErr",
        (__bridge NSString *)kICAErrorKey:@(error),(__bridge NSString *)kICANotificationVendorErrorCodeKey:@(error)};
    notifyICA(info,kICANotificationTypeDeviceStatusError,details,NO);
    notifyICA(info,kICANotificationTypeScannerScanDone,@{(__bridge NSString *)kICAErrorKey:@(error)},NO);
}
static int deliverPages(NSArray *pages,NSString *base,uint32_t dpi) {
    (void)base;NativeState *s=state(activeInfo);NSDictionary *request=s.request;
    BOOL overview=[request[@"progressNotificationWithData"] boolValue];
    BOOL bands=[request[@"progressNotificationWithScanData"] boolValue];
    for(NSDictionary *page in pages) {
        NSUInteger fullW=[page[@"width"] unsignedIntegerValue],fullH=[page[@"rows"] unsignedIntegerValue];
        NSUInteger channels=[page[@"channels"] unsignedIntegerValue];NSData *pixels=page[@"pixels"];
        double ox=overview?0:[request[@"offsetX"] doubleValue]*dpi/300.0;
        double oy=overview?0:[request[@"offsetY"] doubleValue]*dpi/300.0;
        double rw=overview?fullW:[request[@"width"] doubleValue],rh=overview?fullH:[request[@"height"] doubleValue];
        if(!isfinite(ox)||!isfinite(oy)||!isfinite(rw)||!isfinite(rh)||ox<0||oy<0||rw<1||rh<1||ox>=fullW||oy>=fullH)return 1;
        NSUInteger x=(NSUInteger)llround(ox),y=(NSUInteger)llround(oy);
        // Preserve actual firmware extent at the page edges; never enlarge the raster.
        NSUInteger w=MIN((NSUInteger)llround(rw),fullW-x),h=MIN((NSUInteger)llround(rh),fullH-y);
        if(!w||!h)return 1;
        NSMutableData *crop=[NSMutableData dataWithLength:w*h*channels];
        for(NSUInteger row=0;row<h;row++)memcpy((char *)crop.mutableBytes+row*w*channels,
            (const char *)pixels.bytes+((row+y)*fullW+x)*channels,w*channels);
        if(overview||bands) {
            NSUInteger bandRows=MAX(1,MIN(64,512*1024/(w*channels)));
            for(NSUInteger row=0;row<h;row+=bandRows) {
                NSUInteger rows=MIN(bandRows,h-row);
                NSMutableDictionary *d=[NSMutableDictionary new];
                ICAError err;
                void *data=(char *)crop.mutableBytes+row*w*channels;
                if(overview)err=ICDAddImageInfoToNotificationDictionary((__bridge CFMutableDictionaryRef)d,(UInt32)w,(UInt32)h,(UInt32)(w*channels),(UInt32)row,(UInt32)rows,(UInt32)(w*channels*rows),data);
                else err=ICDAddBandInfoToNotificationDictionary((__bridge CFMutableDictionaryRef)d,(UInt32)w,(UInt32)h,(UInt32)(8*channels),8,(UInt32)channels,0,channels==3?ICScannerPixelDataTypeRGB:ICScannerPixelDataTypeGray,(UInt32)(w*channels),(UInt32)row,(UInt32)rows,(UInt32)(w*channels*rows),data);
                if(err||notifyICA(activeInfo,kICANotificationTypeScanProgressStatus,d,YES))return 1;
            }
            if(notifyICA(activeInfo,kICANotificationTypeScannerPageDone,nil,NO))return 1;
        } else {
            NSString *folder=request[@"document folder"],*uti=request[@"document format"];
            if(![folder isKindOfClass:NSString.class]||!folder.isAbsolutePath||![uti isKindOfClass:NSString.class])return 1;
            NSDictionary *extensions=@{@"public.png":@"png",@"public.jpeg":@"jpg",@"public.tiff":@"tiff",@"com.adobe.pdf":@"pdf",(__bridge NSString *)kICUTTypeRaw:@"raw"};
            NSString *ext=extensions[uti];if(!ext)return 1;
            id requestedExtension=request[@"document extension"];
            if(requestedExtension) {
                if(![requestedExtension isKindOfClass:NSString.class]||![requestedExtension length]||[requestedExtension length]>16||
                   [requestedExtension rangeOfCharacterFromSet:[[NSCharacterSet characterSetWithCharactersInString:@"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"] invertedSet]].location!=NSNotFound)return 1;
                ext=requestedExtension;
            }
            NSString *name=[request[@"document name"] isKindOfClass:NSString.class]?[request[@"document name"] lastPathComponent]:@"Scan";
            if(!name.length||[name isEqual:@"."]||[name isEqual:@".."])return 1;
            NSMutableData *output=[NSMutableData new];
            if([uti isEqual:(__bridge NSString *)kICUTTypeRaw]) {
                ICARawFileHeader header={0};header.imageDataOffset=sizeof(header);header.version=1;
                header.imageWidth=(UInt32)w;header.imageHeight=(UInt32)h;header.bytesPerRow=(UInt32)(w*channels);
                header.numberOfComponents=(UInt32)channels;header.bitsPerComponent=8;header.bitsPerPixel=(UInt32)(8*channels);
                header.cgColorSpaceModel=channels==3?kCGColorSpaceModelRGB:kCGColorSpaceModelMonochrome;
                header.bitmapInfo=kCGImageAlphaNone;header.orientation=1;header.dpi=dpi;
                // Image Capture interprets this descriptor when assembling PDF pages.
                NSString *mode=request[@"ColorSyncMode"];
                if(![mode isKindOfClass:NSString.class]||!mode.length||
                   [mode lengthOfBytesUsingEncoding:NSUTF8StringEncoding]>=sizeof(header.colorSyncModeStr))return 1;
                strlcpy(header.colorSyncModeStr,mode.UTF8String,sizeof(header.colorSyncModeStr));
                [output appendBytes:&header length:sizeof(header)];[output appendData:crop];
            } else {
                CGColorSpaceRef space=channels==3?CGColorSpaceCreateDeviceRGB():CGColorSpaceCreateDeviceGray();
                CGDataProviderRef provider=CGDataProviderCreateWithCFData((__bridge CFDataRef)crop);
                CGImageRef image=CGImageCreate(w,h,8,channels*8,w*channels,space,(CGBitmapInfo)kCGImageAlphaNone,provider,NULL,false,kCGRenderingIntentDefault);
                CGDataProviderRelease(provider);CGColorSpaceRelease(space);if(!image)return 1;
                if([uti isEqual:@"com.adobe.pdf"]) {
                    CGRect box=CGRectMake(0,0,w*72.0/dpi,h*72.0/dpi);
                    CGDataConsumerRef consumer=CGDataConsumerCreateWithCFData((__bridge CFMutableDataRef)output);
                    CGContextRef context=CGPDFContextCreate(consumer,&box,NULL);CGDataConsumerRelease(consumer);
                    if(!context){CGImageRelease(image);return 1;}
                    CGPDFContextBeginPage(context,NULL);CGContextDrawImage(context,box,image);CGPDFContextEndPage(context);CGPDFContextClose(context);CGContextRelease(context);
                } else {
                    CGImageDestinationRef dest=CGImageDestinationCreateWithData((__bridge CFMutableDataRef)output,(__bridge CFStringRef)uti,1,NULL);
                    if(!dest){CGImageRelease(image);return 1;}
                    CGImageDestinationAddImage(dest,image,(__bridge CFDictionaryRef)@{(__bridge NSString *)kCGImagePropertyDPIWidth:@(dpi),(__bridge NSString *)kCGImagePropertyDPIHeight:@(dpi)});
                    BOOL ok=CGImageDestinationFinalize(dest);CFRelease(dest);if(!ok){CGImageRelease(image);return 1;}
                }
                CGImageRelease(image);
            }
            // Keep the client's requested name; number collisions without overwriting user files.
            NSString *file=nil;
            for(NSUInteger index=0;index<10000;index++) {
                NSString *stem=index?[name stringByAppendingFormat:@" %lu",(unsigned long)index]:name;
                NSString *candidate=[folder stringByAppendingPathComponent:[stem stringByAppendingPathExtension:ext]];
                NSError *error=nil;
                if([output writeToFile:candidate options:NSDataWritingWithoutOverwriting error:&error]){file=candidate;break;}
                if(![error.domain isEqual:NSCocoaErrorDomain]||error.code!=NSFileWriteFileExistsError){NSLog(@"ICA output %@",error);return 1;}
            }
            if(!file)return 1;
            if(notifyICA(activeInfo,kICANotificationTypeScannerPageDone,@{(__bridge NSString *)kICANotificationScannerDocumentNameKey:file},NO))return 1;
        }
    }
    return 0;
}
#define MARVELL_PAGE_CONSUMER deliverPages
#define main decoder_test_main
#include "../decode_capture.m"
#undef main
#undef MARVELL_PAGE_CONSUMER

static ICAError performScan(const ScannerObjectInfo *info) {
    NativeState *s=state(info);if(!s.request)return paramErr;
    unsigned dpi=setting(s,@"ICAP_XRESOLUTION").unsignedIntValue;
    if(dpi!=setting(s,@"ICAP_YRESOLUTION").unsignedIntValue)return paramErr;
    if(![s.request[@"progressNotificationWithData"] boolValue]) {
        double w=[s.request[@"width"] doubleValue],h=[s.request[@"height"] doubleValue];
        double x=[s.request[@"offsetX"] doubleValue],y=[s.request[@"offsetY"] doubleValue];
        if(!isfinite(w)||!isfinite(h)||!isfinite(x)||!isfinite(y)||w<1||h<1||x<0||y<0||
           x/300+w/dpi>8.28||y/300+h/dpi>11.70)return paramErr;
    }
    NSString *source=s.unit==3?@"adf":@"flatbed",*color=setting(s,@"ICAP_PIXELTYPE").intValue==2?@"color":@"gray";
    NSString *folder=[NSTemporaryDirectory() stringByAppendingPathComponent:[@"HP-Native-ICA-" stringByAppendingString:NSUUID.UUID.UUIDString]];
    NSError *error=nil;
    if(![[NSFileManager defaultManager] createDirectoryAtPath:folder withIntermediateDirectories:NO attributes:@{NSFilePosixPermissions:@0700} error:&error])return kICADeviceInternalErr;
    NSString *raw=[folder stringByAppendingPathComponent:@"capture.asp"],*logPath=[folder stringByAppendingPathComponent:@"diagnostic.log"];
    [[NSFileManager defaultManager] createFileAtPath:logPath contents:nil attributes:nil];
    NSFileHandle *log=[NSFileHandle fileHandleForWritingAtPath:logPath];if(!log)return kICADeviceInternalErr;
    NSTask *task=[NSTask new];task.executableURL=[NSBundle.mainBundle.bundleURL URLByAppendingPathComponent:@"Contents/MacOS/marvell_capture"];
    task.arguments=@[s.ip,raw,[@(dpi) stringValue],source,color,@"a4"];task.standardOutput=log;task.standardError=log;
    if(![task launchAndReturnError:&error]){[log closeFile];NSLog(@"ICA launch %@",error);return kICADeviceInternalErr;}
    BOOL cancelled=NO;
    while(task.running) {
        if(notifyICA(info,kICANotificationTypeScanProgressStatus,nil,YES)==userCanceledErr){cancelled=YES;[task terminate];break;}
        [NSThread sleepForTimeInterval:0.25];
    }
    [task waitUntilExit];[log closeFile];
    NSLog(@"ICA capture status=%d evidence=%@",task.terminationStatus,folder);
    if(cancelled){notifyICA(info,kICANotificationTypeTransactionCanceled,nil,NO);return userCanceledErr;}
    if(task.terminationStatus)return kICADeviceInternalErr;
    NSData *stream=[NSData dataWithContentsOfFile:raw options:NSDataReadingMappedIfSafe error:&error];
    if(!stream||stream.length>300*1024*1024)return kICADeviceInternalErr;
    activeInfo=info;int result=decode(stream,@"");activeInfo=NULL;
    if(result)return kICADeviceInternalErr;
    return notifyICA(info,kICANotificationTypeScannerScanDone,nil,NO);
}

static int testDelivery(ScannerObjectInfo *info) {
    NSString *folder=[NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
    if(![[NSFileManager defaultManager] createDirectoryAtPath:folder withIntermediateDirectories:NO attributes:nil error:NULL])return 1;
    NativeState *s=state(info);activeInfo=info;
    unsigned char bytes[]={255,0,0,0,255,0,0,0,255,255,255,255};
    NSArray *pages=@[@{@"width":@2,@"rows":@2,@"channels":@3,@"pixels":[NSData dataWithBytes:bytes length:sizeof(bytes)]}];
    for(NSString *format in @[@"public.png",@"public.jpeg",@"public.tiff",@"com.adobe.pdf",(__bridge NSString *)kICUTTypeRaw]) {
        s.request=@{@"width":@2,@"height":@2,@"document folder":folder,@"document format":format,@"document name":@"test",@"ColorSyncMode":@"Device RGB"};
        assert(deliverPages(pages,@"",300)==0);
    }
    NSArray *files=[[NSFileManager defaultManager] contentsOfDirectoryAtPath:folder error:NULL];assert(files.count==5);
    for(NSString *file in files) {
        NSData *data=[NSData dataWithContentsOfFile:[folder stringByAppendingPathComponent:file]];assert(data.length>0);
        if([file.pathExtension isEqual:@"raw"]) {
            assert(data.length==sizeof(ICARawFileHeader)+sizeof(bytes));
            ICARawFileHeader header;memcpy(&header,data.bytes,sizeof(header));assert(header.imageWidth==2&&header.imageHeight==2&&header.dpi==300);
            assert(!strcmp(header.colorSyncModeStr,"Device RGB"));
            assert(!memcmp((const char *)data.bytes+sizeof(header),bytes,sizeof(bytes)));
        }
    }
    for(id mode in @[@42,@"",[@"x" stringByPaddingToLength:64 withString:@"x" startingAtIndex:0]]) {
        s.request=@{@"width":@2,@"height":@2,@"document folder":folder,@"document format":(__bridge NSString *)kICUTTypeRaw,@"ColorSyncMode":mode};
        assert(deliverPages(pages,@"",300)==1);
    }
    s.request=@{@"width":@2,@"height":@2,@"document folder":folder,@"document format":@"public.jpeg",@"document extension":@"jpeg",@"document name":@"requested"};
    NSString *existing=[folder stringByAppendingPathComponent:@"requested.jpeg"];
    NSData *sentinel=[@"existing user file" dataUsingEncoding:NSUTF8StringEncoding];
    assert([sentinel writeToFile:existing options:NSDataWritingWithoutOverwriting error:NULL]);
    assert(deliverPages(@[pages[0],pages[0]],@"",300)==0);
    assert([[NSData dataWithContentsOfFile:existing] isEqual:sentinel]);
    for(NSString *name in @[@"requested 1.jpeg",@"requested 2.jpeg"]) {
        NSURL *url=[NSURL fileURLWithPath:[folder stringByAppendingPathComponent:name]];
        CGImageSourceRef source=CGImageSourceCreateWithURL((__bridge CFURLRef)url,NULL);
        assert(source&&CGImageSourceGetCount(source)==1);CFRelease(source);
    }
    NSMutableDictionary *bad=[s.request mutableCopy];bad[@"document extension"]=@"../pdf";s.request=bad;
    assert(deliverPages(pages,@"",300)==1);
    s.request=@{@"width":@2,@"height":@2,@"progressNotificationWithScanData":@YES};assert(deliverPages(pages,@"",300)==0);
    s.request=@{@"progressNotificationWithData":@YES};assert(deliverPages(pages,@"",300)==0);
    s.request=@{@"width":@2,@"height":@2,@"offsetX":@-1};assert(deliverPages(pages,@"",300)==1);
    activeInfo=NULL;assert([[NSFileManager defaultManager] removeItemAtPath:folder error:NULL]);return 0;
}
