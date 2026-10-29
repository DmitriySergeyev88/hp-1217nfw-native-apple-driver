#import <Foundation/Foundation.h>
#import <ImageIO/ImageIO.h>
#import <CoreGraphics/CoreGraphics.h>
#include <arpa/inet.h>
#include <assert.h>
static uint32_t u32(const unsigned char *p) {uint32_t v;memcpy(&v,p,4);return ntohl(v);}
static void rgbrow(unsigned char *out,const unsigned char *in,size_t width) {
    for(size_t x=0;x<width;x++) {out[3*x]=in[width+x];out[3*x+1]=in[2*width+x];out[3*x+2]=in[x];}
}
static void mirrorrow(unsigned char *row,size_t width,size_t channels) {
    for(size_t x=0;x<width/2;x++)for(size_t c=0;c<channels;c++) {
        size_t a=x*channels+c,b=(width-1-x)*channels+c;
        unsigned char value=row[a];row[a]=row[b];row[b]=value;
    }
}
static int exportPages(NSArray *pages,NSString *base,uint32_t dpi);
static int decode(NSData *stream,NSString *base) {
    const unsigned char *b=stream.bytes;size_t n=stream.length,pos=0,width=0,rows=0,expected=0,planeRows=0;
    uint32_t dpi=0,channels=0;BOOL page=NO,ended=NO,job=NO,adf=NO,partial=NO;
    NSMutableData *pixels=[NSMutableData data];
    NSMutableArray *pages=[NSMutableArray array];size_t totalPixels=0;
    while(pos<n) {
        if(n-pos<32||u32(b+pos)!=0x41535001)return 1;
        uint32_t cmd=u32(b+pos+4),len=u32(b+pos+20),status=u32(b+pos+16);pos+=32;
        if(len>n-pos||len>8*1024*1024||status||ended)return 1;
        const unsigned char *p=b+pos;pos+=len;
        if(cmd==9) {
            if(job||len!=100)return 1;job=YES;dpi=u32(p+12);
            adf=(u32(p+56)&0x300)==0x200;
            uint32_t top=u32(p+64),bottom=u32(p+72);
            if(!dpi||dpi>1200||bottom<=top||bottom-top>1500)return 1;
            expected=(uint64_t)(bottom-top)*dpi/100;
        } else if(cmd==11) {if(!job||page||rows||len||pages.count>=100)return 1;page=YES;
        } else if(cmd==5) {
            if(!page||partial||len<24)return 1;
            uint32_t type=u32(p),start=u32(p+4),count=u32(p+8),sample=u32(p+12),w=u32(p+20);
            uint32_t ch=(type==10||type==12)?3:type==6?1:0;
            if(type==12&&!adf)return 1;
            if(!ch||!w||w>12000||!count||sample!=1||start!=planeRows||(!adf&&count%ch)||
               (width&&width!=w)||(channels&&channels!=ch)||(uint64_t)w*count!=len-24)return 1;
            width=w;channels=ch;size_t add=count/ch;
            if(rows+add>expected||totalPixels+pixels.length+(uint64_t)w*count>256*1024*1024)return 1;
            partial=count%ch!=0;
            if(partial)fprintf(stderr,"ADF incomplete final color row: %u channel plane(s), preserved in ASP capture; not synthesized in export\n",count%ch);
            NSUInteger old=pixels.length;[pixels increaseLengthBy:w*add*ch];unsigned char *dst=(unsigned char *)pixels.mutableBytes+old;
            for(size_t y=0;y<add;y++) {
                if(ch==3)rgbrow(dst+y*w*3,p+24+y*w*3,w);
                else memcpy(dst+y*w,p+24+y*w,w);
                if(type==12)mirrorrow(dst+y*w*ch,w,ch);
            }
            rows+=add;planeRows+=count;
        // Firmware can round the requested extent down by one row. Require EndPage,
        // retain the received pixels and DPI; never interpolate to the requested size.
        } else if(cmd==14) {if(!page||len||!rows||rows>expected||(!adf&&expected-rows>1))return 1;
            [pages addObject:@{@"pixels":[pixels copy],@"width":@(width),@"rows":@(rows),@"channels":@(channels)}];
            fprintf(stderr,"page %lu: %zux%zu channels=%u dpi=%u\n",(unsigned long)pages.count,width,rows,channels,dpi);
            totalPixels+=pixels.length;pixels=[NSMutableData data];width=rows=planeRows=channels=0;partial=NO;page=NO;
        } else if(cmd==12) {if(page||!pages.count||len)return 1;ended=YES;
        } else if((cmd!=10&&cmd!=13)||len)return 1;
    }
    if(!ended||page||!pages.count)return 1;
    return exportPages(pages,base,dpi);
}

static int exportPages(NSArray *pages,NSString *base,uint32_t dpi) {
#ifdef MARVELL_PAGE_CONSUMER
    return MARVELL_PAGE_CONSUMER(pages,base,dpi);
#else
    NSMutableArray *stems=[NSMutableArray array];
    NSMutableArray *paths=[NSMutableArray arrayWithObject:[base stringByAppendingPathExtension:@"pdf"]];
    for(NSUInteger i=0;i<pages.count;i++) {
        NSString *stem=pages.count==1?base:[base stringByAppendingFormat:@"-page-%03lu",(unsigned long)i+1];
        [stems addObject:stem];
        for(NSString *ext in @[@"png",@"jpg"]) [paths addObject:[stem stringByAppendingPathExtension:ext]];
    }
    for(NSString *path in paths)if([[NSFileManager defaultManager] fileExistsAtPath:path])return 1;
    NSMutableData *pdf=[NSMutableData data];
    CGDataConsumerRef consumer=CGDataConsumerCreateWithCFData((__bridge CFMutableDataRef)pdf);
    if(!consumer)return 1;
    CGContextRef context=CGPDFContextCreate(consumer,NULL,NULL);CGDataConsumerRelease(consumer);
    if(!context)return 1;
    int result=0;
    for(NSUInteger i=0;i<pages.count&&!result;i++) {
        NSDictionary *page=pages[i];NSData *pixels=page[@"pixels"];
        size_t width=[page[@"width"] unsignedLongValue],rows=[page[@"rows"] unsignedLongValue],channels=[page[@"channels"] unsignedLongValue];
        CGColorSpaceRef space=channels==3?CGColorSpaceCreateDeviceRGB():CGColorSpaceCreateDeviceGray();
        CGDataProviderRef provider=CGDataProviderCreateWithCFData((__bridge CFDataRef)pixels);
        CGImageRef image=CGImageCreate(width,rows,8,8*channels,width*channels,space,(CGBitmapInfo)kCGImageAlphaNone,provider,NULL,false,kCGRenderingIntentDefault);
        CGDataProviderRelease(provider);CGColorSpaceRelease(space);if(!image){result=1;break;}
        CGRect rect=CGRectMake(0,0,width*72.0/dpi,rows*72.0/dpi);
        NSDictionary *box=@{(__bridge NSString *)kCGPDFContextMediaBox:[NSData dataWithBytes:&rect length:sizeof(rect)]};
        CGPDFContextBeginPage(context,(__bridge CFDictionaryRef)box);CGContextDrawImage(context,rect,image);CGPDFContextEndPage(context);
        for(NSString *ext in @[@"png",@"jpg"]) {
            NSMutableData *data=[NSMutableData data];
            CFStringRef uti=[ext isEqualToString:@"png"]?CFSTR("public.png"):CFSTR("public.jpeg");
            CGImageDestinationRef destination=CGImageDestinationCreateWithData((__bridge CFMutableDataRef)data,uti,1,NULL);
            if(!destination){result=1;break;}
            NSDictionary *props=@{(__bridge NSString *)kCGImagePropertyDPIWidth:@(dpi),(__bridge NSString *)kCGImagePropertyDPIHeight:@(dpi),(__bridge NSString *)kCGImageDestinationLossyCompressionQuality:@1.0};
            CGImageDestinationAddImage(destination,image,(__bridge CFDictionaryRef)props);
            if(!CGImageDestinationFinalize(destination))result=1;CFRelease(destination);if(result)break;
            NSError *error=nil;
            if(![data writeToFile:[stems[i] stringByAppendingPathExtension:ext] options:NSDataWritingWithoutOverwriting error:&error]) {NSLog(@"Output error %@",error);result=1;break;}
        }
        CGImageRelease(image);
    }
    CGPDFContextClose(context);CGContextRelease(context);
    if(!result) {
        NSError *error=nil;
        if(![pdf writeToFile:[base stringByAppendingPathExtension:@"pdf"] options:NSDataWritingWithoutOverwriting error:&error]){NSLog(@"PDF output error %@",error);result=1;}
    }
    return result;
#endif
}

int main(int argc,char **argv) {
    @autoreleasepool {
        if(argc==2&&!strcmp(argv[1],"--test")) {
            unsigned char input[]={30,31,10,11,20,21},output[6];rgbrow(output,input,2);
            const unsigned char wanted[]={10,20,30,11,21,31};assert(!memcmp(output,wanted,6));
            mirrorrow(output,2,3);const unsigned char mirrored[]={11,21,31,10,20,30};assert(!memcmp(output,mirrored,6));
            assert(decode([NSData data],@"/invalid")==1);puts("PASS channel order and empty-stream rejection");return 0;
        }
        if(argc!=3)return 2;
        NSString *path=[NSString stringWithUTF8String:argv[1]];NSError *error=nil;
        NSDictionary *attr=[[NSFileManager defaultManager] attributesOfItemAtPath:path error:&error];
        if(!attr||[attr fileSize]>300*1024*1024)return 1;
        NSData *data=[NSData dataWithContentsOfFile:path options:NSDataReadingMappedIfSafe error:&error];
        if(!data)return 1;
        return decode(data,[NSString stringWithUTF8String:argv[2]]);
    }
}
