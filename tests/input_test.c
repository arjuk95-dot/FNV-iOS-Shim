#include <assert.h>
#include <math.h>
#include <stdio.h>
#include "FNVTouchMath.h"
#include "input.h"

/* The input-only test does not link the guest heap. Darwin still requires
 * the optional diagnostic hook to be supplied at static link time. */
void gheap_report(void) {}

/* Link to upstream's unmodified input.c. This tests the host polling boundary. */
static void send(FNVLook *look, double x, double y, double gain) {
    FNVMouseDelta v = FNVLookTo(look, x, y, gain);
    if (v.dx || v.dy) input_mouse_move(v.dx, v.dy);
}
static void expectMotion(int x, int y) {
    int32_t dx, dy, wheel;
    uint8_t buttons[8];
    input_mouse_state(&dx, &dy, &wheel, buttons);
    assert(dx == x && dy == y);
}
int main(void) {
    FNVLook look = {100, 200, 0, 0};
    for (int i = 1; i <= 8; ++i) send(&look, 100+i*0.25, 200-i*0.5, 1);
    expectMotion(2, -4);
    send(&look, 102, 196, 1);
    expectMotion(0, 0);  // stationary
    look = (FNVLook){600, 100, 0, 0};
    send(&look, 600, 100, 1);
    expectMotion(0, 0);  // fresh contact
    send(&look, 602, 96, 0.5);
    expectMotion(1, -2);
    expectMotion(0, 0);  // host consumes motion once
    look = (FNVLook){0};
    for (int i = 1; i <= 120; ++i) send(&look, i, 0, 1);
    expectMotion(120, 0);
    look = (FNVLook){0};
    send(&look, 120, 0, 1);
    expectMotion(120, 0);
    FNVMove walk = FNVMoveFromOffset(0, -28, 56);
    assert(walk.x == 0 && walk.y == 0.5);
    FNVMove diagonal = FNVMoveFromOffset(-100, 100, 56);
    assert(diagonal.x < 0 && diagonal.y < 0 && fabs(hypot(diagonal.x, diagonal.y) - 1) < 1e-9);
    FNVMove rest = FNVMoveFromOffset(0, 0, 56);
    assert(rest.x == 0 && rest.y == 0);
    puts("PASS: swipe deltas, fractional input, re-touch, stationary hold, sensitivity, host polling, event batching and analog movement math");
    return 0;
}
