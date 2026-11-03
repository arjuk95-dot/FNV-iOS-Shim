// Synthetic guest calls for testing the same COM dispatch and renderer as the game.
#include "shims.h"
#include "input.h"
#include "FNVGuestMemory.h"
#include "FNVPad.h"
#include <assert.h>
#include <stdlib.h>
#include <stdio.h>
extern const ShimTable d3d9_shims, xinput_shims;

static CPU cpu;
static uint32_t stack;
static uint32_t invoke(ShimFn fn, uint32_t *args, int count) {
    SETREG(&cpu, R_ESP, stack);
    memcpy(MEM + stack + 4, args, 4u * count);
    fn(&cpu);
    assert(REG(&cpu, R_ESP) == stack + 4u + 4u * count);
    return REG(&cpu, R_EAX);
}
static ShimFn slot(uint32_t object, unsigned i) {
    uint32_t thunk = G32(G32(object) + 4*i);
    assert(thunk >= IMPORT_THUNK_BASE && (thunk - IMPORT_THUNK_BASE)/4 < (uint32_t)host_import_count);
    return host_imports[(thunk - IMPORT_THUNK_BASE)/4].fn;
}
int fnv_probe(unsigned frameLimit) {
    MEM = fnv_reserve_guest();
    if (MEM == MAP_FAILED) { perror("reserve 4 GiB"); return 1; }
    stack = gmalloc(256);
    uint32_t pp = gmalloc(56), out = gmalloc(4), pad = gmalloc(16);
    uint32_t d3d = invoke(d3d9_shims.list[0].fn, (uint32_t[]){32}, 1);
    P32(pp, 960); P32(pp+4, 540); P32(pp+8, 21); P32(pp+32, 1);
    uint32_t hr = invoke(slot(d3d, 16), (uint32_t[]){d3d,0,1,0,0,pp,out}, 7);
    if (hr || !G32(out)) return 2;
    uint32_t dev = G32(out);
    int32_t dx, dy, wheel;
    uint8_t buttons[8], red = 80, green = 80;
    for (unsigned i=0; !frameLimit || i<frameLimit; ++i) {
        input_mouse_state(&dx, &dy, &wheel, buttons);
        red += (uint32_t)dx; green += (uint32_t)dy;
        if (invoke(xinput_shims.list[0].fn, (uint32_t[]){0,pad}, 2)) return 3;
        int16_t x,y;
        memcpy(&x,MEM+pad+8,2); memcpy(&y,MEM+pad+10,2);
        uint8_t blue = (uint8_t)(64 + (abs(x)+abs(y))/512);
        uint32_t color = 0xff000000u | ((uint32_t)red<<16) | ((uint32_t)green<<8) | blue;
        if (invoke(slot(dev,43),(uint32_t[]){dev,0,0,1,color,0x3f800000,0},7)) return 4;
        if (invoke(slot(dev,17),(uint32_t[]){dev,0,0,0,0},5)) return 5;
    }
    return 0;
}
