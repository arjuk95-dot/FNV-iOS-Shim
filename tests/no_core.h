#ifndef FNV_TEST_NO_CORE_H
#define FNV_TEST_NO_CORE_H
#include <stdio.h>
#include <stdlib.h>
#include <sys/resource.h>
#ifdef __linux__
#include <sys/prctl.h>
#endif
/* Python harnesses reject this separately from expected historical failures. */
#define FNV_TEST_SETUP_FAILURE 125
static void fnv_test_disable_core_dumps(void){
    /* These children intentionally abort with a 4 GiB guest mapping. Do not
       send it to a hosted crash collector or write a huge core file. Linux
       piped core handlers can ignore RLIMIT_CORE, so disable dumpability too.
       This affects only the test process, not runner/system configuration. */
    struct rlimit core_limit={0,0};
    if(setrlimit(RLIMIT_CORE,&core_limit)!=0){perror("setrlimit RLIMIT_CORE");exit(FNV_TEST_SETUP_FAILURE);}
    if(getrlimit(RLIMIT_CORE,&core_limit)!=0||core_limit.rlim_cur!=0){
        fputs("Core dump limit was not disabled\n",stderr);exit(FNV_TEST_SETUP_FAILURE);
    }
#ifdef __linux__
    if(prctl(PR_SET_DUMPABLE,0,0,0,0)!=0||prctl(PR_GET_DUMPABLE,0,0,0,0)!=0){
        fputs("Linux test process remains dumpable\n",stderr);exit(FNV_TEST_SETUP_FAILURE);
    }
#endif
}
#endif
