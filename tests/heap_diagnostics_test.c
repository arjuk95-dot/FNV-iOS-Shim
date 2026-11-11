#include "FNVGuestMemory.h"
#include "../upstream/recomp/host/gheap.c"
#include <assert.h>
#include "no_core.h"
uint8_t *MEM;
int main(int argc,char **argv){
    fnv_test_disable_core_dumps();
    assert(argc==2);MEM=fnv_reserve_guest();assert(MEM!=MAP_FAILED);
    uint32_t q=gmalloc(40);
    if(!strcmp(argv[1],"tail")){MEM[q+40]=0;gfree(q);}
    else if(!strcmp(argv[1],"header")){P32(q-HDR,99);gsize(q);}
    else if(!strcmp(argv[1],"class")){P32(q-HDR+4,99);gfree(q);}
    else if(!strcmp(argv[1],"double-free")){gfree(q);gfree(q);}
    else if(!strcmp(argv[1],"unowned")){gfree(0xfffffff0);}
    else if(!strcmp(argv[1],"bad-free-list")){gfree(q);freelist[cls(40+HDR)]=0xffffff00;gmalloc(40);}
    else if(!strcmp(argv[1],"live-free-list")){freelist[cls(40+HDR)]=q-HDR;gmalloc(40);}
    else if(!strcmp(argv[1],"valid")){
        uint32_t original=q;memset(MEM+q,0x5a,40);assert(gsize(q)==40);
        q=grealloc(q,44);assert(q==original&&gsize(q)==44);
        for(unsigned i=0;i<40;i++)assert(MEM[q+i]==0x5a);
        q=grealloc(q,12);assert(q==original&&gsize(q)==12);gfree(q);
        for(unsigned i=0;i<10000;i++){q=gmalloc(40);memset(MEM+q,0x5a,40);gfree(q);}
        q=gmalloc(9<<20);memset(MEM+q,0x5a,9<<20);gfree(q);q=gmalloc(9<<20);gfree(q);
        puts("PASS: checked allocation/reallocation/reuse, unchanged addresses and capacities");return 0;
    }else return 2;
    fputs("Expected heap corruption was not stopped\n",stderr);return 1;
}
