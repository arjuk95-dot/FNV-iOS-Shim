#pragma once
#include <sys/mman.h>
#include <stddef.h>
#include <stdint.h>

#ifdef RT_FIXED_MEM
#error iOS guest and host must be built with runtime-relative pointers
#endif
static inline uint8_t *fnv_reserve_guest(void) {
    return mmap(NULL, (size_t)1 << 32, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANON, -1, 0);
}
