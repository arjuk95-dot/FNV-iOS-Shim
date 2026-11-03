#include "FNVPad.h"
#include "input.h"
#include <math.h>
#include <pthread.h>
static pthread_mutex_t lock = PTHREAD_MUTEX_INITIALIZER;
static int16_t x, y;
static uint32_t packet;
static int analog;
static uint16_t buttons;
static uint8_t triggers[2];
static int16_t axis(float v) {
    return (int16_t)lroundf(fmaxf(-1, fminf(1, v)) * 32767);
}
void fnv_move(float right, float forward) {
    pthread_mutex_lock(&lock);
    int16_t nextX = axis(right), nextY = axis(forward);
    if (nextX != x || nextY != y) {
        x = nextX; y = nextY; ++packet;
        if (!analog) {
            input_key(0x11, y > 5500); input_key(0x1f, y < -5500);
            input_key(0x20, x > 5500); input_key(0x1e, x < -5500);
        }
    }
    pthread_mutex_unlock(&lock);
}
void fnv_pad_state(int16_t *outX, int16_t *outY, uint32_t *seq) {
    pthread_mutex_lock(&lock);
    *outX = x; *outY = y; *seq = packet;
    pthread_mutex_unlock(&lock);
}
void fnv_use_analog(int enabled) {
    // Called during startup, before accepting movement.
    pthread_mutex_lock(&lock); analog = !!enabled; pthread_mutex_unlock(&lock);
}
int fnv_analog_enabled(void) {
    pthread_mutex_lock(&lock); int enabled = analog; pthread_mutex_unlock(&lock);
    return enabled;
}
void fnv_pad_snapshot(FNVPadState *state){pthread_mutex_lock(&lock);*state=(FNVPadState){packet,buttons,triggers[0],triggers[1],x,y,0,0};pthread_mutex_unlock(&lock);}
void fnv_pad_button(uint16_t mask,int down){pthread_mutex_lock(&lock);uint16_t next=down?(buttons|mask):(buttons&~mask);if(next!=buttons){buttons=next;packet++;}pthread_mutex_unlock(&lock);}
void fnv_pad_trigger(int right,int down){pthread_mutex_lock(&lock);unsigned i=!!right;uint8_t next=down?255:0;if(triggers[i]!=next){triggers[i]=next;packet++;}pthread_mutex_unlock(&lock);}
void fnv_pad_reset(void){fnv_move(0,0);pthread_mutex_lock(&lock);if(buttons||triggers[0]||triggers[1]){buttons=0;triggers[0]=triggers[1]=0;packet++;}pthread_mutex_unlock(&lock);}
