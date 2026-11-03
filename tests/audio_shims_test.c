// Real DirectSound COM ABI -> real PCM mixer, without an audio device or game assets.
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include "com.h"
#include "shims.h"
#include "FNVNativeMedia.h"
uint8_t *MEM;HostImport host_imports[MAX_IMPORTS];int host_import_count;
extern const ShimTable dsound_shims;
static uint32_t heap=0x80000;
uint32_t gmalloc(uint32_t n){uint32_t p=heap+16;P32(p-4,n);heap=(p+n+15)&~15u;if(heap>=4u<<20)abort();return p;}
void gfree(uint32_t p){if(p)memset(MEM+p,0xdd,G32(p-4));}
void rt_trap(CPU *c,int code,uint32_t address){(void)c;fprintf(stderr,"unexpected trap %d at %#x\n",code,address);abort();}
int fnv_audio_start(void){return 1;}
static int failed;
static void check(const char *name,int ok){printf("%s: %s\n",ok?"PASS":"FAIL",name);failed+=!ok;}
static uint32_t invoke(ShimFn fn,const uint32_t *args,unsigned count){CPU c={0};SETREG(&c,R_ESP,0x1000);P32(0x1000,0xabc);for(unsigned i=0;i<count;i++)P32(0x1004+4*i,args[i]);fn(&c);if(REG(&c,R_ESP)!=0x1004+4*count){fprintf(stderr,"Wrong COM stack cleanup: %#x count=%u\n",REG(&c,R_ESP),count);abort();}return REG(&c,R_EAX);}
static uint32_t method(uint32_t o,unsigned slot,const uint32_t *args,unsigned count){uint32_t thunk=G32(G32(o)+slot*4);return invoke(host_imports[(thunk-IMPORT_THUNK_BASE)/4].fn,args,count);}
#define M(o,slot,...) method(o,slot,(uint32_t[]){__VA_ARGS__},sizeof((uint32_t[]){__VA_ARGS__})/4)
static int near(float a,float b){return fabsf(a-b)<0.002f;}
int main(void){
    MEM=calloc(1,4u<<20);
    uint32_t create[]={0,0x2000,0};check("native DirectSound device",invoke(dsound_shims.list[0].fn,create,3)==0);uint32_t ds=G32(0x2000);
    uint32_t desc=0x3000,wfx=0x3100;P32(desc,20);P32(desc+8,8);P32(desc+16,wfx);
    P32(wfx,1|(1u<<16));P32(wfx+4,48000);P32(wfx+8,96000);P32(wfx+12,2|(16u<<16));
    check("PCM mono buffer creation",M(ds,3,ds,desc,0x2004,0)==0);uint32_t b=G32(0x2004);
    check("real buffer lock",M(b,11,b,0,8,0x4000,0x4004,0x4008,0x400c,2)==0&&G32(0x4004)==8);
    int16_t pcm[]={0,16384,0,-16384};memcpy(MEM+G32(0x4000),pcm,sizeof pcm);
    check("unlock publishes PCM and preserves stdcall stack",M(b,19,b,G32(0x4000),8,0,0)==0);
    M(b,12,b,0,0,0);float left[8],right[8];fnv_audio_mix(left,right,4,48000);
    check("actual guest PCM reaches both output channels",near(left[1],0.5f)&&near(right[1],0.5f)&&near(left[3],-0.5f));
    M(b,9,b,0x4010);check("one-shot buffer completes",G32(0x4010)==0);
    M(b,13,b,0);M(b,12,b,0,0,1);fnv_audio_mix(left,right,8,48000);
    check("looping buffer wraps without losing samples",near(left[1],0.5f)&&near(left[5],0.5f));
    M(b,18,b);M(b,13,b,0);M(b,17,b,24000);M(b,12,b,0,0,0);fnv_audio_mix(left,right,8,48000);
    check("frequency resamples and interpolates PCM",near(left[1],0.25f)&&near(left[2],0.5f)&&near(left[5],-0.25f));
    M(b,13,b,0);M(b,17,b,48000);M(b,15,b,(uint32_t)-602);M(b,16,b,10000);M(b,12,b,0,0,0);fnv_audio_mix(left,right,4,48000);
    check("volume and pan affect real output",near(left[1],0)&&near(right[1],0.25f));
    check("duplicate shares sample storage",M(ds,5,ds,b,0x2008)==0);uint32_t duplicate=G32(0x2008);M(b,2,b);
    M(duplicate,15,duplicate,0);M(duplicate,16,duplicate,0);M(duplicate,13,duplicate,0);M(duplicate,12,duplicate,0,0,0);fnv_audio_mix(left,right,4,48000);
    check("duplicate survives release of original",near(left[1],0.5f)&&near(right[3],-0.5f));M(duplicate,2,duplicate);
    M(ds,3,ds,desc,0x2004,0);b=G32(0x2004);P32(0x5000,0x279f9a86);M(b,0,b,0x5000,0x2010);uint32_t spatial=G32(0x2010);
    check("3D interface retains its parent sound buffer",M(b,2,b)==1);M(spatial,2,spatial);check("last 3D reference releases parent",G32(b)==0xddddddddu);
    uint32_t v=fnv_audio_voice_create(4,1,48000,8,1);uint8_t p8[]={128,255,0,128};fnv_audio_voice_write(v,0,p8,4);fnv_audio_voice_play(v,0);fnv_audio_mix(left,right,4,48000);
    check("unsigned 8-bit PCM is centered at silence",near(left[0],0)&&near(left[1],127/128.f)&&near(left[2],-1));fnv_audio_voice_destroy(v);
    check("unsupported format is rejected",fnv_audio_voice_create(16,6,48000,16,1)==0);
    free(MEM);return failed?1:0;
}
