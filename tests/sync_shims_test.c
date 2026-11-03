// Test the actual exported Win32 shims with real host pthreads and waitable objects.
#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#include <time.h>
#include <unistd.h>
#include "shims.h"
uint8_t *MEM;
_Thread_local uint32_t host_last_error;
extern const ShimTable sync_shims;
void host_sync_diagnostics(CPU *) __attribute__((weak_import));
#ifdef RT_CALLTRACE
_Thread_local uint32_t rt_ct_ring[256],rt_ct_pos;
#endif
static _Thread_local uint32_t call_sp;
static uint32_t next_sp=0x1000,next_guest=0x80000,entries;
static int failures;
static void check(const char *name,int ok){printf("%s: %s\n",ok?"PASS":"FAIL",name);fflush(stdout);failures+=!ok;}
static uint32_t invoke(const char *name,const uint32_t *args,int count){
    if(!call_sp)call_sp=__atomic_fetch_add(&next_sp,0x1000,__ATOMIC_RELAXED);
    CPU c={0};SETREG(&c,R_ESP,call_sp);P32(call_sp,0xabc);
    SETREG(&c,272,call_sp+0x800);P32(call_sp+0x824,1);
    for(int i=0;i<count;i++)P32(call_sp+4+4*i,args[i]);
    for(int i=0;i<sync_shims.count;i++)if(!strcmp(sync_shims.list[i].name,name)){sync_shims.list[i].fn(&c);return REG(&c,R_EAX);}
    abort();
}
#define CALL(name,...) invoke(name,(uint32_t[]){__VA_ARGS__},sizeof((uint32_t[]){__VA_ARGS__})/4)
void host_thread_init(CPU *c,uint32_t size){
    (void)size;uint32_t base=__atomic_fetch_add(&next_guest,0x4000,__ATOMIC_RELAXED);
    SETREG(c,R_ESP,base+0x2000);SETREG(c,272,base+0x3000);
}
void rt_calltrace_dump(void){}
int host_run_guest(CPU *c,uint32_t entry){
    __atomic_fetch_add(&entries,1,__ATOMIC_RELAXED);
    if(entry==2){uint32_t sp=REG(c,R_ESP);P32(sp+4,55);for(int i=0;i<sync_shims.count;i++)if(!strcmp(sync_shims.list[i].name,"ExitThread"))sync_shims.list[i].fn(c);abort();}
    SETREG(c,R_EAX,7);return 0;
}
static uint64_t ns(void){struct timespec t;clock_gettime(CLOCK_MONOTONIC,&t);return (uint64_t)t.tv_sec*1000000000ull+t.tv_nsec;}
static void *signal_later(void *p){usleep(20000);CALL("SetEvent",(uint32_t)(uintptr_t)p);return NULL;}
static uint32_t event(int manual,int signaled){return CALL("CreateEventA",0,manual,signaled,0);}
int main(void){
    MEM=calloc(1,4<<20);setenv("FNV_NO_QOS","1",1);setenv("FNV_TRACE_SYNC","1",1);
    uint32_t a=event(0,1),b=event(0,0);P32(0x50000,a);P32(0x50004,b);
    check("wait-all unsatisfied returns timeout",CALL("WaitForMultipleObjects",2,0x50000,1,0)==0x102);
    check("wait-all preserves auto-reset signal on timeout",CALL("WaitForSingleObject",a,0)==0);
    uint32_t s1=CALL("CreateSemaphoreA",0,1,3,0),s2=CALL("CreateSemaphoreA",0,0,3,0);
    P32(0x50000,s1);P32(0x50004,s2);CALL("WaitForMultipleObjects",2,0x50000,1,0);
    check("wait-all preserves semaphore count on timeout",CALL("WaitForSingleObject",s1,0)==0);
    a=event(0,1);b=event(0,0);P32(0x50000,a);P32(0x50004,b);
    pthread_t producer;pthread_create(&producer,NULL,signal_later,(void *)(uintptr_t)b);
    uint32_t r=CALL("WaitForMultipleObjects",2,0x50000,1,200);pthread_join(producer,NULL);
    check("wait-all completes after second event arrives",r==0);
    check("successful wait-all consumes both auto-reset events",CALL("WaitForSingleObject",a,0)==0x102&&CALL("WaitForSingleObject",b,0)==0x102);
    a=event(1,0);b=event(1,1);P32(0x50000,a);P32(0x50004,b);
    check("wait-any returns signaled index",CALL("WaitForMultipleObjects",2,0x50000,0,0)==1);
    CALL("SetEvent",a);check("wait-any chooses lowest signaled index",CALL("WaitForMultipleObjects",2,0x50000,0,0)==0);
    host_last_error=0;check("invalid single wait reports invalid handle",CALL("WaitForSingleObject",0xffff,0)==0xffffffffu&&host_last_error==6);
    // Cross a second boundary, where an unsigned nanosecond subtraction used to expire early.
    for(;;){uint64_t part=ns()%1000000000ull;if(part>=940000000&&part<960000000)break;usleep(1000);}
    CALL("ResetEvent",a);uint64_t before=ns();r=CALL("WaitForMultipleObjects",1,0x50000,0,120);uint64_t elapsed=ns()-before;
    check("finite wait spans monotonic second boundary",r==0x102&&elapsed>=110000000ull);
    uint32_t h=CALL("CreateThread",0,0,1,0,0,0);r=CALL("WaitForSingleObject",h,1000);CALL("GetExitCodeThread",h,0x51000);
    check("normal thread return signals and records exit code",h&&r==0&&G32(0x51000)==7);
    h=CALL("CreateThread",0,0,2,0,0,0);r=CALL("WaitForSingleObject",h,1000);CALL("GetExitCodeThread",h,0x51000);
    check("ExitThread signals and records explicit exit code",h&&r==0&&G32(0x51000)==55);
    uint32_t count=__atomic_load_n(&entries,__ATOMIC_RELAXED);h=CALL("CreateThread",0,0,1,0,4,0);
    check("CREATE_SUSPENDED does not execute early",h&&CALL("WaitForSingleObject",h,20)==0x102&&__atomic_load_n(&entries,__ATOMIC_RELAXED)==count);
    check("ResumeThread releases suspended worker",CALL("ResumeThread",h)==1&&CALL("WaitForSingleObject",h,1000)==0);
    if(host_sync_diagnostics){
        CPU snapshot={0};SETREG(&snapshot,R_ESP,0x60000);SETREG(&snapshot,272,0x61000);P32(0x61024,1);P32(0x60000,0x401123);
#ifdef RT_CALLTRACE
        rt_ct_ring[0]=0x401000;rt_ct_ring[1]=0x401001;rt_ct_ring[2]=0x401002;rt_ct_pos=3;
#endif
        host_sync_diagnostics(&snapshot);
    }
    return failures?1:0;
}
