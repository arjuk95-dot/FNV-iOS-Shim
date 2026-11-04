#include "FNVGuestMemory.h"
#ifndef FNV_GHEAP_SOURCE
#define FNV_GHEAP_SOURCE "../upstream/recomp/host/gheap.c"
#endif
#ifndef FNV_KERNEL_SOURCE
#define FNV_KERNEL_SOURCE "../upstream/recomp/host/shims_kernel32.c"
#endif
#include FNV_GHEAP_SOURCE
#include FNV_KERNEL_SOURCE
#include <assert.h>
uint8_t *MEM;uint32_t host_image_base=0x400000;
static uint32_t allocate(uint32_t at,uint32_t bytes,uint32_t type){CPU c={0};SETREG(&c,R_ESP,0x1000);P32(0x1000,0x123456);P32(0x1004,at);P32(0x1008,bytes);P32(0x100c,type);P32(0x1010,4);VirtualAlloc_(&c);assert(REG(&c,R_ESP)==0x1014);return REG(&c,R_EAX);}
int main(int argc,char **argv){
    assert(argc==2);MEM=fnv_reserve_guest();assert(MEM!=MAP_FAILED);P32(host_image_base+0x3c,0x80);P32(host_image_base+0x80+24+56,0x1000000);
    int ok=0;const char *mode=argv[1];
    if(!strcmp(mode,"occupied")){uint32_t p=gmalloc(4096);MEM[p]=0x5a;uint32_t r=allocate(p&~0xffffu,65536,0x2000);if(r)MEM[p]=0xcc;ok=r==0&&last_error==487&&MEM[p]==0x5a;printf("host=%#x fixed_result=%#x canary=%#x\n",p,r,MEM[p]);}
    else if(!strcmp(mode,"future-heap")||!strcmp(mode,"future-pages")){
        uint32_t r=allocate(0x41000000,4<<20,0x2000);assert(r==0x41000000);MEM[r+32]=0x5a;
        uint32_t p=!strcmp(mode,"future-heap")?gmalloc(20<<20):gpages(20<<20);
        ok=((uint64_t)p+(20<<20)<=r||p>=r+(4<<20))&&MEM[r+32]==0x5a;printf("reserved=%#x host=%#x canary=%#x\n",r,p,MEM[r+32]);
    }else if(!strcmp(mode,"unreserved-commit")){ok=allocate(0x31000000,4096,0x1000)==0&&last_error==487;}
    else if(!strcmp(mode,"partial-commit")){assert(allocate(0x31000000,65536,0x2000)==0x31000000);ok=allocate(0x3100f000,8192,0x1000)==0&&last_error==487;}
    else if(!strcmp(mode,"rounding")){ok=allocate(0x31001234,0x2345,0x2000)==0x31000000;}
    else if(!strcmp(mode,"valid-commit")){assert(allocate(0x31000000,65536,0x2000)==0x31000000);uint32_t p=allocate(0x31001000,4096,0x1000);MEM[p]=0x5a;ok=p==0x31001000&&allocate(p,4096,0x1000)==p&&MEM[p]==0x5a;}
    else if(!strcmp(mode,"overflow")){ok=allocate(0xfffff000,8192,0x2000)==0;}
    else if(!strcmp(mode,"zero")){ok=allocate(0,0,0x3000)==0;}
    else if(!strcmp(mode,"spanning-future")){uint32_t r=allocate(0x20000000,0x40000000,0x2000);uint32_t p=gmalloc(4096);ok=r==0x20000000&&p>=0x60000000;printf("large fixed=%#x host=%#x\n",r,p);}
    else if(!strcmp(mode,"spanning-occupied")){uint32_t p=gmalloc(4096);MEM[p]=0x5a;ok=allocate(0x20000000,0x40000000,0x2000)==0&&MEM[p]==0x5a;}
    else if(!strcmp(mode,"adjacent")){assert(allocate(0x41400000,4<<20,0x2000)==0x41400000);assert(allocate(0x41000000,4<<20,0x2000)==0x41000000);uint32_t p=gmalloc(24<<20);ok=p>=0x41800000;}
    printf("%s: %s\n",ok?"PASS":"FAIL",mode);return ok?0:1;
}
