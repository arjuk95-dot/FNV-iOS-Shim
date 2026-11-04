// Windows SDK IIDs and the original game's base-first Release-until-zero order.
#include "FNVGuestMemory.h"
#include "../upstream/recomp/host/gheap.c"
#ifndef FNV_DSOUND_SOURCE
#define FNV_DSOUND_SOURCE "../upstream/recomp/host/dsound.c"
#endif
#include FNV_DSOUND_SOURCE
#include <assert.h>
uint8_t *MEM;HostImport host_imports[MAX_IMPORTS];int host_import_count;
void rt_trap(CPU *c,int n,uint32_t a){(void)c;fprintf(stderr,"trap %d %#x\n",n,a);abort();}
int fnv_audio_start(void){return 1;}
static const uint8_t sdk_3d[16]={0x86,0xfa,0x9a,0x27,0x81,0x49,0xce,0x11,0xa5,0x21,0,0x20,0xaf,0x0b,0xe5,0x60};
static const uint8_t sdk_listener[16]={0x84,0xfa,0x9a,0x27,0x81,0x49,0xce,0x11,0xa5,0x21,0,0x20,0xaf,0x0b,0xe5,0x60};
static const uint8_t sdk_base[16]={0x85,0xfa,0x9a,0x27,0x81,0x49,0xce,0x11,0xa5,0x21,0,0x20,0xaf,0x0b,0xe5,0x60};
static uint32_t stack,output,iid,ds;
static uint32_t invoke(ShimFn fn,uint32_t *args,unsigned n){CPU c={0};SETREG(&c,R_ESP,stack);P32(stack,0xaeb047);for(unsigned i=0;i<n;i++)P32(stack+4+4*i,args[i]);fn(&c);assert(REG(&c,R_ESP)==stack+4+4*n);return REG(&c,R_EAX);}
static uint32_t method(uint32_t o,unsigned slot,uint32_t *args,unsigned n){uint32_t thunk=G32(G32(o)+4*slot);assert(thunk>=IMPORT_THUNK_BASE&&(thunk-IMPORT_THUNK_BASE)/4<(uint32_t)host_import_count);return invoke(host_imports[(thunk-IMPORT_THUNK_BASE)/4].fn,args,n);}
#define CALL(o,slot,...) method(o,slot,(uint32_t[]){__VA_ARGS__},sizeof((uint32_t[]){__VA_ARGS__})/4)
static uint32_t make_buffer(int primary){
    uint32_t desc=gmalloc(20),wfx=gmalloc(20);P32(desc,20);P32(desc+4,primary?0x11:0x10);P32(desc+8,primary?0:4096);P32(desc+16,primary?0:wfx);
    P32(wfx,1|(1u<<16));P32(wfx+4,48000);P32(wfx+8,96000);P32(wfx+12,2|(16u<<16));
    assert(CALL(ds,3,ds,desc,output,0)==0);uint32_t b=G32(output);gfree(desc);gfree(wfx);return b;
}
static uint32_t query(uint32_t b,const uint8_t *guid,uint32_t *object){memcpy(MEM+iid,guid,16);P32(output,0xabcdef);uint32_t hr=CALL(b,0,b,iid,output);*object=G32(output);return hr;}
static void drain(uint32_t b){unsigned count=0;while(CALL(b,2,b)){assert(++count<8);}}
int main(int argc,char **argv){
    assert(argc==2);MEM=fnv_reserve_guest();assert(MEM!=MAP_FAILED);stack=gmalloc(128);output=gmalloc(4);iid=gmalloc(16);
    assert(invoke(dsound_shims.list[0].fn,(uint32_t[]){0,output,0},3)==0);ds=G32(output);
    const char *mode=argv[1];uint32_t b=make_buffer(!strcmp(mode,"listener")),s=0;
    if(!strcmp(mode,"sdk-destructor")){
        assert(query(b,sdk_3d,&s)==0);printf("base=%#x spatial=%#x alias=%d\n",b,s,b==s);fflush(stdout);
        // Exact order from aeafb0: drain base interface, then the separately stored 3D interface.
        drain(b);drain(s);
    }else if(!strcmp(mode,"independent-counts")||!strcmp(mode,"listener")){
        assert(query(b,!strcmp(mode,"listener")?sdk_listener:sdk_3d,&s)==0);
        assert(s!=b);assert(CALL(b,2,b)==0);assert(allocation_find(b,0)->live);
        uint32_t base=0;assert(query(s,sdk_base,&base)==0&&base==b);assert(CALL(base,2,base)==0);
        assert(CALL(s,2,s)==0);assert(!allocation_find(b,0)->live);
    }else if(!strcmp(mode,"canonical-interface")){
        uint32_t again=0;assert(query(b,sdk_3d,&s)==0);assert(query(b,sdk_3d,&again)==0&&again==s&&s!=b);
        assert(CALL(s,2,s)==1);assert(CALL(s,2,s)==0);assert(CALL(b,2,b)==0);
    }else if(!strcmp(mode,"unknown-iid")){
        uint8_t unknown[16];memcpy(unknown,sdk_3d,16);unknown[15]^=1;
        assert(query(b,unknown,&s)==0x80004002u&&s==0&&G32(b+4)==1);drain(b);
    }else if(!strcmp(mode,"duplicate-spatial")){
        uint32_t duplicate=0;assert(CALL(ds,5,ds,b,output)==0);duplicate=G32(output);
        uint32_t data=G32(COM_DATA(b)+B_DATA),other=0;assert(query(b,sdk_3d,&s)==0&&query(duplicate,sdk_3d,&other)==0&&s!=other);
        drain(b);drain(s);assert(allocation_find(data,0)->live);
        CALL(duplicate,12,duplicate,0,0,0);float l[4],r[4];fnv_audio_mix(l,r,4,48000);
        drain(duplicate);drain(other);assert(!allocation_find(data,0)->live);
    }else return 2;
    printf("PASS: %s\n",mode);return 0;
}
