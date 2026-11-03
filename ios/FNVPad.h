#pragma once
#include <stdint.h>
void fnv_move(float right, float forward);
void fnv_pad_state(int16_t *x, int16_t *y, uint32_t *packet);
void fnv_use_analog(int enabled);
int fnv_analog_enabled(void);
