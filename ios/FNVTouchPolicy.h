#pragma once
#include <math.h>
#include <stddef.h>
#ifndef M_PI
#define M_PI 3.14159265358979323846
#endif

typedef struct {double x,y,w,h;} FNVTouchRect;
typedef struct {double x,y;} FNVTouchVector;
static inline double FNVTouchClamp(double v,double lo,double hi){return isfinite(v)?fmax(lo,fmin(hi,v)):lo;}
static inline int FNVTouchContains(FNVTouchRect r,double x,double y){return x>=r.x&&y>=r.y&&x<=r.x+r.w&&y<=r.y+r.h;}
static inline FNVTouchRect FNVTouchPlace(FNVTouchRect safe,double x,double y,double diameter){
    double d=FNVTouchClamp(diameter,20,fmin(safe.w,safe.h));
    double px=fmin(fmax(22,d/2),safe.w/2),py=fmin(fmax(22,d/2),safe.h/2);
    return (FNVTouchRect){FNVTouchClamp(safe.x+x*safe.w,safe.x+px,safe.x+safe.w-px)-d/2,FNVTouchClamp(safe.y+y*safe.h,safe.y+py,safe.y+safe.h-py)-d/2,d,d};
}
static inline FNVTouchRect FNVTouchRegion(FNVTouchRect safe,double x,double y,double w,double h){
    w=FNVTouchClamp(w,.08,1);h=FNVTouchClamp(h,.08,1);
    return(FNVTouchRect){safe.x+FNVTouchClamp(x,0,1-w)*safe.w,safe.y+FNVTouchClamp(y,0,1-h)*safe.h,w*safe.w,h*safe.h};
}
static inline int FNVTouchRecoveryGesture(unsigned activeFingers){return activeFingers>=4;}
// Resolve overlapping minimum-sized targets by nearest normalized center.
static inline int FNVTouchHit(const FNVTouchRect *frames,const int *visible,size_t count,double x,double y){
    double best=1e30;int selected=-1;
    for(size_t i=0;i<count;i++)if(!visible||visible[i]){
        FNVTouchRect r=frames[i];double rx=fmax(22,r.w/2),ry=fmax(22,r.h/2);
        double dx=(x-r.x-r.w/2)/rx,dy=(y-r.y-r.h/2)/ry,score=dx*dx+dy*dy;
        if(score<=1&&score<best){best=score;selected=(int)i;}
    }
    return selected;
}
static inline FNVTouchVector FNVTouchMove(double dx,double dy,double radius,double deadzone,double response){
    double length=hypot(dx,dy),unit=length/fmax(1,radius),dz=FNVTouchClamp(deadzone,0,.8);
    if(length==0||unit<=dz)return(FNVTouchVector){0,0};
    double amount=pow(FNVTouchClamp((unit-dz)/(1-dz),0,1),FNVTouchClamp(response,.25,4));
    return(FNVTouchVector){dx/length*amount,-dy/length*amount};
}
// No motion is carried into a later frame. Excess velocity is deliberately
// discarded at the game's maximum turn rate instead of becoming a turn tail.
static inline FNVTouchVector FNVTouchStick(double touchX,double touchY,double gyroX,double gyroY,double dt,double gainX,double gainY,double maxRate,double deadzone,double response,int invertX,int invertY){
    dt=FNVTouchClamp(dt,.001,.15);maxRate=fmax(1,maxRate);
    double vx=touchX*gainX/dt*(invertX?-1:1)+gyroX;
    double vy=-touchY*gainY/dt*(invertY?-1:1)+gyroY;
    double length=hypot(vx,vy);if(length<.001)return(FNVTouchVector){0,0};
    double magnitude=FNVTouchClamp(length/maxRate,0,1);
    double corrected=FNVTouchClamp(deadzone,0,.8)+(1-FNVTouchClamp(deadzone,0,.8))*pow(magnitude,1/FNVTouchClamp(response,.25,4));
    return(FNVTouchVector){vx/length*corrected,vy/length*corrected};
}
// Sector zero starts at twelve o'clock. A center/outside release cancels.
static inline int FNVTouchSector(double dx,double dy,double inner,double outer,unsigned count){
    double length=hypot(dx,dy);if(!count||length<inner||length>outer)return-1;
    double angle=atan2(dx,-dy)+M_PI/(double)count;
    if(angle<0)angle+=2*M_PI;
    return(int)(angle/(2*M_PI)*count)%count;
}
typedef struct {double startX,startY,lastX,lastY,began;int owner,consumed,fire;} FNVTouchContact;
enum {FNVTouchNone,FNVTouchMoveOwner,FNVTouchLookOwner,FNVTouchFireOwner,FNVTouchAimOwner,FNVTouchUtilityOwner,FNVTouchActionOwner,FNVTouchOverlayOwner,FNVTouchMenuOwner,FNVTouchEditOwner};
static inline FNVTouchContact FNVTouchBegin(int owner,double x,double y,double time){return(FNVTouchContact){x,y,x,y,time,owner,0,owner==FNVTouchFireOwner};}
static inline int FNVTouchRecognizeHold(FNVTouchContact *c,double now,double threshold){if(c->owner!=FNVTouchUtilityOwner||c->consumed||now-c->began<threshold)return 0;c->consumed=1;return 1;}
static inline int FNVTouchUtilityTap(const FNVTouchContact *c,double now,double threshold){return c->owner==FNVTouchUtilityOwner&&!c->consumed&&now-c->began<threshold&&hypot(c->lastX-c->startX,c->lastY-c->startY)<24;}
static inline int FNVTouchFireSlide(FNVTouchContact *c,int inside){if(c->owner!=FNVTouchFireOwner&&c->owner!=FNVTouchAimOwner)return 0;int changed=c->fire!=!!inside;c->fire=!!inside;return changed;}
