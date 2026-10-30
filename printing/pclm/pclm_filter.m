// Native URF -> PCLm, firmware 20200618: numeric delimiters and strip dispatch order matter.
#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import <ImageIO/ImageIO.h>
#include <signal.h>
#include <stdint.h>
#include <stdarg.h>
#include <spawn.h>
#include <unistd.h>
#include <sys/wait.h>
#include <errno.h>
extern char **environ;
static pid_t renderer;
static volatile sig_atomic_t stopped;
static FILE *document;
static NSMutableArray<NSNumber *> *offsets, *pages;
static unsigned char row[5100], strip[5100*128];
static void stop(int sig) { (void)sig; stopped=1;if(renderer>0)kill(renderer,SIGTERM); }
static void cleanup(void) {
    if(renderer>0){kill(renderer,SIGKILL);while(waitpid(renderer,NULL,0)<0&&errno==EINTR){}renderer=0;}
}
static void fail(const char *message) { fprintf(stderr,"ERROR: HP PCLm: %s\n",message);exit(1); }
// CUPS supplies the final PCLm MIME to every filter. Force URF only for Apple's child.
static void start_renderer(int argc,char **argv) {
    const char *type=getenv("CONTENT_TYPE");
    if(!type||strcmp(type,"application/pdf")) {
        if(argc==7&&!freopen(argv[6],"rb",stdin))fail("cannot open input");
        return;
    }
    if(argc!=6&&argc!=7)fail("PDF requires CUPS arguments");
    int pipefd[2];if(pipe(pipefd))fail("cannot create renderer pipe");
    posix_spawn_file_actions_t actions;
    if(posix_spawn_file_actions_init(&actions)||
       posix_spawn_file_actions_adddup2(&actions,pipefd[1],STDOUT_FILENO)||
       posix_spawn_file_actions_addclose(&actions,pipefd[0])||
       posix_spawn_file_actions_addclose(&actions,pipefd[1]))fail("renderer actions failed");
    size_t n=0;while(environ[n])n++;
    char **env=calloc(n+2,sizeof(char *));if(!env)fail("allocation failed");
    size_t j=0;for(size_t i=0;i<n;i++)
        if(strncmp(environ[i],"FINAL_CONTENT_TYPE=",19))env[j++]=environ[i];
    env[j++]="FINAL_CONTENT_TYPE=image/urf";env[j]=NULL;
    char *args[8]={"/usr/libexec/cups/filter/cgpdftoraster",NULL};
    for(int i=1;i<argc;i++)args[i]=argv[i];
    int error=posix_spawn(&renderer,args[0],&actions,NULL,args,env);
    posix_spawn_file_actions_destroy(&actions);free(env);close(pipefd[1]);
    if(error){close(pipefd[0]);renderer=0;fail("cannot launch Apple rasterizer");}
    if(dup2(pipefd[0],STDIN_FILENO)<0)fail("cannot connect rasterizer");close(pipefd[0]);
}
static void finish_renderer(void) {
    if(renderer>0){int status;pid_t p;
        do{p=waitpid(renderer,&status,0);}while(p<0&&errno==EINTR);
        renderer=0;if(p<0||!WIFEXITED(status)||WEXITSTATUS(status))fail("Apple rasterizer failed");
    }
}
static void read_exact(void *p,size_t n) {
    if(stopped)fail("cancelled");
    if(fread(p,1,n,stdin)!=n)fail("truncated input");
}
static unsigned byte(void) { unsigned char c;read_exact(&c,1);return c; }
static unsigned be32(const unsigned char *p) { return (unsigned)p[0]<<24|(unsigned)p[1]<<16|(unsigned)p[2]<<8|p[3]; }
static void put(const void *p,size_t n) {
    if(stopped)fail("cancelled");
    if(fwrite(p,1,n,document)!=n)fail("temporary output write failed");
    if(ftello(document)>2147483647)fail("document exceeds 2 GiB limit");
}
static void text(NSString *s) { NSData *d=[s dataUsingEncoding:NSASCIIStringEncoding];if(!d)fail("internal text encoding");put(d.bytes,d.length); }
static void object(unsigned n,NSString *body) {
    while(offsets.count<=n)[offsets addObject:@0];
    offsets[n]=@(ftello(document));text([NSString stringWithFormat:@"%u 0 obj\n%@\nendobj\n",n,body]);
}
static void stream(unsigned n,NSString *attrs,NSData *data) {
    while(offsets.count<=n)[offsets addObject:@0];
    offsets[n]=@(ftello(document));
    // The firmware consumes two bytes after a number. Bits must follow ALL other fields.
    text([NSString stringWithFormat:@"%u 0 obj\n<<\n/Length %lu \n%@\n>>\nstream\n",n,(unsigned long)data.length,attrs]);
    put(data.bytes,data.length);text(@"\nendstream\nendobj\n");
}
static NSData *jpeg(unsigned w,unsigned h) {
    CGColorSpaceRef cs=CGColorSpaceCreateDeviceGray();
    CGDataProviderRef provider=CGDataProviderCreateWithData(NULL,strip,(size_t)w*h,NULL);
    CGImageRef image=CGImageCreate(w,h,8,8,w,cs,(CGBitmapInfo)kCGImageAlphaNone,provider,NULL,false,kCGRenderingIntentDefault);
    if(!image)fail("gray strip image creation failed");
    NSMutableData *data=[NSMutableData data];
    CGImageDestinationRef dest=CGImageDestinationCreateWithData((__bridge CFMutableDataRef)data,CFSTR("public.jpeg"),1,NULL);
    if(!dest)fail("JPEG encoder unavailable");
    NSDictionary *opts=@{(__bridge NSString *)kCGImageDestinationLossyCompressionQuality:@0.90,
        (__bridge NSString *)kCGImagePropertyDPIWidth:@600,(__bridge NSString *)kCGImagePropertyDPIHeight:@600,
        (__bridge NSString *)kCGImagePropertyJFIFDictionary:@{(__bridge NSString *)kCGImagePropertyJFIFIsProgressive:@NO}};
    CGImageDestinationAddImage(dest,image,(__bridge CFDictionaryRef)opts);
    bool ok=CGImageDestinationFinalize(dest);
    CFRelease(dest);CGImageRelease(image);CGDataProviderRelease(provider);CGColorSpaceRelease(cs);
    if(!ok||!data.length)fail("JPEG encoding failed");return data;
}
static unsigned decode(unsigned w) {
    unsigned copies=byte()+1,x=0;
    while(x<w) {
        unsigned code=byte();if(code==128){memset(row+x,255,w-x);break;}
        unsigned n=code<128?code+1:257-code;if(n>w-x)fail("URF packet crosses row boundary");
        if(code<128)memset(row+x,byte(),n);else read_exact(row+x,n);x+=n;
    }
    return copies;
}
int main(int argc,char **argv) { @autoreleasepool {
    if(argc!=1&&argc!=6&&argc!=7)fail("invalid CUPS arguments");
    atexit(cleanup);
    struct sigaction action={0};action.sa_handler=stop;sigemptyset(&action.sa_mask);
    sigaction(SIGTERM,&action,NULL);sigaction(SIGINT,&action,NULL);signal(SIGPIPE,SIG_IGN);
    start_renderer(argc,argv);
    unsigned char head[32],file[12];read_exact(file,12);
    if(memcmp(file,"UNIRAST\0",8))fail("expected URF raster");
    unsigned expected=be32(file+8),next=3,count=0;if(expected>10000)fail("page limit");
    document=tmpfile();if(!document)fail("cannot create private temporary document");
    offsets=[NSMutableArray arrayWithObjects:@0,@0,@0,nil];pages=[NSMutableArray array];text(@"%PDF-1.7\n%PCLm 1.0\n");
    for(;;) { @autoreleasepool {
        if(stopped)fail("cancelled");
        size_t n=fread(head,1,32,stdin);if(!n){if(ferror(stdin))fail("input read error");break;}
        if(n!=32)fail("truncated page header");
        if(++count>10000||(expected&&count>expected))fail("page count mismatch");
        unsigned w=be32(head+12),h=be32(head+16);
        if(head[0]!=8||head[1]!=0||be32(head+20)!=600||!w||w>5100||!h||h>20000)
            fail("requires gray8 600 dpi raster, width <= 5100");
        unsigned page=next,content=next+1,first=next+2,parts=(h+127)/128;next+=2+2*parts;
        NSMutableString *resources=[NSMutableString string],*ops=[NSMutableString stringWithString:@"0.12000000 0 0 0.12000000 0 0 cm"];
        for(unsigned i=0;i<parts;i++) {
            unsigned rows=MIN(128,h-i*128);
            [resources appendFormat:@"/Image%u %u 0 R ",i,first+2*i];
            [ops appendFormat:@"\n/P <</MCID 0>> BDC q\n%u 0 0 %u 0 %u cm\n/Image%u Do Q EMC",w,rows,h-i*128-rows,i];
        }
        // Integer canvas contains the exact raster; no pixel rescaling here.
        object(page,[NSString stringWithFormat:@"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 %u %u] /Resources << /XObject << %@ >> >> /Contents [%u 0 R] >>",(w*72+599)/600,(h*72+599)/600,resources,content]);
        stream(content,@"",[ops dataUsingEncoding:NSASCIIStringEncoding]);
        unsigned y=0,repeats=0;
        for(unsigned i=0;i<parts;i++) { @autoreleasepool {
            unsigned rows=MIN(128,h-y);
            for(unsigned j=0;j<rows;j++,y++) {
                if(!repeats){repeats=decode(w);if(repeats>h-y)fail("URF row repeat exceeds page");}
                memcpy(strip+(size_t)j*w,row,w);repeats--;
            }
            NSString *attrs=[NSString stringWithFormat:@"/Type /XObject\n/Subtype /Image\n/Width %u \n/Height %u \n/ColorSpace /DeviceGray\n/Name /ColorStrip\n/Filter /DCTDecode\n/BitsPerComponent 8 \n",w,rows];
            stream(first+2*i,attrs,jpeg(w,rows));stream(first+2*i+1,@"",[@"q /Image Do Q\n" dataUsingEncoding:NSASCIIStringEncoding]);
        }}
        [pages addObject:@(page)];fprintf(stderr,"INFO: HP PCLm page=%u pixels=%ux%u dpi=600 gray=8 JPEG=90\n",count,w,h);
    }}
    finish_renderer();
    if(!count||(expected&&count!=expected))fail("missing pages");
    object(1,@"<< /Type /Catalog /Pages 2 0 R >>");
    NSMutableString *kids=[NSMutableString string];for(NSNumber *p in pages)[kids appendFormat:@"%@ 0 R ",p];
    object(2,[NSString stringWithFormat:@"<< /Type /Pages /Count %u /Kids [%@] >>",count,kids]);
    off_t xref=ftello(document);text([NSString stringWithFormat:@"xref\n0 %u\n0000000000 65535 f \n",next]);
    for(unsigned i=1;i<next;i++)text([NSString stringWithFormat:@"%010lld 00000 n \n",offsets[i].longLongValue]);
    text([NSString stringWithFormat:@"trailer\n<< /Size %u /Root 1 0 R >>\nstartxref\n%lld\n%%%%EOF\n",next,(long long)xref]);
    if(fflush(document)||fseeko(document,0,SEEK_SET))fail("temporary file rewind failed");
    unsigned char buffer[65536];size_t n;
    while((n=fread(buffer,1,sizeof(buffer),document))) {
        if(stopped)fail("cancelled");if(fwrite(buffer,1,n,stdout)!=n)fail("output error");
    }
    if(ferror(document)||fflush(stdout))fail("output flush failed");fclose(document);
    return 0;
}}
