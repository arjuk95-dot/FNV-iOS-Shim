// Native Windows harness for the unchanged allocator C functions; only platform headers are adapted.
#include <windows.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <assert.h>
static uint8_t *MEM;
typedef SRWLOCK pthread_mutex_t;
#define PTHREAD_MUTEX_INITIALIZER SRWLOCK_INIT
static int pthread_mutex_lock(pthread_mutex_t *m){AcquireSRWLockExclusive(m);return 0;}
static int pthread_mutex_unlock(pthread_mutex_t *m){ReleaseSRWLockExclusive(m);return 0;}
static uint32_t G32(uint32_t p){uint32_t v;memcpy(&v,MEM+p,4);return v;}
static void P32(uint32_t p,uint32_t v){memcpy(MEM+p,&v,4);}
#include "gheap-under-test.c"
static LONG CALLBACK demand_commit(EXCEPTION_POINTERS *e){
    if(e->ExceptionRecord->ExceptionCode!=EXCEPTION_ACCESS_VIOLATION)return EXCEPTION_CONTINUE_SEARCH;
    uintptr_t address=(uintptr_t)e->ExceptionRecord->ExceptionInformation[1],base=(uintptr_t)MEM;
    if(address<base || address-base>=0x100000000ull)return EXCEPTION_CONTINUE_SEARCH;
    if(!VirtualAlloc((void*)(address&~4095ull),4096,MEM_COMMIT,PAGE_READWRITE))return EXCEPTION_CONTINUE_SEARCH;
    return EXCEPTION_CONTINUE_EXECUTION;
}
int main(int argc,char **argv){
    assert(argc==2);MEM=VirtualAlloc(NULL,0x100000000ull,MEM_RESERVE,PAGE_READWRITE);assert(MEM);assert(AddVectoredExceptionHandler(1,demand_commit));
    const char *mode=argv[1];int ok=0;
    if(!strcmp(mode,"empty-spanning")){ok=gheap_reserve_fixed(0x20000000,0x60000000)&&gmalloc(4096)>=0x60000000;}
    else if(!strcmp(mode,"occupied-spanning")){uint32_t p=gmalloc(4096);MEM[p]=0x5a;ok=!gheap_reserve_fixed(0x20000000,0x60000000)&&MEM[p]==0x5a;}
    else if(!strcmp(mode,"future-heap")){assert(gheap_reserve_fixed(0x41000000,0x41400000));MEM[0x41000020]=0x5a;uint32_t p=gmalloc(20<<20);ok=p>=0x41400000&&MEM[0x41000020]==0x5a;}
    else if(!strcmp(mode,"future-pages")){assert(gheap_reserve_fixed(0x41000000,0x41400000));MEM[0x41000020]=0x5a;uint32_t p=gpages(20<<20);ok=p>=0x41400000&&MEM[0x41000020]==0x5a;}
    else if(!strcmp(mode,"adjacent")){assert(gheap_reserve_fixed(0x41400000,0x41800000));assert(gheap_reserve_fixed(0x41000000,0x41400000));ok=gmalloc(24<<20)>=0x41800000;}
    else if(!strcmp(mode,"recycling")){assert(gheap_reserve_fixed(0x41000000,0x41400000));ok=1;for(unsigned i=0;i<10000;i++){uint32_t p=gmalloc(1024);if(p>=0x41000000&&p<0x41400000)ok=0;memset(MEM+p,i&255,1024);for(unsigned j=0;j<1024;j++)if(MEM[p+j]!=(i&255))ok=0;gfree(p);}}
    printf("%s: %s\n",ok?"PASS":"FAIL",mode);return ok?0:1;
}
