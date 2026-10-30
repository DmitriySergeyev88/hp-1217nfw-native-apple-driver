// Lossless sGray8 URF filter. Wire semantics checked against OpenPrinting CUPS
// cups/raster-stream.c; independently implemented shortest-path packet encoder.
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>
#include <signal.h>
#include <time.h>
#include <errno.h>

#define MAX_WIDTH 12000
#define MAX_HEIGHT 20000
static volatile sig_atomic_t cancelled;
static uint64_t input_bytes, output_bytes;
static unsigned dp[MAX_WIDTH+1], literal[MAX_WIDTH+1], repeat[MAX_WIDTH+1];
static uint16_t length[MAX_WIDTH+1];
static unsigned char kind[MAX_WIDTH+1], a[MAX_WIDTH], b[MAX_WIDTH], encoded[MAX_WIDTH*2];
static void stop(int sig) {(void)sig;cancelled=1;}
static void fail(const char *why) {fprintf(stderr,"ERROR: HP Native URF: %s\n",why);exit(1);}
static void read_exact(void *p,size_t n) {
    if(cancelled)fail("cancelled");
    size_t got=fread(p,1,n,stdin);input_bytes+=got;
    if(got!=n)fail("truncated input or read error");
}
static int byte(void) {unsigned char c;read_exact(&c,1);return c;}
static void write_exact(const void *p,size_t n) {
    if(cancelled)fail("cancelled");
    if(fwrite(p,1,n,stdout)!=n)fail("output error");output_bytes+=n;
}
static uint32_t be32(const unsigned char *p) {
    return ((uint32_t)p[0]<<24)|((uint32_t)p[1]<<16)|((uint32_t)p[2]<<8)|p[3];
}
static unsigned decode(unsigned char *row,unsigned w) {
    unsigned copies=(unsigned)byte()+1,x=0;
    while(x<w) {
        unsigned code=(unsigned)byte();
        if(code==128){memset(row+x,255,w-x);break;}
        unsigned n=code<128?code+1:257-code;
        if(n>w-x)fail("packet crosses row boundary");
        if(code<128)memset(row+x,byte(),n);else read_exact(row+x,n);
        x+=n;
    }
    return copies;
}
// O(width): two monotone queues select minimum-cost literal/repeat predecessors.
// Only standard 1..128 repeat / 2..128 literal packets are emitted; no new PDL.
static size_t encode(const unsigned char *row,unsigned w) {
    unsigned lh=0,lt=0,rh=0,rt=0,run=0;dp[0]=0;
    for(unsigned i=1;i<=w;i++) {
        if(i==1||row[i-1]!=row[i-2]){run=i-1;rh=rt=0;}
        unsigned j=i-1;
        while(rt>rh&&dp[repeat[rt-1]]>=dp[j])rt--;
        repeat[rt++]=j;
        unsigned lower=i>128?i-128:0;if(lower<run)lower=run;
        while(rh<rt&&repeat[rh]<lower)rh++;
        j=repeat[rh];dp[i]=dp[j]+2;length[i]=(uint16_t)(i-j);kind[i]=0;
        if(i>=2) {
            j=i-2;
            while(lt>lh&&(int)dp[literal[lt-1]]-(int)literal[lt-1]>=(int)dp[j]-(int)j)lt--;
            literal[lt++]=j;
            lower=i>128?i-128:0;
            while(lh<lt&&literal[lh]<lower)lh++;
            j=literal[lh];unsigned cost=dp[j]+1+i-j;
            if(cost<dp[i]){dp[i]=cost;length[i]=(uint16_t)(i-j);kind[i]=1;}
        }
    }
    size_t pos=dp[w];unsigned i=w;
    while(i) {
        unsigned n=length[i],start=i-n;
        if(kind[i]){pos-=n+1;encoded[pos]=(unsigned char)(257-n);memcpy(encoded+pos+1,row+start,n);}
        else {pos-=2;encoded[pos]=(unsigned char)(n-1);encoded[pos+1]=row[start];}
        i=start;
    }
    if(pos)fail("encoder invariant");return dp[w];
}
static void emit(const unsigned char *row,unsigned w,unsigned copies) {
    size_t size=encode(row,w);
    unsigned char count=(unsigned char)(copies-1);
    write_exact(&count,1);write_exact(encoded,size);
}
int main(int argc,char **argv) {
    // CUPS filter ABI: job-id user title copies options [filename]. No job text logged.
    if(argc!=1&&argc!=6&&argc!=7){fprintf(stderr,"Usage: hp-m1217-urf [job user title copies options [file]]\n");return 2;}
    if(argc==7&&!freopen(argv[6],"rb",stdin))fail("cannot open input");
    struct sigaction action={0};action.sa_handler=stop;sigemptyset(&action.sa_mask);
    sigaction(SIGTERM,&action,NULL);sigaction(SIGINT,&action,NULL);signal(SIGPIPE,SIG_IGN);
    unsigned char header[32],file[12];read_exact(file,12);
    if(memcmp(file,"UNIRAST\0",8))fail("expected Apple URF input");
    unsigned expected=be32(file+8),pages=0;if(expected>10000)fail("page count limit");
    write_exact(file,12);clock_t started=clock();
    for(;;) {
        if(cancelled)fail("cancelled");
        size_t n=fread(header,1,32,stdin);input_bytes+=n;
        if(!n){if(ferror(stdin))fail("read error");break;}
        if(n!=32)fail("truncated page header");
        if(++pages>10000||(expected&&pages>expected))fail("page count mismatch");
        unsigned w=be32(header+12),h=be32(header+16);
        if(header[0]!=8||header[1]!=0||be32(header+20)!=600||!w||!h||w>MAX_WIDTH||h>MAX_HEIGHT)
            fail("requires 600 dpi, 8-bit sGray, bounded full page");
        write_exact(header,32);
        unsigned y=0,pending=0;
        while(y<h) {
            unsigned copies=decode(b,w);if(copies>h-y)fail("row repeats exceed page");y+=copies;
            if(pending&&memcmp(a,b,w)){emit(a,w,pending);pending=0;}
            if(!pending)memcpy(a,b,w);
            while(copies) {
                unsigned take=copies<256-pending?copies:256-pending;
                pending+=take;copies-=take;
                if(pending==256){emit(a,w,pending);pending=0;}
            }
        }
        if(pending)emit(a,w,pending);
        if(fflush(stdout))fail("flush error");
        fprintf(stderr,"INFO: HP Native URF page=%u pixels=%ux%u dpi=600 gray=8\n",pages,w,h);
    }
    if(!pages||(expected&&pages!=expected))fail("missing pages");
    if(fflush(stdout))fail("flush error");
    fprintf(stderr,"INFO: HP Native URF pages=%u input=%llu output=%llu cpu=%.3fs\n",pages,
        (unsigned long long)input_bytes,(unsigned long long)output_bytes,(double)(clock()-started)/CLOCKS_PER_SEC);
    return 0;
}
