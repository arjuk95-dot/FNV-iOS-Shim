#include <stdio.h>
#include <stdlib.h>
#include "host.h"
uint8_t *MEM;
void rt_diag_watch(CPU *,uint32_t,const uint32_t *,unsigned);
int main(void){
    MEM=calloc(1,1<<20);uint8_t *before=malloc(1<<20);CPU c={0},original;
    SETREG(&c,R_ESP,0x10100);SETREG(&c,R_ECX,0x8000);SETREG(&c,20,0x10010);SETREG(&c,272,0x4000);
    P32(0x4024,9);P32(0x4008,0x10000);P32(0x4004,0x20000);P32(0x10100,0x401123);
    P32(0x10010,0x10020);P32(0x10014,0x401234);P32(0x10024,0x402345);
    P32(0x8000,0x123);P32(0x8008,0x456);P32(0x8010,0x789);
    original=c;memcpy(before,MEM,1<<20);
    for(int i=0;i<1024;i++)rt_diag_watch(&c,0x401000,(uint32_t[]){0,8,16},3);
    if(memcmp(&original,&c,sizeof c)||memcmp(before,MEM,1<<20))return 1;
    puts("PASS: selected-entry samples preserve guest registers and memory");return 0;
}
