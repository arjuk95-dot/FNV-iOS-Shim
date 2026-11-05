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

typedef enum {
    FNVContextGameplay=0, FNVContextPipBoy=1, FNVContextVATS=2,
    FNVContextMenu=3, FNVContextDialogue=4, FNVContextLoot=5,
    FNVContextMinigame=6, FNVContextUnknown=7,FNVContextLockpick=8,
    FNVContextHacking=9,FNVContextComputer=10,FNVContextPipMap=11
} FNVInputContext;
static inline int fnv_context_is_pip(FNVInputContext value){return value==FNVContextPipBoy||value==FNVContextPipMap;}
void fnv_pad_touch_state(const FNVPadState *state);
void fnv_pad_physical_state(const FNVPadState *state,int connected);
int fnv_pad_physical_active(void);
void fnv_pad_context_set(FNVInputContext context);
FNVInputContext fnv_pad_context(void);
uint32_t fnv_pad_input_epoch(void);
void fnv_pad_stick_camera(int enabled);
int fnv_pad_uses_stick_camera(void);
void fnv_pad_mouse_move(int dx,int dy);
void fnv_pad_camera_sensitivity(float radians_per_count);
float fnv_pad_mouse_radians(void);
void fnv_pad_bindings_set(const uint8_t bindings[28]);
unsigned fnv_pad_binding(unsigned action);
void fnv_pad_apply_binding(FNVPadState *state,unsigned code);
