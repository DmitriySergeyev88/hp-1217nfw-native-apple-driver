// Independent, bounded read-only Marvell2 protocol probe; no HP code linked.
#include <arpa/inet.h>
#include <errno.h>
#include <stdio.h>
#include <stdint.h>
#include <string.h>
#include <sys/socket.h>
#include <unistd.h>
#include <assert.h>
#include <stdlib.h>
#include <signal.h>

static volatile sig_atomic_t stop_io;
static void stop_test_io(int sig) {(void)sig;stop_io=1;}

static void header(uint32_t h[8], uint32_t command) {
    memset(h, 0, 32); h[0]=htonl(0x41535001); h[1]=htonl(command);
}
static int transfer(int fd, void *buffer, size_t size, int writing) {
    size_t done=0;
    while(done<size) {
        if(stop_io) {errno=EINTR;return -1;}
        ssize_t n=writing ? send(fd,(char *)buffer+done,size-done,0)
                          : recv(fd,(char *)buffer+done,size-done,0);
        if(n<0 && errno==EINTR) continue;
        if(n<=0) return -1;
        done+=(size_t)n;
    }
    return 0;
}
int main(int argc,char **argv) {
    uint32_t h[8];
    if(argc==2 && !strcmp(argv[1],"--test")) {
        header(h,15); const unsigned char *b=(void *)h;
        assert(!memcmp(b,"ASP\1",4)); assert(b[7]==15);
        for(int i=8;i<32;i++) assert(b[i]==0);
        int pair[2]; assert(socketpair(AF_UNIX,SOCK_STREAM,0,pair)==0);
        assert(transfer(pair[0],h,32,1)==0); uint32_t got[8];
        assert(transfer(pair[1],got,32,0)==0);assert(!memcmp(h,got,32));
        close(pair[0]);assert(transfer(pair[1],got,1,0)==-1);close(pair[1]);
        assert(socketpair(AF_UNIX,SOCK_STREAM,0,pair)==0);
        stop_io=1;assert(transfer(pair[1],got,1,0)==-1);stop_io=0;
        close(pair[0]);close(pair[1]);
        assert(socketpair(AF_UNIX,SOCK_STREAM,0,pair)==0);
        struct sigaction action={0},old;action.sa_handler=stop_test_io;sigemptyset(&action.sa_mask);
        assert(sigaction(SIGALRM,&action,&old)==0);alarm(1);
        assert(transfer(pair[1],got,1,0)==-1);assert(stop_io);alarm(0);stop_io=0;
        assert(sigaction(SIGALRM,&old,NULL)==0);close(pair[0]);close(pair[1]);
        puts("PASS header, transport, EOF, interrupted I/O");return 0;
    }
    if(argc!=2) {fprintf(stderr,"Usage: marvell_probe IPv4 | --test\n");return 2;}
    struct sockaddr_in addr={.sin_len=sizeof(addr),.sin_family=AF_INET,.sin_port=htons(8290)};
    if(inet_pton(AF_INET,argv[1],&addr.sin_addr)!=1) return 2;
    alarm(15);
    int fd=socket(AF_INET,SOCK_STREAM,0);if(fd<0)return 1;
    struct timeval timeout={3,0};int yes=1;
    if(setsockopt(fd,SOL_SOCKET,SO_RCVTIMEO,&timeout,sizeof(timeout)) ||
       setsockopt(fd,SOL_SOCKET,SO_SNDTIMEO,&timeout,sizeof(timeout)) ||
       setsockopt(fd,SOL_SOCKET,SO_NOSIGPIPE,&yes,sizeof(yes))) {close(fd);return 1;}
    if(connect(fd,(void *)&addr,sizeof(addr))) {perror("connect");close(fd);return 1;}
    // The vendor session starts with a one-way handshake before lock acquisition.
    header(h,21);
    if(transfer(fd,h,32,1)) {close(fd);return 1;}
    const uint32_t commands[]={0,15,6,1}; // Lock, ADF, settings, unlock. No scan.
    int result=0;
    for(size_t c=0;c<4;c++) {
        header(h,commands[c]);
        if(transfer(fd,h,32,1) || transfer(fd,h,32,0)) {perror("header I/O");result=1;break;}
        for(int i=0;i<8;i++)h[i]=ntohl(h[i]);
        if(h[0]!=0x41535001 || h[1]!=commands[c] || h[5]>4096) {
            fprintf(stderr,"Invalid response magic/command/length\n");result=1;break;
        }
        printf("command %u header:",commands[c]);for(int i=0;i<8;i++)printf(" %08x",h[i]);puts("");
        if(h[4] && commands[c]!=15) {fprintf(stderr,"Device rejected command\n");result=1;break;}
        unsigned char payload[4096];
        if(h[5] && transfer(fd,payload,h[5],0)) {perror("payload I/O");result=1;break;}
        if(commands[c]==6) {
            if(h[5]!=100) {fprintf(stderr,"Unexpected settings length\n");result=1;break;}
            for(unsigned i=0;i<100;i+=4) {uint32_t v;memcpy(&v,payload+i,4);printf("setting[%u]=%u\n",i/4,ntohl(v));}
        }
    }
    close(fd);return result;
}
