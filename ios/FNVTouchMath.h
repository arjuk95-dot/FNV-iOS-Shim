#pragma once
#include <math.h>

/* All inputs are UIKit points. Keep the fractional part between move events. */
typedef struct { double x, y, carryX, carryY; } FNVLook;
typedef struct { int dx, dy; } FNVMouseDelta;
typedef struct { double x, y; } FNVMove;

static inline FNVMouseDelta FNVLookTo(FNVLook *look, double x, double y, double gain) {
    double dx = (x - look->x) * gain + look->carryX;
    double dy = (y - look->y) * gain + look->carryY;
    FNVMouseDelta result = { (int)dx, (int)dy };
    *look = (FNVLook){ x, y, dx - result.dx, dy - result.dy };
    return result;
}

/* x points right, y points forward. Magnitude saturates at the stick radius. */
static inline FNVMove FNVMoveFromOffset(double dx, double dy, double radius) {
    double divisor = fmax(radius, hypot(dx, dy));
    return (FNVMove){ dx / divisor, -dy / divisor };
}
