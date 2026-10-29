// Experimental native capture. Saves framed wire data locally for decoder research.
#define main probe_main
#include "marvell_probe.c"
#undef main
#include <signal.h>
#include <time.h>
static volatile sig_atomic_t interrupted;
static void interrupt_capture(int sig) {(void)sig;interrupted=1;stop_io=1;}
static int reply(int fd,uint32_t h[8]) {
    if(transfer(fd,h,32,0))return -1;
    for(int i=0;i<8;i++)h[i]=ntohl(h[i]);
    return h[0]==0x41535001 && h[5]<=8*1024*1024 ? 0:-1;
}
static int command(int fd,uint32_t cmd,uint32_t h[8]) {
    header(h,cmd);
    if(transfer(fd,h,32,1)||reply(fd,h))return -1;
    fprintf(stderr,"command=%u reply=%u status=%u length=%u\n",cmd,h[1],h[4],h[5]);
    return h[1]==cmd && h[4]==0 ? 0:-1;
}
static int settings(int fd,const uint32_t values[25]) {
    uint32_t packet[33],h[8];header(packet,7);packet[5]=htonl(100);
    for(int i=0;i<25;i++)packet[8+i]=htonl(values[i]);
    if(transfer(fd,packet,sizeof(packet),1)||reply(fd,h))return -1;
    fprintf(stderr,"settings reply command=%u status=%u length=%u\n",h[1],h[4],h[5]);
    return h[1]!=7||h[4]!=0||h[5]!=0 ? -1:0;
}
static int acquire(int fd,uint32_t h[8]) {
    // A real two-sheet ADF job remained busy for more than 10s after EndJob.
    for(int attempt=0;attempt<120&&!interrupted;attempt++) {
        if(command(fd,0,h)==0)return h[5]? -1:0;
        if(h[1]!=0 || h[4]!=2 || h[5])return -1;
        struct timespec pause={0,250000000};nanosleep(&pause,NULL);
    }
    return -1;
}
int main(int argc,char **argv) {
    int restoring=argc==4 && !strcmp(argv[1],"--restore");
    int checking=argc==3 && !strcmp(argv[1],"--check");
    unsigned dpi=150,source=0x100,color=1,area=200;
    if(argc==7) {
        char *end;unsigned long value=strtoul(argv[3],&end,10);
        if(*end || (value!=75&&value!=150&&value!=300&&value!=600))return 2;dpi=(unsigned)value;
        if(!strcmp(argv[4],"adf"))source=0x200;else if(strcmp(argv[4],"flatbed"))return 2;
        if(source==0x200&&dpi>300)return 2;
        if(!strcmp(argv[5],"gray"))color=0;else if(strcmp(argv[5],"color"))return 2;
        if(!strcmp(argv[6],"a4"))area=1169;else if(strcmp(argv[6],"small"))return 2;
    } else if(argc!=3 && !restoring) {fprintf(stderr,"Usage: marvell_capture IPv4 NEW_CAPTURE_FILE [75|150|300|600 flatbed|adf color|gray small|a4] | --restore IPv4 SETTINGS_FILE\n");return 2;}
    struct sockaddr_in addr={.sin_len=sizeof(addr),.sin_family=AF_INET,.sin_port=htons(8290)};
    if(inet_pton(AF_INET,argv[restoring||checking?2:1],&addr.sin_addr)!=1)return 2;
    FILE *out=restoring||checking?NULL:fopen(argv[2],"wbx");if(!restoring&&!checking&&!out){perror("output");return 1;}
    int fd=socket(AF_INET,SOCK_STREAM,0),locked=0,started=0,changed=0,result=1;
    uint32_t h[8],original[25],values[25];size_t total=0;
    struct timeval timeout={45,0};int yes=1;
    struct timespec begin,end;clock_gettime(CLOCK_MONOTONIC,&begin);
    struct sigaction action={0};action.sa_handler=interrupt_capture;sigemptyset(&action.sa_mask);
    if(sigaction(SIGINT,&action,NULL)||sigaction(SIGTERM,&action,NULL)||sigaction(SIGALRM,&action,NULL)){perror("signal setup");goto cleanup;}
    alarm(180);
    if(fd<0){perror("socket");goto cleanup;}
    if(setsockopt(fd,SOL_SOCKET,SO_RCVTIMEO,&timeout,sizeof(timeout))||
       setsockopt(fd,SOL_SOCKET,SO_SNDTIMEO,&timeout,sizeof(timeout))||
       setsockopt(fd,SOL_SOCKET,SO_NOSIGPIPE,&yes,sizeof(yes))){perror("socket options");goto cleanup;}
    if(connect(fd,(void *)&addr,sizeof(addr))){perror("connect scanner TCP 8290");result=3;goto cleanup;}
    if(checking){fprintf(stderr,"TCP connection PASS; no scan commands sent\n");result=0;goto cleanup;}
    header(h,21);if(transfer(fd,h,32,1)||acquire(fd,h))goto cleanup;
    locked=1;
    if(restoring) {
        FILE *in=fopen(argv[3],"rb");
        if(!in)goto cleanup;
        size_t n=fread(original,1,100,in);int extra=fgetc(in);fclose(in);
        if(n!=100||extra!=EOF)goto cleanup;
        for(int i=0;i<25;i++)original[i]=ntohl(original[i]);
        result=settings(fd,original)?1:0;goto cleanup;
    }
    if(command(fd,6,h)||h[5]!=100||transfer(fd,original,100,0))goto cleanup;
    char *backup=NULL;
    if(asprintf(&backup,"%s.settings",argv[2])<0)goto cleanup;
    FILE *saved=fopen(backup,"wbx");free(backup);if(!saved)goto cleanup;
    int saveFailed=fwrite(original,1,100,saved)!=100;if(fclose(saved))saveFailed=1;
    if(saveFailed)goto cleanup;
    for(int i=0;i<25;i++)original[i]=ntohl(original[i]);
    memcpy(values,original,100);
    values[3]=dpi;values[14]=(values[14]&0x11110011)|source;values[24]=color;
    values[16]=0;values[17]=0;values[18]=area;values[19]=area==200?200:827;
    if(settings(fd,values))goto cleanup;
    changed=1;
    if(command(fd,2,h)||h[5])goto cleanup;
    started=1;
    while(!interrupted && total<128*1024*1024) {
        if(reply(fd,h))break;
        printf("event=%u status=%u payload=%u\n",h[1],h[4],h[5]);fflush(stdout);
        uint32_t wire[8];for(int i=0;i<8;i++)wire[i]=htonl(h[i]);
        if(fwrite(wire,1,32,out)!=32)break;
        unsigned char *data=malloc(h[5]?h[5]:1);if(!data)break;
        int bad=transfer(fd,data,h[5],0)||fwrite(data,1,h[5],out)!=h[5];
        total+=h[5];free(data);if(bad)break;
        if(h[1]==24) {header(wire,24);if(transfer(fd,wire,32,1))break;}
        if(h[1]==12) {result=0;started=0;break;}
        if(h[1]==4) {started=0;break;}
        if(h[1]!=5 && h[1]!=9 && h[1]!=10 && h[1]!=11 && h[1]!=13 && h[1]!=14 && h[1]!=24)break;
    }
cleanup:
    // Allow a bounded best-effort abort after the main deadline interrupted I/O.
    if(interrupted) {stop_io=0;alarm(10);}
    if(started) {header(h,3);(void)transfer(fd,h,32,1);}
    // Only restore settings after a completed stream, never while image data is pending.
    if(changed && !started) {
        if(command(fd,1,h))result=1;
        else {
            locked=0;
            if(acquire(fd,h))result=1;
            else {locked=1;if(settings(fd,original))result=1;}
        }
    }
    if(locked && !started && (command(fd,1,h)||h[5]))result=1;
    if(fd>=0)close(fd);
    if(out && fclose(out))result=1;
    alarm(0);clock_gettime(CLOCK_MONOTONIC,&end);
    double elapsed=end.tv_sec-begin.tv_sec+(end.tv_nsec-begin.tv_nsec)/1e9;
    fprintf(stderr,"capture result=%d bytes=%zu interrupted=%d seconds=%.3f\n",result,total,interrupted,elapsed);
    return result;
}
