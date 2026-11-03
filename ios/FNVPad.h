#pragma once
#include <stdint.h>
void fnv_move(float right, float forward);
void fnv_pad_state(int16_t *x, int16_t *y, uint32_t *packet);
void fnv_use_analog(int enabled);
int fnv_analog_enabled(void);
typedef struct {uint32_t packet;uint16_t buttons;uint8_t left_trigger,right_trigger;int16_t lx,ly,rx,ry;} FNVPadState;
void fnv_pad_snapshot(FNVPadState *state);
void fnv_pad_button(uint16_t mask,int down);
void fnv_pad_trigger(int right,int down);
void fnv_pad_reset(void);
