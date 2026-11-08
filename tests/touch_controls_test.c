#include <stdio.h>
#include <math.h>
#include <string.h>
#include <stdlib.h>
#include "FNVPad.h"
#include "FNVTouchPolicy.h"
static unsigned failed;
void input_key(int key,int down){(void)key;(void)down;}
void input_touch_mouse_reset(void){}
void input_touch_mouse_move(int x,int y){(void)x;(void)y;}
static void check(const char *name,int value){printf("%s: %s\n",value?"PASS":"FAIL",name);failed+=!value;}
int main(void){
    fnv_use_analog(1);FNVPadState touch={0},out={0};touch.lx=12300;touch.ly=18000;touch.rx=17000;touch.ry=-12000;touch.left_trigger=touch.right_trigger=255;fnv_pad_touch_state(&touch);fnv_pad_snapshot(&out);
    check("independent movement aim fire and look",out.lx==12300&&out.ly==18000&&out.rx==17000&&out.ry==-12000&&out.left_trigger==255&&out.right_trigger==255);
    uint32_t epoch=fnv_pad_input_epoch();fnv_pad_context_set(FNVContextPipBoy);fnv_pad_snapshot(&out);check("context transition clears touch before snapshot",out.lx==0&&out.ly==0&&out.rx==0&&out.ry==0&&out.left_trigger==0&&out.right_trigger==0&&fnv_pad_input_epoch()!=epoch);
    FNVPadState physical={0};physical.buttons=0x1000;physical.right_trigger=150;physical.rx=14000;fnv_pad_physical_state(&physical,1);fnv_pad_touch_state(&touch);fnv_pad_snapshot(&out);check("physical activity quarantines touch source",out.buttons==0x1000&&out.right_trigger==150&&out.left_trigger==0&&out.lx==0&&out.rx==14000);
    fnv_pad_reset();fnv_pad_snapshot(&out);check("touch cancellation preserves physical held inputs",out.buttons==0x1000&&out.right_trigger==150&&out.rx==14000);
    fnv_pad_physical_state(NULL,0);fnv_pad_snapshot(&out);check("disconnect leaves neutral source state",out.buttons==0&&out.right_trigger==0&&out.rx==0);
    physical=(FNVPadState){0};physical.rx=2000;fnv_pad_physical_state(&physical,1);fnv_pad_touch_state(&touch);fnv_pad_snapshot(&out);check("physical stick noise does not steal touch",!fnv_pad_physical_active()&&out.lx==touch.lx&&out.rx==touch.rx);fnv_pad_physical_state(NULL,0);fnv_pad_reset();
    FNVTouchContact aim=FNVTouchBegin(FNVTouchAimOwner,10,10,0);check("Aim slide enters Fire once",FNVTouchFireSlide(&aim,1)&&!FNVTouchFireSlide(&aim,1)&&aim.fire);check("leaving Fire releases attack",FNVTouchFireSlide(&aim,0)&&!aim.fire);
    FNVTouchContact swipe=FNVTouchBegin(FNVTouchLookOwner,10,10,0);check("ordinary swipe cannot acquire Fire",!FNVTouchFireSlide(&swipe,1)&&!swipe.fire);
    aim=FNVTouchBegin(FNVTouchAimOwner,10,10,0);
    check("short Aim contact is a tap without entering ADS",FNVTouchAimTap(&aim,.1,.32,1)&&!FNVTouchAimHold(&aim,.1,.32,1));
    check("Aim hold consumes once at the threshold and cannot also tap",FNVTouchAimHold(&aim,.32,.32,1)&&!FNVTouchAimHold(&aim,.5,.32,1)&&!FNVTouchAimTap(&aim,.5,.32,1));
    aim=FNVTouchBegin(FNVTouchAimOwner,10,10,0);
    check("release can recognize a hold missed by a busy display tick",FNVTouchAimHold(&aim,1,.32,1));
    aim=FNVTouchBegin(FNVTouchAimOwner,10,10,0);
    check("releasing outside Aim triggers neither tap nor hold",!FNVTouchAimTap(&aim,.1,.32,0)&&!FNVTouchAimHold(&aim,.5,.32,0));
    aim.lastX=60;check("dragging across Aim is not a short tap",!FNVTouchAimTap(&aim,.1,.32,1));
    check("non-Aim contacts cannot trigger the Aim gesture",!FNVTouchAimTap(&swipe,.1,.32,1)&&!FNVTouchAimHold(&swipe,.5,.32,1));
    FNVTouchContact pip=FNVTouchBegin(FNVTouchUtilityOwner,10,10,0);check("utility short tap",FNVTouchUtilityTap(&pip,.1,.38));check("utility hold consumes B exactly once",FNVTouchRecognizeHold(&pip,.5,.38)&&!FNVTouchRecognizeHold(&pip,.6,.38)&&!FNVTouchUtilityTap(&pip,.6,.38));
    check("radial cancel boundaries",FNVTouchSector(0,0,24,125,7)==-1&&FNVTouchSector(130,0,24,125,7)==-1&&FNVTouchSector(0,-90,24,125,7)==0);
    FNVTouchVector a=FNVTouchStick(6,0,0,0,1.0/60,.2,.2,360,.24,1.6,0,0),b=FNVTouchStick(12,0,0,0,1.0/30,.2,.2,360,.24,1.6,0,0);check("frame-time normalized swipe",fabs(a.x-b.x)<1e-9&&a.x>0);
    b=FNVTouchStick(36,0,0,0,.1,.2,.2,360,.24,1.6,0,0);check("a slow UI frame does not amplify swipe velocity",fabs(a.x-b.x)<1e-9);
    a=FNVTouchStick(0,0,0,0,1.0/60,.2,.2,360,.24,1.6,0,0);check("stationary right stick has no tail",a.x==0&&a.y==0);
    a=FNVTouchStick(10,0,-120,0,1.0/60,.2,.2,360,.24,1.6,0,0);check("gyro combines before clamp",a.x==0&&a.y==0);
    a=FNVTouchStick(10000,10000,800,800,1.0/60,.2,.2,360,.24,1.6,0,0);check("combined maximum is bounded",hypot(a.x,a.y)<=1.000001);
    FNVTouchVector carry={0};FNVLook classic={0};int equal=1;double x=0,y=0;
    const double packets[][3]={{.125,-.25,.016},{1.5,2.25,.033},{40,-10,.010},{258.375,8,.140}};
    for(unsigned i=0;i<4;i++){x+=packets[i][0];y+=packets[i][1];FNVMouseDelta old=FNVLookTo(&classic,x,y,3),now=FNVTouchRelative(&carry,packets[i][0],packets[i][1],0,0,packets[i][2],3,3,3,3,.002,1,1,0,0);if(old.dx!=now.dx||old.dy!=now.dy)equal=0;}
    check("direct swipe exactly matches classic Aim 3x across fractional packets and frame times",equal);
    carry=(FNVTouchVector){0};FNVMouseDelta direct=FNVTouchRelative(&carry,300,0,0,0,.2,3,3,3,3,.002,1,1,0,0);
    check("fast 300-point swipe retains all 900 counts beyond the controller turn cap",direct.dx==900&&direct.dy==0);
    carry=(FNVTouchVector){0};int gyroCounts=0;
    for(unsigned i=0;i<120;i++){FNVMouseDelta delta=FNVTouchRelative(&carry,0,0,1,0,1.0/120,3,3,3,3,.002,1,1,0,0);gyroCounts+=delta.dx;}
    check("gyro 3x produces three camera radians per device radian independent of sample rate",abs(gyroCounts-1500)<=1);
    carry=(FNVTouchVector){0};direct=FNVTouchRelative(&carry,10,0,-.6,0,.1,3,3,1,1,.002,1,1,0,0);
    check("opposite gyro and swipe combine before relative-count quantization",direct.dx==0);
    carry=(FNVTouchVector){0};direct=FNVTouchRelative(&carry,10,0,.1,0,.1,3,3,3,3,.002,2,.5,0,0);
    check("common and aiming multipliers apply equally to swipe and gyro",direct.dx==45);
    carry=(FNVTouchVector){0};direct=FNVTouchRelative(&carry,0,0,1,0,.1,3,3,3,3,.004,1,1,0,0);
    check("gyro calibration follows the live game's mouse sensitivity",direct.dx==75);
    carry=(FNVTouchVector){.4,-.4};direct=FNVTouchRelative(&carry,0,0,0,0,.016,3,3,3,3,.002,1,1,0,0);
    check("fractional camera carry cannot rotate a stationary view",direct.dx==0&&direct.dy==0);
    FNVTouchVector filtered=FNVTouchSmooth((FNVTouchVector){0},20,10,.016,.025);
    check("optional smoothing preserves the first swipe's full distance",fabs(hypot(filtered.x,filtered.y)-hypot(20,10))<1e-9);
    filtered=FNVTouchSmooth(filtered,10,20,.016,.025);
    check("direction smoothing preserves subsequent swipe distance",fabs(hypot(filtered.x,filtered.y)-hypot(10,20))<1e-9);
    filtered=FNVTouchSmooth(filtered,0,0,.016,.025);check("smoothing stops immediately without a rotation tail",filtered.x==0&&filtered.y==0);
    filtered=FNVTouchSmooth((FNVTouchVector){20,0},-20,0,.016,.12);check("reversing a swipe never turns in the previous direction",filtered.x==-20&&filtered.y==0);
    FNVPadState mapControls={0};
    FNVTouchNavigationStick(&mapControls,FNVContextPipMap,0,54,-54,54,.1,1);
    FNVTouchNavigationStick(&mapControls,FNVContextPipMap,1,54,0,54,.1,1);
    check("Pip-Boy map has independent right-stick pan and vertical-only left-stick zoom",mapControls.lx==0&&mapControls.ly==32767&&mapControls.rx==32767&&mapControls.ry==0);
    FNVPadState stationaryMap={0};FNVTouchNavigationStick(&stationaryMap,FNVContextPipMap,1,54,0,54,.1,1);
    check("holding the map stick keeps panning without repeated swipes",stationaryMap.rx==mapControls.rx&&stationaryMap.ry==mapControls.ry);
    FNVTouchNavigationStick(&stationaryMap,FNVContextPipMap,1,0,0,54,.1,1);check("releasing the map stick returns pan to neutral",stationaryMap.rx==0&&stationaryMap.ry==0);
    check("map controls use native A selection X marker and LB/RB zoom masks",FNVTouchMapButton(2)==0x1000&&FNVTouchMapButton(4)==0x4000&&FNVTouchMapButton(6)==0x200&&FNVTouchMapButton(7)==0x100);
    check("Data tabs stay on native D-pad left and right",FNVTouchMapButton(8)==4&&FNVTouchMapButton(9)==8);
    check("both Pip-Boy page families expose a right navigation stick without enabling gameplay look",FNVTouchRightStickContext(FNVContextPipBoy)&&FNVTouchRightStickContext(FNVContextPipMap)&&!FNVTouchRightStickContext(FNVContextGameplay)&&!FNVTouchRightStickContext(FNVContextDialogue));
    a=FNVTouchMove(1,1,54,.1,1);check("floating movement deadzone",a.x==0&&a.y==0);a=FNVTouchMove(200,-200,54,.1,1);check("radial movement saturation",fabs(hypot(a.x,a.y)-1)<1e-9);
    const FNVTouchRect safe[]={{62,8,832,395},{8,8,552,304},{8,8,1008,740}};
    int valid=1;for(unsigned i=0;i<3;i++)for(unsigned j=0;j<4;j++){FNVTouchRect r=FNVTouchPlace(safe[i],j&1?1:0,j&2?1:0,140);if(r.x<safe[i].x||r.y<safe[i].y||r.x+r.w>safe[i].x+safe[i].w||r.y+r.h>safe[i].y+safe[i].h)valid=0;}check("normalized layouts fit safe areas and rotations",valid);
    FNVTouchRect targets[]={{100,100,20,20},{130,100,20,20}};check("minimum hit area and nearest overlap resolution",FNVTouchHit(targets,NULL,2,96,110)==0&&FNVTouchHit(targets,NULL,2,135,110)==1);
    FNVTouchRect tiny=FNVTouchPlace(safe[0],1,1,20);check("small icon retains its full hit area inside the safe inset",tiny.x+tiny.w/2+22<=safe[0].x+safe[0].w&&tiny.y+tiny.h/2+22<=safe[0].y+safe[0].h);
    FNVTouchRect region=FNVTouchRegion(safe[0],1,1,.7,.8);check("resized activation region stays fully inside the safe area",region.x>=safe[0].x&&region.y>=safe[0].y&&region.x+region.w<=safe[0].x+safe[0].w&&region.y+region.h<=safe[0].y+safe[0].h);
    check("a third gameplay finger cannot trigger editor recovery",!FNVTouchRecoveryGesture(3)&&FNVTouchRecoveryGesture(4));
    FNVPadState fallback={0};for(unsigned i=0;i<FNVTouchFallbackCount;i++)FNVTouchFallbackButton(&fallback,i);
    check("standard controller exposes every XInput digital button and both independent triggers",fallback.buttons==0xf3ff&&fallback.left_trigger==255&&fallback.right_trigger==255);
    fallback=(FNVPadState){0};FNVTouchFallbackButton(&fallback,FNVTouchFallbackLT);
    check("fallback LT is an unremapped held left trigger",fallback.left_trigger==255&&fallback.right_trigger==0&&fallback.buttons==0);
    fallback=(FNVPadState){0};FNVTouchFallbackButton(&fallback,FNVTouchFallbackRT);
    check("fallback RT is an unremapped held right trigger",fallback.right_trigger==255&&fallback.left_trigger==0&&fallback.buttons==0);
    fallback=(FNVPadState){0};FNVTouchFallbackStick(&fallback,0,54,-54,54);FNVTouchFallbackStick(&fallback,1,-54,54,54);
    check("fallback sticks retain both axes without context-specific map zoom constraints",fallback.lx>0&&fallback.ly>0&&fallback.rx<0&&fallback.ry<0);
    FNVTouchFallbackStick(&fallback,0,0,0,54);FNVTouchFallbackStick(&fallback,1,0,0,54);
    check("fallback stick release is neutral",fallback.lx==0&&fallback.ly==0&&fallback.rx==0&&fallback.ry==0);
    int fallbackValid=1;
    for(unsigned i=0;i<3;i++){
        FNVTouchRect frames[FNVTouchFallbackCount];
        for(unsigned j=0;j<FNVTouchFallbackCount;j++){
            frames[j]=FNVTouchFallbackFrame(safe[i],j);FNVTouchRect r=frames[j];
            if(r.w<44||r.x<safe[i].x||r.y<safe[i].y||r.x+r.w>safe[i].x+safe[i].w||r.y+r.h>safe[i].y+safe[i].h)fallbackValid=0;
        }
        for(unsigned j=0;j<FNVTouchFallbackCount;j++){FNVTouchRect r=frames[j];if(FNVTouchHit(frames,NULL,FNVTouchFallbackCount,r.x+r.w/2,r.y+r.h/2)!=(int)j)fallbackValid=0;}
        for(int right=0;right<2;right++){FNVTouchRect r=FNVTouchFallbackRegion(safe[i],right);if(r.w<100||r.h<80||r.x<safe[i].x||r.y<safe[i].y||r.x+r.w>safe[i].x+safe[i].w||r.y+r.h>safe[i].y+safe[i].h)fallbackValid=0;}
    }
    check("all sixteen emergency controls remain individually reachable in compact phone and tablet safe areas",fallbackValid);
    FNVPadState remapped={0};fnv_pad_apply_binding(&remapped,10);fnv_pad_apply_binding(&remapped,17);check("live binding decoder uses XInput outputs",remapped.buttons==0x1000&&remapped.right_trigger==255);
    printf("%u failure(s)\n",failed);return failed?1:0;
}
