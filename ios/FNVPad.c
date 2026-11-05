#include "FNVPad.h"
#include "input.h"
#include <math.h>
#include <pthread.h>
#include <stdlib.h>
#include <string.h>
static pthread_mutex_t lock=PTHREAD_MUTEX_INITIALIZER;
static FNVPadState touch,physical,combined;
static uint32_t epoch;
static int analog,physical_connected,physical_active,stick_camera;
static float mouse_radians=.002f;
static FNVInputContext context=FNVContextGameplay;
static uint8_t bindings[28]={19,20,23,22,17,10,16,12,8,0,0,0,13,15,11,7,14,0,1,0,0,0,0,0,0,0,0,9};
static int16_t axis(float value){return (int16_t)lroundf(fmaxf(-1,fminf(1,value))*32767);}
static int active(const FNVPadState *s){return s->buttons||s->left_trigger>30||s->right_trigger>30||abs(s->lx)>7849||abs(s->ly)>7849||abs(s->rx)>8689||abs(s->ry)>8689;}
static void refresh(void){
    FNVPadState next=touch;next.packet=combined.packet;
    if(physical_connected){
        next.buttons|=physical.buttons;
        if(physical.left_trigger>next.left_trigger)next.left_trigger=physical.left_trigger;
        if(physical.right_trigger>next.right_trigger)next.right_trigger=physical.right_trigger;
        if(physical_active){next.lx=physical.lx;next.ly=physical.ly;next.rx=physical.rx;next.ry=physical.ry;}
    }
    if(memcmp((char *)&next+4,(char *)&combined+4,sizeof next-4))next.packet++;
    combined=next;
}
void fnv_move(float right,float forward){
    pthread_mutex_lock(&lock);touch.lx=axis(right);touch.ly=axis(forward);
    if(!analog){input_key(0x11,touch.ly>5500);input_key(0x1f,touch.ly< -5500);input_key(0x20,touch.lx>5500);input_key(0x1e,touch.lx< -5500);}
    refresh();pthread_mutex_unlock(&lock);
}
void fnv_pad_state(int16_t *x,int16_t *y,uint32_t *packet){pthread_mutex_lock(&lock);*x=combined.lx;*y=combined.ly;*packet=combined.packet;pthread_mutex_unlock(&lock);}
void fnv_use_analog(int enabled){pthread_mutex_lock(&lock);analog=!!enabled;pthread_mutex_unlock(&lock);}
int fnv_analog_enabled(void){pthread_mutex_lock(&lock);int result=analog||physical_connected;pthread_mutex_unlock(&lock);return result;}
void fnv_pad_snapshot(FNVPadState *state){pthread_mutex_lock(&lock);*state=combined;pthread_mutex_unlock(&lock);}
void fnv_pad_button(uint16_t mask,int down){pthread_mutex_lock(&lock);touch.buttons=down?(touch.buttons|mask):(touch.buttons&~mask);refresh();pthread_mutex_unlock(&lock);}
void fnv_pad_trigger(int right,int down){pthread_mutex_lock(&lock);if(right)touch.right_trigger=down?255:0;else touch.left_trigger=down?255:0;refresh();pthread_mutex_unlock(&lock);}
void fnv_pad_touch_state(const FNVPadState *state){pthread_mutex_lock(&lock);if(!physical_active)touch=*state;else memset(&touch,0,sizeof touch);refresh();pthread_mutex_unlock(&lock);}
void fnv_pad_reset(void){pthread_mutex_lock(&lock);memset(&touch,0,sizeof touch);input_touch_mouse_reset();if(!analog){input_key(0x11,0);input_key(0x1f,0);input_key(0x20,0);input_key(0x1e,0);}++epoch;refresh();pthread_mutex_unlock(&lock);}
void fnv_pad_physical_state(const FNVPadState *state,int connected){
    pthread_mutex_lock(&lock);int was_active=physical_active;physical_connected=!!connected;
    if(connected&&state)physical=*state;else memset(&physical,0,sizeof physical);
    physical_active=physical_connected&&active(&physical);
    if(physical_active&&!was_active){memset(&touch,0,sizeof touch);input_touch_mouse_reset();++epoch;}
    refresh();pthread_mutex_unlock(&lock);
}
int fnv_pad_physical_active(void){pthread_mutex_lock(&lock);int value=physical_active;pthread_mutex_unlock(&lock);return value;}
void fnv_pad_context_set(FNVInputContext value){pthread_mutex_lock(&lock);if(value!=context){context=value;memset(&touch,0,sizeof touch);input_touch_mouse_reset();++epoch;refresh();}pthread_mutex_unlock(&lock);}
FNVInputContext fnv_pad_context(void){pthread_mutex_lock(&lock);FNVInputContext value=context;pthread_mutex_unlock(&lock);return value;}
uint32_t fnv_pad_input_epoch(void){pthread_mutex_lock(&lock);uint32_t value=epoch;pthread_mutex_unlock(&lock);return value;}
void fnv_pad_stick_camera(int enabled){pthread_mutex_lock(&lock);if(stick_camera!=!!enabled){stick_camera=!!enabled;input_touch_mouse_reset();++epoch;}pthread_mutex_unlock(&lock);}
int fnv_pad_uses_stick_camera(void){pthread_mutex_lock(&lock);int value=stick_camera||physical_active||context!=FNVContextGameplay;pthread_mutex_unlock(&lock);return value;}
void fnv_pad_mouse_move(int dx,int dy){pthread_mutex_lock(&lock);if(!stick_camera&&!physical_active&&context==FNVContextGameplay)input_touch_mouse_move(dx,dy);pthread_mutex_unlock(&lock);}
void fnv_pad_camera_sensitivity(float value){pthread_mutex_lock(&lock);mouse_radians=isfinite(value)&&value>1e-6f&&value<=1?value:.002f;pthread_mutex_unlock(&lock);}
float fnv_pad_mouse_radians(void){pthread_mutex_lock(&lock);float value=mouse_radians;pthread_mutex_unlock(&lock);return value;}
void fnv_pad_bindings_set(const uint8_t values[28]){pthread_mutex_lock(&lock);if(memcmp(bindings,values,28)){memcpy(bindings,values,28);memset(&touch,0,sizeof touch);input_touch_mouse_reset();++epoch;refresh();}pthread_mutex_unlock(&lock);}
unsigned fnv_pad_binding(unsigned action){pthread_mutex_lock(&lock);unsigned value=action<28?bindings[action]:0;pthread_mutex_unlock(&lock);return value;}
void fnv_pad_apply_binding(FNVPadState *state,unsigned code){
    static const uint16_t masks[18]={0,1,2,0,8,4,0x10,0x20,0x40,0x80,0x1000,0x2000,0x4000,0x8000,0x200,0x100,0,0};
    if(code<18)state->buttons|=masks[code];
    if(code==16)state->left_trigger=255;if(code==17)state->right_trigger=255;
    if(code==19)state->ly=32767;if(code==20)state->ly=-32767;if(code==22)state->lx=32767;if(code==23)state->lx=-32767;
}
