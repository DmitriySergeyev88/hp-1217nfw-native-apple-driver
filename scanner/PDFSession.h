#import <PDFKit/PDFKit.h>

static NSString *documentStem(NSString *name) {
    NSString *value=[name stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if([value.pathExtension.lowercaseString isEqual:@"pdf"])value=value.stringByDeletingPathExtension;
    if(!value.length||[value isEqual:@"."]||[value isEqual:@".."]||
       [value lengthOfBytesUsingEncoding:NSUTF8StringEncoding]>160||
       [value rangeOfCharacterFromSet:[NSCharacterSet characterSetWithCharactersInString:@"/:"]].location!=NSNotFound||
       [value rangeOfCharacterFromSet:NSCharacterSet.controlCharacterSet].location!=NSNotFound)return nil;
    return value;
}
static PDFDocument *combinePDFs(NSArray<NSURL *> *sources) {
    PDFDocument *result=[PDFDocument new];
    for(NSURL *url in sources) {
        PDFDocument *input=[[PDFDocument alloc] initWithURL:url];
        if(!input||input.isEncrypted||!input.pageCount||result.pageCount+input.pageCount>100)return nil;
        for(NSUInteger i=0;i<input.pageCount;i++) {
            PDFPage *page=[[input pageAtIndex:i] copy];if(!page)return nil;
            [result insertPage:page atIndex:result.pageCount];
        }
    }
    return result.pageCount?result:nil;
}
static BOOL saveCombinedPDF(NSArray<NSURL *> *sources,NSURL *destination,NSError **error) {
    PDFDocument *document=combinePDFs(sources);NSData *data=document.dataRepresentation;
    if(!data){if(error)*error=[NSError errorWithDomain:@"NativeScan" code:1 userInfo:@{NSLocalizedDescriptionKey:@"Не удалось собрать PDF (лимит 100 страниц). Исходные сканы сохранены."}];return NO;}
    return [data writeToURL:destination options:NSDataWritingWithoutOverwriting error:error];
}
static void testPDFSession(void) {
    assert([documentStem(@" Документ.pdf ") isEqual:@"Документ"]);
    for(NSString *bad in @[@"",@"..",@"a/b",@"a:b",@"line\nname"])assert(!documentStem(bad));
    NSURL *root=[NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString]];
    assert([[NSFileManager defaultManager] createDirectoryAtURL:root withIntermediateDirectories:NO attributes:nil error:NULL]);
    NSMutableArray *sources=[NSMutableArray new];
    for(int i=0;i<2;i++) {
        NSMutableData *data=[NSMutableData new];CGRect box=CGRectMake(0,0,100+i,200+i);
        CGDataConsumerRef consumer=CGDataConsumerCreateWithCFData((__bridge CFMutableDataRef)data);
        CGContextRef c=CGPDFContextCreate(consumer,&box,NULL);CGDataConsumerRelease(consumer);
        CGPDFContextBeginPage(c,NULL);CGContextSetRGBFillColor(c,i,0,1-i,1);CGContextFillRect(c,box);CGPDFContextEndPage(c);CGPDFContextClose(c);CGContextRelease(c);
        NSURL *url=[root URLByAppendingPathComponent:[NSString stringWithFormat:@"%d.pdf",i]];
        assert([data writeToURL:url options:NSDataWritingWithoutOverwriting error:NULL]);[sources addObject:url];
    }
    NSURL *out=[root URLByAppendingPathComponent:@"combined.pdf"];assert(saveCombinedPDF(sources,out,NULL));
    NSData *before=[NSData dataWithContentsOfURL:out];assert(!saveCombinedPDF(sources,out,NULL));
    assert([[NSData dataWithContentsOfURL:out] isEqual:before]);
    PDFDocument *doc=[[PDFDocument alloc] initWithURL:out];assert(doc.pageCount==2);
    for(int i=0;i<2;i++){CGRect box=[[doc pageAtIndex:i] boundsForBox:kPDFDisplayBoxMediaBox];assert(box.size.width==100+i&&box.size.height==200+i);}
    assert(!combinePDFs(@[]));assert(!combinePDFs(@[[root URLByAppendingPathComponent:@"missing.pdf"]]));
    [sources addObject:out];assert(combinePDFs(sources).pageCount==4);
    assert([[NSFileManager defaultManager] removeItemAtURL:root error:NULL]);
    puts("PASS PDF session: names, order, page dimensions, multi-batch merge, no overwrite");
}
