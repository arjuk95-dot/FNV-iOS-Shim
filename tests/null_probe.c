#include <assert.h>
#include "FNVPad.h"
#include "input.h"
#include "d3d9_backend.h"
static int clears;
void d3d_backend_clear(D3DState *s, uint32_t n, uint32_t rects, uint32_t flags, uint32_t color, float z, uint32_t stencil) {
    (void)n; (void)rects; (void)z; (void)stencil;
    assert(s->width==960 && s->height==540 && flags==1);
    // Red/green reflect the relative swipe, blue reflects both analog axes.
    assert(color==0xff564d70u);
    ++clears;
}
#include <stdio.h>
int fnv_probe(unsigned);
int main(void) {
    fnv_use_analog(0);
    fnv_move(0.7f,0.5f);
    uint8_t keys[256]; input_keyboard_state(keys);
    assert(keys[0x20] && keys[0x11]);
    fnv_move(0,0); input_keyboard_state(keys);
    assert(!keys[0x20] && !keys[0x11]);
    fnv_use_analog(1);
    fnv_move(0.25f,0.5f);
    input_mouse_move(6,-3);
    int rc = fnv_probe(3);
    assert(rc == 0 && clears == 3);
    puts("PASS: dynamic guest map, D3D COM device/clear/present, input poll");
    return rc;
}
