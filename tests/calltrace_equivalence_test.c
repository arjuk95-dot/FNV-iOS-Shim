// Authored guest-style calls exercise the real runtime helpers in both trace modes.
#include "rt.h"
#include <assert.h>
#include <stdio.h>
uint8_t arena[4096];
uint8_t *MEM=arena;
#ifdef RT_CALLTRACE
_Thread_local uint32_t rt_ct_ring[256],rt_ct_pos;
#endif
static uint32_t entries;
static __attribute__((noinline)) void leaf(CPU *c,uint32_t x){
    RT_ENTER(0x401000u);entries++;
    uint32_t p=(x&255)*4,v=(uint32_t)LD(GM(p),4);
    ST(GM(p),v+x+17,4);ST(c->r+4,LD(c->r+4,4)^v,4);
    c->r[518]=(uint8_t)(v==0);
}
static __attribute__((noinline)) void branch(CPU *c,uint32_t x){
    RT_ENTER(0x402000u);entries++;
    U v=LD(c->r,4);leaf(c,x);leaf(c,x^0x9e3779b9u);
    ST(c->r,v+(U)x*3,4);
}
int main(void){
    CPU c={0};uint32_t x=0x12345678;
    for(unsigned i=0;i<10000;i++){x=x*1664525u+1013904223u;branch(&c,x);}
    assert(entries==30000);
#ifdef RT_CALLTRACE
    assert(rt_ct_pos==entries&&rt_ct_ring[(rt_ct_pos-1)&255]==0x401000u);
#endif
    uint64_t h=1469598103934665603ull;
    for(unsigned i=0;i<sizeof c.r;i++)h=(h^c.r[i])*1099511628211ull;
    for(unsigned i=0;i<sizeof arena;i++)h=(h^arena[i])*1099511628211ull;
    printf("%016llx\n",(unsigned long long)h);return 0;
}
