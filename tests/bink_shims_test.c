// Authored Bink header + deterministic native backend exercise the actual guest ABI.
#include "shims.h"
#include "FNVNativeMedia.h"
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
uint8_t *MEM;static unsigned heap=0x80000;static int failed,opened,closed,paused;static double clock_value;static unsigned decoded;
uint32_t gmalloc(uint32_t n){unsigned p=heap;heap+=n+16;return p;}void gfree(uint32_t p){(void)p;}
void host_path(const char *p,char *out,size_t n){snprintf(out,n,"%s",p);}
int fnv_audio_start(void){return 1;}
uintptr_t fnv_video_open(const char *path){if(strcmp(path,"NativeMedia/author.mp4"))abort();opened++;return 42;}
double fnv_video_time(uintptr_t m){if(m!=42)abort();return clock_value;}
int fnv_video_decode(uintptr_t m,unsigned frame){if(m!=42)abort();decoded=frame;return frame<=3;}
int fnv_video_copy(uintptr_t m,void *out,int pitch,unsigned h,unsigned dx,unsigned dy,unsigned sx,unsigned sy,unsigned w,unsigned ht,unsigned fmt){
    if(m!=42||pitch!=16||h!=2||dx||dy||sx||sy||w!=4||ht!=2||fmt!=3||!decoded)abort();memset(out,0x7e,32);return 1;
}
void fnv_video_pause(uintptr_t m,int p){if(m!=42)abort();paused=p;}void fnv_video_close(uintptr_t m){if(m!=42)abort();closed++;}
extern const ShimTable media_shims;
static void check(const char *name,int ok){printf("%s: %s\n",ok?"PASS":"FAIL",name);failed+=!ok;}
static unsigned call(const char *name,const uint32_t *args,unsigned n){CPU c={0};SETREG(&c,R_ESP,0x1000);P32(0x1000,0x123456);for(unsigned i=0;i<n;i++)P32(0x1004+4*i,args[i]);
    for(int i=0;i<media_shims.count;i++)if(!strcmp(media_shims.list[i].name,name)){media_shims.list[i].fn(&c);if(REG(&c,R_ESP)!=0x1004+4*n)abort();return REG(&c,R_EAX);}abort();}
#define CALL(name,...) call(name,(uint32_t[]){__VA_ARGS__},sizeof((uint32_t[]){__VA_ARGS__})/4)
int main(void){
    MEM=calloc(1,4<<20);char dir[]="/tmp/fnv-bink-test-XXXXXX";if(!mkdtemp(dir)||chdir(dir))abort();
    uint32_t header[11]={0};memcpy(header,"BIKi",4);header[1]=100;header[2]=3;header[5]=4;header[6]=2;header[7]=30;header[8]=1;header[10]=1;
    FILE *f=fopen("author.bik","wb");fwrite(header,1,44,f);fclose(f);strcpy((char*)MEM+0x2000,"author.bik");
    unsigned h=CALL("_BinkOpen@8",0x2000,0);check("original header becomes valid guest BINK metadata",h&&opened==1&&G32(h)==4&&G32(h+4)==2&&G32(h+8)==3&&G32(h+12)==1);
    check("first movie frame is ready",CALL("_BinkWait@4",h)==0);CALL("_BinkDoFrame@4",h);check("DoFrame decodes actual selected native frame",decoded==1&&!G32(h+28));
    check("copy returns success and writes decoded pixels",CALL("_BinkCopyToBufferRect@44",h,0x3000,16,2,0,0,0,0,4,2,0x80000003)==1&&MEM[0x3000]==0x7e);
    CALL("_BinkNextFrame@4",h);check("guest frame progression waits for native media clock",G32(h+12)==2&&CALL("_BinkWait@4",h)==1);clock_value=1.0/30;check("media clock releases next frame",CALL("_BinkWait@4",h)==0);
    check("pause reports previous state",CALL("_BinkPause@8",h,1)==0&&paused&&CALL("_BinkWait@4",h)==1);check("resume restores playback",CALL("_BinkPause@8",h,0)==1&&!paused);
    P32(h+12,4);CALL("_BinkDoFrame@4",h);check("decode failure reaches guest ReadError",G32(h+28)==1);
    CALL("_BinkClose@4",h);check("close releases exactly one native movie",closed==1);CALL("_BinkClose@4",h);check("stale close is harmless",closed==1);
    unlink("author.bik");chdir("/");rmdir(dir);free(MEM);return failed?1:0;
}
