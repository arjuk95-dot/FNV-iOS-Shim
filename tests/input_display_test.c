#include "shims.h"
#include "FNVPad.h"
#include "FNVDisplay.h"
#include "FNVTouchMath.h"
#include "input.h"
#include <stdio.h>
#include <stdlib.h>
uint8_t *MEM;HostImport host_imports[MAX_IMPORTS];int host_import_count;static unsigned heap=0x80000;static int failed;
uint32_t gmalloc(uint32_t n){unsigned p=heap;heap+=n+16;return p;}void gfree(uint32_t p){(void)p;}
void gheap_report(void){}
void rt_trap(CPU *c,int n,uint32_t a){(void)c;(void)n;(void)a;abort();}
void fnv_input_mouse_camera(CPU *,uint32_t);extern const ShimTable xinput_shims;
static void check(const char *name,int ok){printf("%s: %s\n",ok?"PASS":"FAIL",name);failed+=!ok;}
static unsigned call(unsigned index,const uint32_t *args,unsigned n){CPU c={0};SETREG(&c,R_ESP,0x1000);P32(0x1000,0x123abc);for(unsigned i=0;i<n;i++)P32(0x1004+4*i,args[i]);xinput_shims.list[index].fn(&c);if(REG(&c,R_ESP)!=0x1004+4*n)abort();return REG(&c,R_EAX);}
int main(void){
    MEM=calloc(1,4<<20);fnv_use_analog(1);fnv_move(0.5,1);fnv_pad_button(0x1000,1);fnv_pad_trigger(1,1);
    check("real XInput ABI exposes stick, ABXY and trigger simultaneously",call(0,(uint32_t[]){0,0x2000},2)==0&&G32(0x2004)==0xff001000&&G32(0x2008)==0x7fff4000&&G32(0x200c)==0);
    unsigned packet=G32(0x2000);call(0,(uint32_t[]){0,0x2000},2);check("unchanged polling preserves packet number",G32(0x2000)==packet);
    input_mouse_move(13,-7);int32_t dx,dy,dz;uint8_t buttons[8];input_mouse_state(&dx,&dy,&dz,buttons);
    check("relative mouse remains independent of active XInput",dx==13&&dy==-7&&call(0,(uint32_t[]){0,0x2000},2)==0&&G32(0x200c)==0);
    input_mouse_state(&dx,&dy,&dz,buttons);check("mouse deltas are consumed exactly once",!dx&&!dy);
    fnv_pad_reset();call(0,(uint32_t[]){0,0x2000},2);check("lifecycle reset releases all buttons, triggers and movement",G32(0x2004)==0&&G32(0x2008)==0&&G32(0x200c)==0&&G32(0x2000)>packet);
    check("other controller indices stay disconnected",call(0,(uint32_t[]){1,0x2000},2)==1167);
    check("capabilities advertise actual buttons/triggers/axes",call(2,(uint32_t[]){0,0,0x2100},3)==0&&G32(0x2104)==0xfffff3ff&&G32(0x2108)==0x7fff7fff);
    CPU c={0};memset(&c,0x35,sizeof c);SETREG(&c,R_EAX,0xaabbcc01);CPU expected=c;SETREG(&expected,R_EAX,0xaabbcc00);fnv_input_mouse_camera(&c,0x1234);
    check("camera compatibility changes only AL, preserving flags and guest state",!memcmp(&c,&expected,sizeof c));
    FNVLook look={100,100,0,0};FNVMouseDelta d=FNVLookTo(&look,110,96,1);check("swipe uses displacement without joystick velocity",d.dx==10&&d.dy==-4);d=FNVLookTo(&look,110,96,1);check("stationary touch produces no aim drift",!d.dx&&!d.dy);
    look=(FNVLook){200,150,0,0};d=FNVLookTo(&look,200,150,1);check("lift and re-touch do not jump camera",!d.dx&&!d.dy);
    fnv_display_configure(1320,2868);check("wide display preserves landscape native aspect within two pixels",fnv_display_width()==1440&&fnv_display_height()==662);
    fnv_display_client(1440,662);check("client dimensions agree with render target",fnv_client_width()==1440&&fnv_client_height()==662);
    fnv_use_analog(0);check("disabled pad reports disconnected",call(0,(uint32_t[]){0,0x2000},2)==1167);
    free(MEM);return failed?1:0;
}
