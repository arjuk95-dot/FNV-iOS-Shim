#ifdef __linux__
#include <time.h>
#include <stdint.h>
#define CLOCK_UPTIME_RAW CLOCK_MONOTONIC
static inline uint64_t clock_gettime_nsec_np(clockid_t id) {
    struct timespec ts; clock_gettime(id,&ts);
    return (uint64_t)ts.tv_sec*1000000000 + ts.tv_nsec;
}
#endif
