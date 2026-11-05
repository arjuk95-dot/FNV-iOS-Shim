#include "shims.h"
#include "FNVPad.h"
#include "FNVDisplay.h"
#include "FNVTouchMath.h"
#include "FNVTouchPolicy.h"
#include "input.h"
#include <stdio.h>
#include <stdlib.h>
uint8_t *MEM;HostImport host_imports[MAX_IMPORTS];int host_import_count;static unsigned heap=0x80000;static int failed;
uint32_t gmalloc(uint32_t n){unsigned p=heap;heap+=n+16;return p;}void gfree(uint32_t p){(void)p;}
void gheap_report(void){}
void rt_trap(CPU *c,int n,uint32_t a){(void)c;(void)n;(void)a;abort();}
void fnv_input_mouse_camera(CPU *,uint32_t);extern const ShimTable xinput_shims,dinput_shims;
static void check(const char *name,int ok){printf("%s: %s\n",ok?"PASS":"FAIL",name);failed+=!ok;}
static unsigned call_fn(ShimFn fn,const uint32_t *args,unsigned n){CPU c={0};SETREG(&c,R_ESP,0x1000);P32(0x1000,0x123abc);for(unsigned i=0;i<n;i++)P32(0x1004+4*i,args[i]);fn(&c);if(REG(&c,R_ESP)!=0x1004+4*n)abort();return REG(&c,R_EAX);}
static unsigned call(unsigned index,const uint32_t *args,unsigned n){return call_fn(xinput_shims.list[index].fn,args,n);}
static unsigned method(uint32_t object,unsigned slot,const uint32_t *args,unsigned n){uint32_t thunk=G32(G32(object)+4*slot),index=(thunk-IMPORT_THUNK_BASE)/4,full[8]={object};if(thunk<IMPORT_THUNK_BASE||index>=(unsigned)host_import_count||n>=8)abort();for(unsigned i=0;i<n;i++)full[i+1]=args[i];return call_fn(host_imports[index].fn,full,n+1);}
int main(void){
    MEM=calloc(1,32<<20);
    P32(0x11d8a80,0x30000);MEM[0x30000]=1;P32(0x3000c,1);
    fnv_use_analog(1);fnv_move(0.5,1);fnv_pad_button(0x1000,1);fnv_pad_trigger(1,1);
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
    fnv_pad_stick_camera(1);c=expected;SETREG(&c,R_EAX,0xaabbcc01);CPU stickExpected=c;fnv_input_mouse_camera(&c,0x1234);
    check("stick-camera mode preserves original verified camera predicate",!memcmp(&c,&stickExpected,sizeof c));fnv_pad_stick_camera(0);
    call_fn(dinput_shims.list[0].fn,(uint32_t[]){0,0x800,0,0x2400,0},5);uint32_t di=G32(0x2400);
    P32(0x2500,0x6f1d2b60);method(di,3,(uint32_t[]){0x2500,0x2404,0},3);uint32_t mouse=G32(0x2404);
    uint32_t ofs,event;while(input_pop_event(1,&ofs,&event,-1)){}
    float sensitivity=.004f;memcpy(MEM+0x11e0a70,&sensitivity,4);
    input_mouse_move(7,-3);fnv_pad_mouse_move(40,-20);method(mouse,9,(uint32_t[]){20,0x2800},2);
    check("actual DirectInput mouse combines classic touch and independent mouse input",(int32_t)G32(0x2800)==47&&(int32_t)G32(0x2804)==-23);
    check("live original mouse sensitivity reaches gyro calibration",fabs(fnv_pad_mouse_radians()-.004f)<1e-9);
    method(mouse,9,(uint32_t[]){20,0x2800},2);check("touch-owned relative counts are consumed once",G32(0x2800)==0&&G32(0x2804)==0);
    while(input_pop_event(1,&ofs,&event,-1)){}input_mouse_move(6,-4);fnv_pad_mouse_move(40,20);fnv_pad_reset();
    check("touch reset removes only touch-owned buffered mouse events",input_pending(1)==2&&input_pop_event(1,&ofs,&event,-1)&&ofs==0&&(int32_t)event==6&&input_pop_event(1,&ofs,&event,-1)&&ofs==4&&(int32_t)event==-4);
    method(mouse,9,(uint32_t[]){20,0x2800},2);check("touch reset preserves independent relative mouse state",(int32_t)G32(0x2800)==6&&(int32_t)G32(0x2804)==-4);
    input_mouse_move(2,1);fnv_pad_mouse_move(80,90);MEM[0x11f308f+1002]=1;
    method(mouse,9,(uint32_t[]){20,0x2800},2);check("Pip-Boy transition clears relative camera before the first mouse snapshot",G32(0x2800)==2&&G32(0x2804)==1&&fnv_pad_context()==FNVContextPipBoy);
    fnv_pad_mouse_move(100,100);method(mouse,9,(uint32_t[]){20,0x2800},2);check("menus reject newly queued gameplay camera motion",G32(0x2800)==0&&G32(0x2804)==0);
    MEM[0x11f308f+1002]=0;call(0,(uint32_t[]){0,0x2000},2);while(input_pop_event(1,&ofs,&event,-1)){}
    input_mouse_move(6,-4);fnv_pad_mouse_move(40,20);MEM[0x11f308f+1056]=1;P32(0x27f0,8);
    method(mouse,10,(uint32_t[]){20,0x2900,0x27f0,1},4);
    check("VATS transition clears owned camera before buffered DirectInput reads",G32(0x27f0)==2&&G32(0x2900)==0&&(int32_t)G32(0x2904)==6&&G32(0x2914)==4&&(int32_t)G32(0x2918)==-4);
    MEM[0x11f308f+1056]=0;call(0,(uint32_t[]){0,0x2000},2);method(mouse,9,(uint32_t[]){20,0x2800},2);while(input_pop_event(1,&ofs,&event,-1)){}
    FNVPadState cameraPad={0};cameraPad.rx=17000;fnv_pad_mouse_move(42,84);input_mouse_move(1,2);fnv_pad_physical_state(&cameraPad,1);
    method(mouse,9,(uint32_t[]){20,0x2800},2);check("physical takeover clears only the touch camera channel",G32(0x2800)==1&&G32(0x2804)==2);
    c=stickExpected;fnv_input_mouse_camera(&c,0x1234);check("active physical camera preserves the original gamepad predicate",!memcmp(&c,&stickExpected,sizeof c));
    cameraPad=(FNVPadState){0};fnv_pad_physical_state(&cameraPad,1);c=stickExpected;fnv_input_mouse_camera(&c,0x1234);check("idle connected pad does not impose a cap on direct touch look",REG(&c,R_EAX)==0xaabbcc00);
    fnv_pad_physical_state(NULL,0);
    FNVLook look={100,100,0,0};FNVMouseDelta d=FNVLookTo(&look,110,96,1);check("swipe uses displacement without joystick velocity",d.dx==10&&d.dy==-4);d=FNVLookTo(&look,110,96,1);check("stationary touch produces no aim drift",!d.dx&&!d.dy);
    look=(FNVLook){200,150,0,0};d=FNVLookTo(&look,200,150,1);check("lift and re-touch do not jump camera",!d.dx&&!d.dy);
    FNVTouchVector movement=FNVTouchMove(1,0,54,.1,1);check("floating stick has a configurable radial dead zone",!movement.x&&!movement.y);
    movement=FNVTouchMove(180,-180,54,.1,1);check("floating movement saturates without diagonal acceleration",fabs(hypot(movement.x,movement.y)-1)<1e-9&&movement.x>0&&movement.y>0);
    FNVTouchContact aim=FNVTouchBegin(FNVTouchAimOwner,100,100,0);int transitions=FNVTouchFireSlide(&aim,1)+FNVTouchFireSlide(&aim,1);check("Aim slide enters Fire exactly once while held",transitions==1&&aim.fire);
    check("leaving Fire releases its own attack contribution",FNVTouchFireSlide(&aim,0)&&!aim.fire);
    FNVTouchContact swipe=FNVTouchBegin(FNVTouchLookOwner,100,100,0);check("ordinary swipe crossing Fire never acquires attack",!FNVTouchFireSlide(&swipe,1)&&!swipe.fire);
    FNVTouchContact utility=FNVTouchBegin(FNVTouchUtilityOwner,10,10,0);check("short utility tap remains a normal B tap",FNVTouchUtilityTap(&utility,.1,.38));
    check("utility hold is recognized once and consumes the B gesture",FNVTouchRecognizeHold(&utility,.4,.38)&&!FNVTouchRecognizeHold(&utility,.5,.38)&&!FNVTouchUtilityTap(&utility,.5,.38));
    check("radial center and outside releases cancel",FNVTouchSector(0,0,20,100,7)==-1&&FNVTouchSector(101,0,20,100,7)==-1&&FNVTouchSector(0,-70,20,100,7)==0);
    FNVTouchVector sixty=FNVTouchStick(6,0,0,0,1.0/60,.2,.2,360,.24,1.6,0,0),thirty=FNVTouchStick(12,0,0,0,1.0/30,.2,.2,360,.24,1.6,0,0);
    check("swipe conversion accounts for frame duration",fabs(sixty.x-thirty.x)<1e-9&&sixty.x>0);
    FNVTouchVector still=FNVTouchStick(0,0,0,0,1.0/60,.2,.2,360,.24,1.6,0,0);check("stationary camera has exactly neutral right stick",still.x==0&&still.y==0);
    FNVTouchVector cancelledLook=FNVTouchStick(10,0,-120,0,1.0/60,.2,.2,360,.24,1.6,0,0);check("gyro and swipe combine before final clamping",fabs(cancelledLook.x)<1e-9&&fabs(cancelledLook.y)<1e-9);
    FNVTouchVector maximum=FNVTouchStick(10000,10000,800,800,1.0/60,.2,.2,360,.24,1.6,0,0);check("maximum turn rate drops overflow instead of accumulating a tail",hypot(maximum.x,maximum.y)<=1.000001&&still.x==0&&still.y==0);
    FNVTouchRect tiny=FNVTouchPlace((FNVTouchRect){62,8,832,395},1,1,20);check("custom button stays inside the safe area",tiny.x>=62&&tiny.y>=8&&tiny.x+tiny.w<=894&&tiny.y+tiny.h<=403);
    FNVTouchRect adjacent[]={{100,100,20,20},{130,100,20,20}};int shown[]={1,1};check("small targets retain hit area and adjacent targets resolve by proximity",FNVTouchHit(adjacent,shown,2,96,110)==0&&FNVTouchHit(adjacent,shown,2,134,110)==1);
    FNVPadState touchState={0};touchState.lx=15000;touchState.ly=22000;touchState.rx=12000;touchState.ry=-9000;touchState.left_trigger=255;touchState.right_trigger=255;fnv_pad_touch_state(&touchState);call(0,(uint32_t[]){0,0x2000},2);
    check("movement, fire, Aim and right-stick look coexist in real XInput",G32(0x2004)==0xffff0000&&G32(0x2008)==((uint32_t)22000<<16|15000)&&G32(0x200c)==((uint32_t)(uint16_t)-9000<<16|12000));
    uint32_t beforeEpoch=fnv_pad_input_epoch();MEM[0x11f308f+1002]=1;call(0,(uint32_t[]){0,0x2000},2);
    check("first native Pip-Boy input snapshot releases gameplay LT RT and both sticks",fnv_pad_context()==FNVContextPipBoy&&fnv_pad_input_epoch()!=beforeEpoch&&G32(0x2004)==0&&G32(0x2008)==0&&G32(0x200c)==0);
    MEM[0x11f308f+1002]=0;MEM[0x11f308f+1056]=1;call(0,(uint32_t[]){0,0x2000},2);check("actual visibility changes detect VATS without observing a B tap",fnv_pad_context()==FNVContextVATS);
    MEM[0x11f308f+1056]=0;MEM[0x11f308f+1014]=1;call(0,(uint32_t[]){0,0x2000},2);check("actual menu state identifies lockpicking",fnv_pad_context()==FNVContextLockpick);MEM[0x11f308f+1014]=0;
    P32(0x3000c,0);call(0,(uint32_t[]){0,0x2000},2);check("initialized mode zero follows the original menu predicate",fnv_pad_context()==FNVContextMenu);
    P32(0x3000c,1);call(0,(uint32_t[]){0,0x2000},2);check("closing menus restores neutral gameplay context",fnv_pad_context()==FNVContextGameplay&&G32(0x2004)==0&&G32(0x2008)==0&&G32(0x200c)==0);
    FNVPadState controller={0};controller.buttons=0x1000;controller.right_trigger=170;controller.rx=17000;fnv_pad_physical_state(&controller,1);fnv_pad_reset();call(0,(uint32_t[]){0,0x2000},2);
    check("touch cancellation respects physical controller buttons trigger and look",G32(0x2004)==0xaa001000&&G32(0x200c)==17000);
    fnv_pad_touch_state(&touchState);call(0,(uint32_t[]){0,0x2000},2);check("physical takeover quarantines touch contributions",G32(0x2004)==0xaa001000&&G32(0x2008)==0&&G32(0x200c)==17000);
    fnv_pad_physical_state(NULL,0);call(0,(uint32_t[]){0,0x2000},2);check("controller disconnect leaves neutral transient state",G32(0x2004)==0&&G32(0x2008)==0&&G32(0x200c)==0);
    FNVPadState remapped={0};fnv_pad_apply_binding(&remapped,10);fnv_pad_apply_binding(&remapped,17);check("gameplay binding codes route to actual controller buttons and triggers",remapped.buttons==0x1000&&remapped.right_trigger==255);
    P32(0x11f35cc,0x50000);for(unsigned i=0;i<28;i++)MEM[0x50000+0x1be8+i]=(uint8_t)fnv_pad_binding(i);MEM[0x50000+0x1be8+4]=10;beforeEpoch=fnv_pad_input_epoch();fnv_pad_touch_state(&touchState);call(0,(uint32_t[]){0,0x2000},2);
    check("native remap table is sampled and old held bindings are released",fnv_pad_binding(4)==10&&fnv_pad_input_epoch()!=beforeEpoch&&G32(0x2004)==0&&G32(0x2008)==0&&G32(0x200c)==0);
    MEM[0x11f308f+1023]=1;P32(0x11da368,0x31000);P32(0x31080,32);
    call(0,(uint32_t[]){0,0x2000},2);check("actual Local Map page selects the native map-control context",fnv_pad_context()==FNVContextPipMap);
    FNVPadState mapInput={0};FNVTouchNavigationStick(&mapInput,FNVContextPipMap,0,54,-54,54,.1,1);FNVTouchNavigationStick(&mapInput,FNVContextPipMap,1,54,0,54,.1,1);
    fnv_pad_touch_state(&mapInput);call(0,(uint32_t[]){0,0x2000},2);
    check("real XInput delivers map pan on RS and zoom on LS without horizontal tab leakage",G32(0x2008)==0x7fff0000&&G32(0x200c)==0x7fff);
    mapInput.buttons=FNVTouchMapButton(6);fnv_pad_touch_state(&mapInput);call(0,(uint32_t[]){0,0x2000},2);check("map Zoom plus reaches native RB",(G32(0x2004)&0xffff)==0x200);
    mapInput.buttons=FNVTouchMapButton(2);fnv_pad_touch_state(&mapInput);MEM[0x11f308f+1001]=1;call(0,(uint32_t[]){0,0x2000},2);
    check("fast-travel confirmation takes priority over the underlying map and releases both sticks",fnv_pad_context()==FNVContextMenu&&G32(0x2004)==0&&G32(0x2008)==0&&G32(0x200c)==0);
    FNVPadState confirmation={0};confirmation.buttons=0x1000;fnv_pad_touch_state(&confirmation);call(0,(uint32_t[]){0,0x2000},2);check("a fresh A press can confirm native fast travel",(G32(0x2004)&0xffff)==0x1000);
    confirmation.buttons=0x2000;fnv_pad_touch_state(&confirmation);call(0,(uint32_t[]){0,0x2000},2);check("a fresh B press can cancel native fast travel",(G32(0x2004)&0xffff)==0x2000);
    MEM[0x11f308f+1001]=0;P32(0x31080,33);call(0,(uint32_t[]){0,0x2000},2);check("World Map restores neutral map controls after closing confirmation",fnv_pad_context()==FNVContextPipMap&&G32(0x2004)==0&&G32(0x2008)==0&&G32(0x200c)==0);
    MEM[0x11f308f+1013]=1;fnv_pad_touch_state(&mapInput);call(0,(uint32_t[]){0,0x2000},2);check("pause also overrides an underlying Pip-Boy map",fnv_pad_context()==FNVContextMenu&&G32(0x2008)==0&&G32(0x200c)==0);MEM[0x11f308f+1013]=0;
    P32(0x31080,34);call(0,(uint32_t[]){0,0x2000},2);check("Quests uses regular Pip-Boy controls instead of map-only zoom",fnv_pad_context()==FNVContextPipBoy);MEM[0x11f308f+1023]=0;call(0,(uint32_t[]){0,0x2000},2);
    fnv_pad_stick_camera(1);c=stickExpected;fnv_input_mouse_camera(&c,0x1234);
    check("standard fallback retains the original controller camera path",!memcmp(&c,&stickExpected,sizeof c));
    int rawFallback=1;P32(0x3000c,0);call(0,(uint32_t[]){0,0x2000},2);
    const uint16_t rawMasks[16]={0,0x100,0x20,0x10,0x200,0,1,2,4,8,0x1000,0x2000,0x4000,0x8000,0x40,0x80};
    for(unsigned i=0;i<16;i++){
        FNVPadState raw={0};FNVTouchFallbackButton(&raw,i);FNVTouchFallbackStick(&raw,0,54,0,54);FNVTouchFallbackStick(&raw,1,0,-54,54);fnv_pad_touch_state(&raw);call(0,(uint32_t[]){0,0x2000},2);
        if((G32(0x2004)&0xffff)!=rawMasks[i]||((G32(0x2004)>>16)&255)!=(i==0?255:0)||(G32(0x2004)>>24)!=(i==5?255:0)||G32(0x2008)!=0x7fff||G32(0x200c)!=0x7fff0000)rawFallback=0;
    }
    check("all fallback buttons triggers and two sticks cross the actual XInput ABI despite remapped gameplay bindings",rawFallback);
    fnv_pad_reset();call(0,(uint32_t[]){0,0x2000},2);check("fallback reset leaves a neutral native controller snapshot",G32(0x2004)==0&&G32(0x2008)==0&&G32(0x200c)==0);
    P32(0x3000c,1);call(0,(uint32_t[]){0,0x2000},2);fnv_pad_stick_camera(0);c=stickExpected;fnv_input_mouse_camera(&c,0x1234);
    check("leaving fallback restores classic direct-touch camera selection",REG(&c,R_EAX)==0xaabbcc00);
    fnv_display_configure(1320,2868);check("wide display preserves landscape native aspect within two pixels",fnv_display_width()==1440&&fnv_display_height()==662);
    fnv_display_client(1440,662);check("client dimensions agree with render target",fnv_client_width()==1440&&fnv_client_height()==662);
    fnv_use_analog(0);check("disabled pad reports disconnected",call(0,(uint32_t[]){0,0x2000},2)==1167);
    free(MEM);return failed?1:0;
}
