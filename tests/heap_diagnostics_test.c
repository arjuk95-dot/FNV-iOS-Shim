#include "FNVGuestMemory.h"
#include "../upstream/recomp/host/gheap.c"
#include <assert.h>
#include <sys/resource.h>
#ifdef __linux__
#include <sys/prctl.h>
#endif
uint8_t *MEM;
int main(int argc,char **argv){
    /* These children intentionally abort with a 4 GiB guest mapping. Do not
       send it to a hosted crash collector or write a huge core file. Linux
       piped core handlers can ignore RLIMIT_CORE, so disable dumpability too.
       This affects only the test process, not runner/system configuration. */
    struct rlimit core_limit={0,0};
    if(setrlimit(RLIMIT_CORE,&core_limit)!=0){perror("setrlimit RLIMIT_CORE");return 2;}
    if(getrlimit(RLIMIT_CORE,&core_limit)!=0||core_limit.rlim_cur!=0){
        fputs("Core dump limit was not disabled\n",stderr);return 2;
    }
#ifdef __linux__
    if(prctl(PR_SET_DUMPABLE,0,0,0,0)!=0||prctl(PR_GET_DUMPABLE,0,0,0,0)!=0){
        fputs("Linux test process remains dumpable\n",stderr);return 2;
    }
#endif
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
