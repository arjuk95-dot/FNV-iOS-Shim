#import "FNVGameplayTouchView.h"
#import "FNVTouchMath.h"
#import "FNVTouchPolicy.h"
#import "FNVTouchSettings.h"
#include "FNVPad.h"
#include "input.h"
#import <CoreMotion/CoreMotion.h>
#import <GameController/GameController.h>
#import <QuartzCore/QuartzCore.h>

static const unsigned FNVGameplayActions[6]={4,6,5,12,16,14};
static const unsigned FNVMenuMasks[10]={0,0,0x1000,0x2000,0x4000,0x8000,1,2,4,8};
@interface FNVFinger : NSObject
@property(nonatomic) FNVTouchContact state;
@property(nonatomic) NSInteger action;
@property(nonatomic) CGPoint origin;
@property(nonatomic) BOOL aimWasOn;
@end
@implementation FNVFinger @end

@interface FNVGameplayTouchView ()
- (void)tick:(CADisplayLink *)link;
- (void)openEditor;
- (void)rebuildEditor;
- (void)drawRadial:(CGContextRef)cg;
- (void)drawMore:(CGContextRef)cg;
- (void)dragSelectionBy:(CGPoint)delta;
- (void)updateMotion;
- (void)closeEditorApply:(BOOL)apply;
- (void)toggleStandardController:(UITapGestureRecognizer *)recognizer;
- (void)performUtility:(NSUInteger)action;
- (void)assignUtility:(NSUInteger)action radial:(BOOL)radial slot:(NSUInteger)slot;
- (CGFloat)utilityEditorAt:(CGFloat)y;
- (NSString *)utilityName:(NSUInteger)action;
- (void)toggleGyro;
- (void)recognizeAimHold:(FNVFinger *)finger at:(double)now;
@end

@interface FNVTouchDisplayProxy : NSObject
@property(nonatomic,weak) FNVGameplayTouchView *owner;
- (void)step:(CADisplayLink *)link;
@end
@implementation FNVTouchDisplayProxy
- (void)step:(CADisplayLink *)link {[self.owner tick:link];}
@end

@implementation FNVGameplayTouchView {
    NSMutableDictionary<NSValue *,FNVFinger *> *_fingers;
    NSMutableArray<NSDictionary *> *_pulses;
    NSMutableDictionary *_settings,*_beforeEdit;
    NSMutableArray *_fallbackButtons;
    CADisplayLink *_displayLink;
    CMMotionManager *_motion;
    CGRect _safe,_frames[FNVTouchFallbackCount],_moveRegion,_lookRegion;
    CGSize _lastSize;
    UIEdgeInsets _lastInsets;
    UIInterfaceOrientation _lastOrientation;
    NSInteger _count,_overlay,_radialSelection,_selected,_editorSlot;
    BOOL _aimed,_radialArmed,_editing,_editingPip,_editorPreview,_suspended,_reportedCamera;
    BOOL _standardFallback;
    BOOL _editingUtilities;
    CGPoint _radialOrigin,_radialStart;
    CGFloat _radialRadius;
    double _lastFrame,_lookDX,_lookDY,_smoothX,_smoothY,_gyroRateX,_gyroRateY,_gyroSampleAt,_biasX,_biasY,_calibrateUntil,_biasSumX,_biasSumY;
    FNVLook _probeLook;
    FNVTouchVector _relativeCarry;
    unsigned _biasSamples;
    uint32_t _inputEpoch;
    FNVInputContext _context;
    UIScrollView *_editorPanel;
    UIButton *_editorReturn;
    double _recoveryStarted;
}

- (instancetype)initWithFrame:(CGRect)frame {
    self=[super initWithFrame:frame];if(!self)return nil;
    self.multipleTouchEnabled=YES;self.opaque=NO;self.backgroundColor=UIColor.clearColor;
    _lookGain=1;_movementRadius=54;_fingers=[NSMutableDictionary new];_pulses=[NSMutableArray new];
    _settings=FNVTouchLoadSettings(NSUserDefaults.standardUserDefaults);
    _fallbackButtons=[NSMutableArray new];for(unsigned i=0;i<FNVTouchFallbackCount;i++)[_fallbackButtons addObject:[@{@"visible":@YES,@"label":@YES,@"opacity":@1} mutableCopy]];
    UITapGestureRecognizer *fallback=[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(toggleStandardController:)];
    fallback.numberOfTouchesRequired=3;fallback.numberOfTapsRequired=2;
    fallback.cancelsTouchesInView=YES;fallback.delaysTouchesBegan=NO;fallback.delaysTouchesEnded=NO;
    [self addGestureRecognizer:fallback];
    _context=fnv_pad_context();_inputEpoch=fnv_pad_input_epoch();
#ifndef FNV_PROBE
    fnv_pad_stick_camera(![_settings[@"cameraDirect"] boolValue]);
    _motion=[CMMotionManager new];_motion.deviceMotionUpdateInterval=1.0/120.0;
    [self updateMotion];
#endif
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(willResign:) name:UIApplicationWillResignActiveNotification object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(didResume:) name:UIApplicationDidBecomeActiveNotification object:nil];
    FNVTouchDisplayProxy *proxy=[FNVTouchDisplayProxy new];proxy.owner=self;
    _displayLink=[CADisplayLink displayLinkWithTarget:proxy selector:@selector(step:)];_displayLink.preferredFramesPerSecond=60;[_displayLink addToRunLoop:NSRunLoop.mainRunLoop forMode:NSRunLoopCommonModes];
    [self resetTouches];
    return self;
}
- (void)dealloc {[_displayLink invalidate];[_motion stopDeviceMotionUpdates];[NSNotificationCenter.defaultCenter removeObserver:self];}
// Reserve our three-finger shortcut instead of the system text-editing chord.
- (UIEditingInteractionConfiguration)editingInteractionConfiguration {return UIEditingInteractionConfigurationNone;}
- (UIColor *)amber:(CGFloat)alpha{return[UIColor colorWithRed:1 green:.73 blue:.25 alpha:alpha];}
- (BOOL)isGame {return !_standardFallback&&(_editing?!_editingPip:_context==FNVContextGameplay);}
- (NSMutableArray *)buttonSettings {return _standardFallback?_fallbackButtons:_settings[[self isGame]?@"gameButtons":@"pipButtons"];}
- (NSArray<NSString *> *)buttonNames {
    if(_standardFallback)return @[@"LT",@"LB",@"Back",@"Start",@"RB",@"RT",@"↑",@"↓",@"←",@"→",@"A",@"B",@"X",@"Y",@"L3",@"R3"];
    if([self isGame])return @[@"Fire",_editing?@"Aim / Gyro":(_aimed?@"Exit ADS":([_settings[@"gyro"] boolValue]?@"Gyro ON":@"Gyro OFF")),@"Interact",@"Jump",@"VATS",@"Pip-Boy"];
    if(_context==FNVContextVATS&&!_editing)return @[@"Queue",@"Target",@"Confirm",@"Cancel",@"Special X",@"Special Y",@"Body ↑",@"Body ↓",@"Body ←",@"Body →"];
    if(_context==FNVContextPipMap&&!_editing)return @[@"Next section",@"Prev section",@"Select / Travel",@"Back / Close",@"Place marker",@"Action Y",@"Zoom +",@"Zoom −",@"Previous tab",@"Next tab"];
    if(_context==FNVContextLockpick&&!_editing)return @[@"",@"",@"",@"Exit",@"Force lock",@"",@"",@"",@"",@""];
    if(_context!=FNVContextPipBoy&&!_editing)return @[@"RT / Next",@"LT / Previous",@"Confirm",@"Back",@"X action",@"Y action",@"Up",@"Down",@"Left",@"Right"];
    return @[@"Next section",@"Prev section",@"Use / Confirm",@"Back / Close",@"Action X",@"Action Y",@"Up",@"Down",@"Left",@"Right"];
}
- (BOOL)buttonAvailable:(NSInteger)index {
    if(_standardFallback)return index>=0&&index<FNVTouchFallbackCount;
    if(_editing||[self isGame])return YES;
    if(_context==FNVContextLockpick)return index==3||index==4;
    if(_context==FNVContextHacking||_context==FNVContextComputer||_context==FNVContextDialogue)return index==2||index==3||index>=6;
    if(fnv_context_is_pip(_context)||_context==FNVContextVATS)return YES;
    return YES;
}
- (FNVTouchRect)policySafe{return(FNVTouchRect){_safe.origin.x,_safe.origin.y,_safe.size.width,_safe.size.height};}
- (CGRect)region:(NSString *)key {
    NSDictionary *r=_settings[key];FNVTouchRect placed=FNVTouchRegion([self policySafe],FNVNumber(r,@"x",0,0,1),FNVNumber(r,@"y",0,0,1),FNVNumber(r,@"w",.4,.08,1),FNVNumber(r,@"h",.7,.08,1));
    return CGRectMake(placed.x,placed.y,placed.w,placed.h);
}
- (void)layoutSubviews {
    [super layoutSubviews];
    UIEdgeInsets insets=self.safeAreaInsets;CGSize size=self.bounds.size;
    if(_lastSize.width&&(!CGSizeEqualToSize(size,_lastSize)||!UIEdgeInsetsEqualToEdgeInsets(insets,_lastInsets)))[self resetTouches];
    _lastSize=size;_lastInsets=insets;
    _safe=UIEdgeInsetsInsetRect(self.bounds,UIEdgeInsetsMake(insets.top+8,insets.left+8,insets.bottom+8,insets.right+8));
    if(_safe.size.width<44||_safe.size.height<44)return;
    NSArray *buttons=[self buttonSettings];_count=MIN((NSInteger)buttons.count,FNVTouchFallbackCount);
#ifdef FNV_PROBE
    _count=0;
#endif
    for(NSInteger i=0;i<_count;i++){
        NSDictionary *b=buttons[i];FNVTouchRect r=_standardFallback?FNVTouchFallbackFrame([self policySafe],(unsigned)i):FNVTouchPlace([self policySafe],FNVNumber(b,@"x",.8,0,1),FNVNumber(b,@"y",.6,0,1),FNVNumber(b,@"size",54,20,140));
        _frames[i]=CGRectMake(r.x,r.y,r.w,r.h);
    }
    _moveRegion=CGRectIntersection(_safe,[self region:[self isGame]?@"move":@"pipMove"]);_lookRegion=CGRectIntersection(_safe,[self region:[self isGame]?@"look":@"pipLook"]);
    if(_standardFallback){FNVTouchRect left=FNVTouchFallbackRegion([self policySafe],0),right=FNVTouchFallbackRegion([self policySafe],1);_moveRegion=CGRectMake(left.x,left.y,left.w,left.h);_lookRegion=CGRectMake(right.x,right.y,right.w,right.h);}
    _radialRadius=MIN(FNVNumber(_settings,@"radialSize",250,200,380)/2,MIN(_safe.size.width,_safe.size.height)/2-4);
    _radialOrigin=CGPointMake(FNVTouchClamp(_safe.origin.x+FNVNumber(_settings,@"radialX",.72,0,1)*_safe.size.width,CGRectGetMinX(_safe)+_radialRadius,CGRectGetMaxX(_safe)-_radialRadius),FNVTouchClamp(_safe.origin.y+FNVNumber(_settings,@"radialY",.43,0,1)*_safe.size.height,CGRectGetMinY(_safe)+_radialRadius,CGRectGetMaxY(_safe)-_radialRadius));
    if(_editing){
        CGFloat width=MIN(340,_safe.size.width*.46);
        _editorPanel.frame=CGRectMake(_safe.origin.x,_safe.origin.y,width,_safe.size.height);
        _editorReturn.frame=CGRectMake(_safe.origin.x,_safe.origin.y,100,44);
    }
    [self setNeedsDisplay];
}
- (void)text:(NSString *)text rect:(CGRect)rect size:(CGFloat)size color:(UIColor *)color {
    NSMutableParagraphStyle *style=[NSMutableParagraphStyle new];style.alignment=NSTextAlignmentCenter;
    [text drawInRect:rect withAttributes:@{NSFontAttributeName:[UIFont systemFontOfSize:size weight:UIFontWeightMedium],NSForegroundColorAttributeName:color,NSParagraphStyleAttributeName:style}];
}
- (void)drawRect:(CGRect)rect {
    CGContextRef cg=UIGraphicsGetCurrentContext();if(!cg)return;
    NSArray *settings=[self buttonSettings],*names=[self buttonNames];
    for(NSInteger i=0;i<_count;i++){
        NSDictionary *b=settings[i];if((![b[@"visible"] boolValue]&&!_editing)||![self buttonAvailable:i])continue;
        CGFloat opacity=(_standardFallback?.82:FNVNumber(_settings,@"opacity",.72,.15,1))*FNVNumber(b,@"opacity",1,.1,1)*(_overlay?.28:1);
        BOOL selected=(_editing&&_selected==i)||([self isGame]&&i==1&&(_aimed||[_settings[@"gyro"] boolValue]));
        UIColor *fill=selected?[self amber:.18*opacity]:[UIColor colorWithWhite:0 alpha:.13*opacity];
        CGContextSetFillColorWithColor(cg,fill.CGColor);CGContextFillEllipseInRect(cg,_frames[i]);
        CGContextSetStrokeColorWithColor(cg,[self amber:opacity].CGColor);CGContextSetLineWidth(cg,selected?2:1);CGContextStrokeEllipseInRect(cg,_frames[i]);
        if(_editing&&![b[@"visible"] boolValue])[self text:@"Hidden" rect:CGRectInset(_frames[i],2,10) size:10 color:[self amber:1]];
        else {
            NSString *symbol=[self isGame]?@[@"bolt.fill",@"scope",@"hand.raised.fill",@"figure.run",@"figure.stand",@"rectangle.on.rectangle"][i]:nil;
            UIImage *icon=symbol?[[UIImage systemImageNamed:symbol] imageWithTintColor:[self amber:opacity] renderingMode:UIImageRenderingModeAlwaysOriginal]:nil;
            BOOL label=[b[@"label"] boolValue];CGFloat iconSize=MIN(27,_frames[i].size.width*.38);
            if(icon)[icon drawInRect:CGRectMake(CGRectGetMidX(_frames[i])-iconSize/2,CGRectGetMidY(_frames[i])-iconSize/2-(label?6:0),iconSize,iconSize)];
            if(label||!icon){
                CGFloat labelSize=MIN(12,_frames[i].size.width/4);
                for(NSString *word in [names[i] componentsSeparatedByCharactersInSet:NSCharacterSet.whitespaceCharacterSet]){
                    CGFloat width=[word sizeWithAttributes:@{NSFontAttributeName:[UIFont systemFontOfSize:labelSize weight:UIFontWeightMedium]}].width;
                    if(width>_frames[i].size.width-6)labelSize*=(_frames[i].size.width-6)/width;
                }
                [self text:names[i] rect:CGRectMake(_frames[i].origin.x+2,CGRectGetMidY(_frames[i])+(icon?8:-8),_frames[i].size.width-4,30) size:labelSize color:[self amber:opacity]];
            }
        }
    }
    if(_standardFallback){
        [self text:@"Standard XInput · Three-finger double-tap to return" rect:CGRectMake(_safe.origin.x+70,_safe.origin.y+_safe.size.height*.19,_safe.size.width-140,25) size:12 color:[self amber:.95]];
        for(unsigned right=0;right<2;right++){CGRect region=right?_lookRegion:_moveRegion;CGPoint origin=CGPointMake(CGRectGetMidX(region),CGRectGetMidY(region));BOOL held=NO;
            for(FNVFinger *finger in _fingers.allValues)if(finger.state.owner==(right?FNVTouchMenuOwner:FNVTouchMoveOwner)){held=YES;break;}
            [self text:right?@"Right stick":@"Left stick" rect:CGRectMake(region.origin.x,region.origin.y,region.size.width,22) size:11 color:[self amber:.8]];
            if(!held){double radius=FNVTouchFallbackRadius([self policySafe]);CGContextSetStrokeColorWithColor(cg,[self amber:.4].CGColor);CGContextSetLineWidth(cg,1);CGContextStrokeEllipseInRect(cg,CGRectMake(origin.x-radius,origin.y-radius,radius*2,radius*2));}
        }
    }
    for(FNVFinger *finger in _fingers.allValues)if(finger.state.owner==FNVTouchMoveOwner||(finger.state.owner==FNVTouchMenuOwner&&(_standardFallback||FNVTouchRightStickContext(_context)))){
        double radius=FNVNumber(_settings,@"radius",54,20,120),dx=finger.state.lastX-finger.origin.x;
        if(_standardFallback)radius=FNVTouchFallbackRadius([self policySafe]);
        if(!_standardFallback&&_context==FNVContextPipMap&&finger.state.owner==FNVTouchMoveOwner)dx=0;
        FNVTouchVector v=FNVTouchMove(dx,finger.state.lastY-finger.origin.y,radius,_standardFallback?.1:FNVNumber(_settings,@"moveDeadzone",.1,0,.5),_standardFallback?1:FNVNumber(_settings,@"moveResponse",1,.4,3));
        double opacity=FNVNumber(_settings,@"opacity",.72,.15,1);
        CGContextSetStrokeColorWithColor(cg,[self amber:.75*opacity].CGColor);CGContextSetLineWidth(cg,1);
        CGContextStrokeEllipseInRect(cg,CGRectMake(finger.origin.x-radius,finger.origin.y-radius,radius*2,radius*2));
        CGContextSetFillColorWithColor(cg,[self amber:.38*opacity].CGColor);CGContextFillEllipseInRect(cg,CGRectMake(finger.origin.x+v.x*radius-17,finger.origin.y-v.y*radius-17,34,34));
    }
    if(_editing){
        CGContextSetLineWidth(cg,1);CGFloat dash[]={5,4};CGContextSetLineDash(cg,0,dash,2);CGContextSetStrokeColorWithColor(cg,[self amber:.9].CGColor);
        CGContextStrokeRect(cg,_moveRegion);CGContextStrokeRect(cg,_lookRegion);CGContextSetLineDash(cg,0,NULL,0);
        [self text:@"Floating movement" rect:CGRectMake(_moveRegion.origin.x,_moveRegion.origin.y,_moveRegion.size.width,22) size:12 color:[self amber:1]];
        [self text:_editingPip?@"Map / preview stick":@"Swipe look" rect:CGRectMake(_lookRegion.origin.x,_lookRegion.origin.y,_lookRegion.size.width,22) size:12 color:[self amber:1]];
        if(_editorPreview)[self text:@"Drag the selected control or region. Tap Settings to continue." rect:CGRectMake(_safe.origin.x+110,_safe.origin.y+8,_safe.size.width-120,40) size:12 color:[self amber:1]];
    }
    if(_overlay==1||_overlay==2)[self drawRadial:cg];
    if(_overlay==3)[self drawMore:cg];
    if(_calibrateUntil>CACurrentMediaTime())[self text:@"Hold still — calibrating gyro" rect:CGRectMake(_safe.origin.x,_safe.origin.y+45,_safe.size.width,24) size:14 color:[self amber:1]];
    if(_context==FNVContextLockpick&&!_editing&&!_standardFallback)[self text:@"Left thumb: pick angle     Right swipe: turn lock" rect:CGRectMake(_safe.origin.x+80,_safe.origin.y+10,_safe.size.width-160,30) size:12 color:[self amber:.9]];
    if(_context==FNVContextPipMap&&!_editing&&!_standardFallback)[self text:@"Left thumb: zoom     Right thumb: move map     Select: travel" rect:CGRectMake(_safe.origin.x+80,_safe.origin.y+10,_safe.size.width-160,30) size:12 color:[self amber:.9]];
}
- (NSArray *)radialNames {
    if(_overlay==2)return @[@"Hotkey 1 ↖",@"Hotkey 3 ↗",@"Hotkey 4 ←",@"Hotkey 5 →",@"Hotkey 6 ↙",@"Hotkey 7 ↓",@"Hotkey 8 ↘"];
    NSMutableArray *ordered=[NSMutableArray new];NSArray *order=_settings[@"radialOrder"];
    for(NSNumber *action in order)[ordered addObject:[self utilityName:action.unsignedIntegerValue]];
    return ordered;
}
- (NSString *)utilityName:(NSUInteger)action {
    if(action==FNVUtilityGyro)return [_settings[@"gyro"] boolValue]?@"Gyro ON":@"Gyro OFF";
    return action<FNVUtilityCount?FNVUtilityNames()[action]:@"";
}
- (void)drawRadial:(CGContextRef)cg {
    double radius=_radialRadius,inner=radius*.24;NSArray *names=[self radialNames];
    CGContextSetFillColorWithColor(cg,[UIColor colorWithWhite:.03 alpha:.83].CGColor);CGContextFillEllipseInRect(cg,CGRectMake(_radialOrigin.x-radius,_radialOrigin.y-radius,2*radius,2*radius));
    CGContextSetLineWidth(cg,1);CGContextSetStrokeColorWithColor(cg,[self amber:.9].CGColor);
    CGContextStrokeEllipseInRect(cg,CGRectMake(_radialOrigin.x-radius,_radialOrigin.y-radius,2*radius,2*radius));
    CGContextStrokeEllipseInRect(cg,CGRectMake(_radialOrigin.x-inner,_radialOrigin.y-inner,2*inner,2*inner));
    for(unsigned i=0;i<7;i++){
        double angle=(double)i/7*2*M_PI-M_PI/2,edge=angle-M_PI/7;
        CGContextMoveToPoint(cg,_radialOrigin.x+cos(edge)*inner,_radialOrigin.y+sin(edge)*inner);CGContextAddLineToPoint(cg,_radialOrigin.x+cos(edge)*radius,_radialOrigin.y+sin(edge)*radius);CGContextStrokePath(cg);
        CGPoint center=CGPointMake(_radialOrigin.x+cos(angle)*radius*.65,_radialOrigin.y+sin(angle)*radius*.65);
        if(_radialArmed&&_radialSelection==(NSInteger)i){
            CGContextSetFillColorWithColor(cg,[self amber:.18].CGColor);CGContextMoveToPoint(cg,_radialOrigin.x,_radialOrigin.y);CGContextAddArc(cg,_radialOrigin.x,_radialOrigin.y,radius,angle-M_PI/7,angle+M_PI/7,0);CGContextClosePath(cg);CGContextFillPath(cg);
        }
        CGFloat labelWidth=radius*.66;[self text:names[i] rect:CGRectMake(center.x-labelWidth/2,center.y-14,labelWidth,34) size:FNVTouchClamp(radius*.09,10,12) color:[self amber:1]];
    }
    [self text:@"Cancel" rect:CGRectMake(_radialOrigin.x-inner,_radialOrigin.y-7,inner*2,20) size:10 color:[self amber:.8]];
}
- (CGRect)moreFrame {
    CGFloat w=MIN(360,_safe.size.width-16),h=MIN(240,_safe.size.height-16);
    return CGRectMake(CGRectGetMaxX(_safe)-w-4,CGRectGetMidY(_safe)-h/2,w,h);
}
- (NSArray *)moreNames {NSMutableArray *names=[NSMutableArray new];for(NSNumber *action in _settings[@"moreOrder"])[names addObject:[self utilityName:action.unsignedIntegerValue]];[names addObject:@"Back"];return names;}
- (CGRect)moreItem:(NSInteger)item {
    CGRect r=[self moreFrame];CGFloat row=(r.size.height-16)/4,col=(r.size.width-16)/2;
    return item==6?CGRectMake(r.origin.x+8,r.origin.y+8+3*row,r.size.width-16,row):CGRectMake(r.origin.x+8+(item%2)*col,r.origin.y+8+(item/2)*row,col,row);
}
- (void)drawMore:(CGContextRef)cg {
    CGRect r=[self moreFrame];CGContextSetFillColorWithColor(cg,[UIColor colorWithWhite:.03 alpha:.91].CGColor);CGContextFillRect(cg,r);CGContextSetStrokeColorWithColor(cg,[self amber:.9].CGColor);CGContextStrokeRect(cg,r);
    NSArray *names=[self moreNames];for(NSInteger i=0;i<(NSInteger)names.count;i++){CGRect row=[self moreItem:i];CGContextStrokeRect(cg,row);[self text:names[i] rect:CGRectInset(row,4,8) size:13 color:[self amber:1]];}
}
- (NSInteger)hitButton:(CGPoint)p {
    FNVTouchRect frames[FNVTouchFallbackCount];int visible[FNVTouchFallbackCount];NSArray *buttons=[self buttonSettings];
    for(NSInteger i=0;i<_count;i++){CGRect r=_frames[i];frames[i]=(FNVTouchRect){r.origin.x,r.origin.y,r.size.width,r.size.height};visible[i]=(_editing||[buttons[i][@"visible"] boolValue])&&[self buttonAvailable:i];}
    return FNVTouchHit(frames,visible,(size_t)_count,p.x,p.y);
}
- (BOOL)insideFire:(CGPoint)p {
    return[self isGame]&&[self hitButton:p]==0;
}
- (void)addCode:(unsigned)code state:(FNVPadState *)s {
    fnv_pad_apply_binding(s,code);
}
- (void)pulseCode:(unsigned)code duration:(double)duration {
    [_pulses addObject:@{@"code":@(code),@"until":@(CACurrentMediaTime()+duration)}];
}
- (void)pulseAction:(unsigned)action duration:(double)duration {[self pulseCode:fnv_pad_binding(action) duration:duration];}
- (void)pulseMask:(unsigned)mask duration:(double)duration {[_pulses addObject:@{@"mask":@(mask),@"until":@(CACurrentMediaTime()+duration)}];}
- (void)pulseAxis:(NSString *)axis value:(double)value {[_pulses addObject:@{@"axis":axis,@"value":@(value),@"until":@(CACurrentMediaTime()+.12)}];}
- (void)localReset {
    [_fingers removeAllObjects];[_pulses removeAllObjects];_aimed=NO;_lookDX=_lookDY=_smoothX=_smoothY=0;_probeLook=(FNVLook){0};_relativeCarry=(FNVTouchVector){0};_recoveryStarted=0;
}
- (void)resetTouches {
    [self localReset];_overlay=0;_radialArmed=NO;
    fnv_pad_reset();_inputEpoch=fnv_pad_input_epoch();if(self.movementChanged)self.movementChanged(0,0);[self setNeedsDisplay];
}
- (void)toggleStandardController:(UITapGestureRecognizer *)recognizer {
    if(recognizer&&recognizer.state!=UIGestureRecognizerStateRecognized)return;
    if(_editing)[self closeEditorApply:NO];
    [self resetTouches];_standardFallback=!_standardFallback;
    fnv_pad_stick_camera(_standardFallback||![_settings[@"cameraDirect"] boolValue]);_inputEpoch=fnv_pad_input_epoch();
    fprintf(stderr,"[touch-overlay] standard_xinput=%d context=%u\n",_standardFallback,_context);
    [self updateMotion];[self setNeedsLayout];[self layoutIfNeeded];[self setNeedsDisplay];
}
- (void)willResign:(NSNotification *)notification {_suspended=YES;[self resetTouches];[_motion stopDeviceMotionUpdates];_gyroRateX=_gyroRateY=0;_gyroSampleAt=0;}
- (void)didResume:(NSNotification *)notification {_suspended=NO;_lastFrame=0;_gyroRateX=_gyroRateY=0;_gyroSampleAt=0;[self resetTouches];}
- (void)openOverlay:(NSInteger)kind origin:(CGPoint)point {
    [self resetTouches];_overlay=kind;_radialArmed=NO;_radialSelection=-1;_radialStart=point;[self setNeedsDisplay];
}
- (void)persistSettings {if(!_editing)[NSUserDefaults.standardUserDefaults setObject:_settings forKey:FNVTouchSettingsKey];}
- (void)toggleGyro {
    _settings[@"gyro"]=@(![_settings[@"gyro"] boolValue]);[self persistSettings];
    // Never reuse an old motion sample, or recalibrate against a moving phone
    // on every tap. Explicit Calibrate / Recenter remains available in settings.
    _gyroRateX=_gyroRateY=0;_gyroSampleAt=0;[self updateMotion];[self setNeedsDisplay];
}
- (void)recognizeAimHold:(FNVFinger *)finger at:(double)now {
    FNVTouchContact state=finger.state;
    if(state.owner!=FNVTouchAimOwner||state.consumed)return;
    if(FNVTouchAimHold(&state,now,FNVNumber(_settings,@"aimDelay",.32,.2,.8),[self hitButton:CGPointMake(state.lastX,state.lastY)]==1))_aimed=YES;
    finger.state=state;
}
- (void)calibrate {
    _biasSumX=_biasSumY=0;_biasSamples=0;_calibrateUntil=CACurrentMediaTime()+.5;_lookDX=_lookDY=0;[self setNeedsDisplay];
}
- (void)updateMotion {
#ifndef FNV_PROBE
    BOOL wanted=!_suspended&&!_standardFallback&&([_settings[@"gyro"] boolValue]||_calibrateUntil>CACurrentMediaTime());
    if(!wanted){if(_motion.deviceMotionActive)[_motion stopDeviceMotionUpdates];_gyroRateX=_gyroRateY=0;return;}
    if(_motion.deviceMotionActive||!_motion.deviceMotionAvailable)return;
    __weak FNVGameplayTouchView *weakSelf=self;
    [_motion startDeviceMotionUpdatesUsingReferenceFrame:CMAttitudeReferenceFrameXArbitraryZVertical toQueue:NSOperationQueue.mainQueue withHandler:^(CMDeviceMotion *sample,NSError *error){
        FNVGameplayTouchView *view=weakSelf;if(!view||error||!sample)return;
        UIInterfaceOrientation orientation=view.window.windowScene.interfaceOrientation;double sign=orientation==UIInterfaceOrientationLandscapeRight?-1:1;
        view->_gyroRateX=-sample.rotationRate.x*sign;view->_gyroRateY=sample.rotationRate.y*sign;view->_gyroSampleAt=CACurrentMediaTime();
    }];
#endif
}
- (void)radialAction:(NSInteger)sector {
    if(sector<0||sector>=7)return;
    if(_overlay==2){static const unsigned masks[]={5,9,4,8,6,2,10};[self resetTouches];[self pulseMask:masks[sector] duration:.15];return;}
    NSArray *order=_settings[@"radialOrder"];if(sector>=(NSInteger)order.count)return;
    [self performUtility:[order[sector] unsignedIntegerValue]];
}
- (void)performUtility:(NSUInteger)action {
    [self resetTouches];
    switch(action){
        case FNVUtilityReload:[self pulseAction:7 duration:.12];break;
        case FNVUtilityCrouch:[self pulseAction:8 duration:.12];break;
        case FNVUtilityWeapons:_overlay=2;_radialArmed=NO;_radialSelection=-1;break;
        case FNVUtilityAmmo:[self pulseAction:18 duration:.15];break;
        case FNVUtilityView:[self pulseAction:13 duration:.12];break;
        case FNVUtilityGyro:[self toggleGyro];break;
        case FNVUtilityMore:_overlay=3;break;
        case FNVUtilityCustomize:[self openEditor];break;
        case FNVUtilityHolster:[self pulseAction:7 duration:.85];break;
        case FNVUtilityLight:[self pulseAction:14 duration:1.0];break;
        case FNVUtilityGrab:[self pulseAction:27 duration:.65];break;
        case FNVUtilityWait:[self pulseAction:15 duration:.12];break;
        case FNVUtilityPause:[self pulseCode:6 duration:.12];break;
    }
}
- (void)moreAction:(NSInteger)item {
    NSArray *order=_settings[@"moreOrder"];
    if(item>=0&&item<(NSInteger)order.count)[self performUtility:[order[item] unsignedIntegerValue]];
    else if(item==(NSInteger)order.count){[self resetTouches];_overlay=1;_radialArmed=NO;_radialSelection=-1;}
}
- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    double now=CACurrentMediaTime();
    unsigned active=0;for(UITouch *item in event.allTouches)if(item.phase!=UITouchPhaseEnded&&item.phase!=UITouchPhaseCancelled)active++;
    if(!_editing&&FNVTouchRecoveryGesture(active)&&!_recoveryStarted)_recoveryStarted=now;
    for(UITouch *touch in touches){
        CGPoint p=[touch locationInView:self];FNVFinger *finger=[FNVFinger new];NSInteger hit=[self hitButton:p];int owner=FNVTouchNone;finger.action=hit;finger.origin=p;
        if(_editing){
            if(!_editorPreview)continue;owner=FNVTouchEditOwner;finger.origin=p;
        }else if(_suspended||fnv_pad_physical_active())continue;
        else if(_overlay){owner=FNVTouchOverlayOwner;
            if(_overlay==3){finger.action=-1;for(NSInteger i=0;i<7;i++)if(CGRectContainsPoint([self moreItem:i],p)){finger.action=i;break;}}
            else {_radialArmed=YES;_radialSelection=FNVTouchSector(p.x-_radialOrigin.x,p.y-_radialOrigin.y,_radialRadius*.24,_radialRadius,7);}
        }else if(_standardFallback){
            if(hit>=0)owner=FNVTouchFallbackOwner;
            else if(CGRectContainsPoint(_moveRegion,p)||CGRectContainsPoint(_lookRegion,p)){int wanted=CGRectContainsPoint(_moveRegion,p)?FNVTouchMoveOwner:FNVTouchMenuOwner;BOOL held=NO;for(FNVFinger *old in _fingers.allValues)if(old.state.owner==wanted)held=YES;if(!held)owner=wanted;}
        }else if([self isGame]){
            if(hit==0)owner=FNVTouchFireOwner;
            else if(hit==1){BOOL held=NO;for(FNVFinger *old in _fingers.allValues)if(old.state.owner==FNVTouchAimOwner)held=YES;if(!held){owner=FNVTouchAimOwner;finger.aimWasOn=_aimed;}}
            else if(hit==5)owner=FNVTouchUtilityOwner;
            else if(hit>=0)owner=FNVTouchActionOwner;
            else if(CGRectContainsPoint(_moveRegion,p)){BOOL hasMove=NO;for(FNVFinger *old in _fingers.allValues)if(old.state.owner==FNVTouchMoveOwner)hasMove=YES;if(!hasMove)owner=FNVTouchMoveOwner;}
            else if(CGRectContainsPoint(_lookRegion,p))owner=FNVTouchLookOwner;
        }else{
            if(hit>=0){owner=FNVTouchNone;
                if(_context==FNVContextPipMap&&hit>=2)[self pulseMask:FNVTouchMapButton((unsigned)hit) duration:.10];
                else if(_context==FNVContextVATS&&hit==1)[self pulseAxis:@"rx" value:.9];
                else if(_context==FNVContextVATS&&hit>=6)[self pulseAxis:hit<8?@"ly":@"lx" value:(hit==6||hit==9)?.9:-.9];
                else if(hit<2)[self pulseCode:hit==0?17:16 duration:.10];else[self pulseMask:FNVMenuMasks[hit] duration:.10];
            }
            else if(CGRectContainsPoint(_moveRegion,p)){BOOL hasMove=NO;for(FNVFinger *old in _fingers.allValues)if(old.state.owner==FNVTouchMoveOwner)hasMove=YES;if(!hasMove)owner=FNVTouchMoveOwner;}
            else if(CGRectContainsPoint(_lookRegion,p)){BOOL hasRight=NO;for(FNVFinger *old in _fingers.allValues)if(old.state.owner==FNVTouchMenuOwner)hasRight=YES;if(!hasRight)owner=FNVTouchMenuOwner;}
        }
        finger.state=FNVTouchBegin(owner,p.x,p.y,now);_fingers[[NSValue valueWithNonretainedObject:touch]]=finger;
#ifdef FNV_PROBE
        if(owner==FNVTouchLookOwner)_probeLook=(FNVLook){p.x,p.y,0,0};
#endif
    }
    [self setNeedsDisplay];
}
- (void)moveFinger:(FNVFinger *)finger to:(CGPoint)p {
    FNVTouchContact state=finger.state;double dx=p.x-state.lastX,dy=p.y-state.lastY;
    if(state.owner==FNVTouchFireOwner||state.owner==FNVTouchAimOwner){
        FNVTouchFireSlide(&state,[self insideFire:p]);
        // Sliding Aim onto Fire is an explicit aim-and-shoot gesture, even
        // before the hold timer expires. It must never become a gyro tap.
        if(state.owner==FNVTouchAimOwner&&state.fire){_aimed=YES;state.consumed=1;}
        if(state.owner==FNVTouchFireOwner||state.fire){double gain=FNVNumber(_settings,@"fireGain",1,.2,3);_lookDX+=dx*gain;_lookDY+=dy*gain;}
    }else if(state.owner==FNVTouchLookOwner||(state.owner==FNVTouchMenuOwner&&!_standardFallback&&!FNVTouchRightStickContext(_context))){
#ifdef FNV_PROBE
        FNVMouseDelta d=FNVLookTo(&_probeLook,p.x,p.y,self.lookGain);input_mouse_move(d.dx,d.dy);
#else
        _lookDX+=dx;_lookDY+=dy;
#endif
    }else if(state.owner==FNVTouchOverlayOwner&&(_overlay==1||_overlay==2)){
        if(hypot(p.x-_radialStart.x,p.y-_radialStart.y)>8)_radialArmed=YES;
        _radialSelection=_radialArmed?FNVTouchSector(p.x-_radialOrigin.x,p.y-_radialOrigin.y,_radialRadius*.24,_radialRadius,7):-1;
    }else if(state.owner==FNVTouchEditOwner){[self dragSelectionBy:CGPointMake(dx,dy)];}
    state.lastX=p.x;state.lastY=p.y;finger.state=state;
}
- (void)touchesMoved:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    for(UITouch *touch in touches){FNVFinger *finger=_fingers[[NSValue valueWithNonretainedObject:touch]];if(finger)[self moveFinger:finger to:[touch locationInView:self]];}[self setNeedsDisplay];
}
- (void)finishTouches:(NSSet<UITouch *> *)touches cancelled:(BOOL)cancelled {
    if(_inputEpoch!=fnv_pad_input_epoch()||_context!=fnv_pad_context()||fnv_pad_physical_active()){[self resetTouches];return;}
    for(UITouch *touch in touches){NSValue *key=[NSValue valueWithNonretainedObject:touch];FNVFinger *finger=_fingers[key];if(!finger)continue;
        if(!cancelled)[self moveFinger:finger to:[touch locationInView:self]];
        double now=CACurrentMediaTime();
        if(!cancelled&&finger.state.owner==FNVTouchAimOwner)[self recognizeAimHold:finger at:now];
        FNVTouchContact state=finger.state;
        if(!cancelled&&FNVTouchAimTap(&state,now,FNVNumber(_settings,@"aimDelay",.32,.2,.8),[self hitButton:CGPointMake(state.lastX,state.lastY)]==1)){
            if(finger.aimWasOn)_aimed=NO;else[self toggleGyro];
        }
        if(!cancelled&&state.owner==FNVTouchUtilityOwner&&FNVTouchUtilityTap(&state,CACurrentMediaTime(),FNVNumber(_settings,@"hold",.38,.22,.8)))[self pulseAction:14 duration:.10];
        if(!cancelled&&state.owner==FNVTouchOverlayOwner){
            if(_overlay==3){if(finger.action>=0&&CGRectContainsPoint([self moreItem:finger.action],[touch locationInView:self]))[self moreAction:finger.action];else[self resetTouches];}
            else if(_overlay==1||_overlay==2){NSInteger selected=_radialArmed?_radialSelection:-1;if(selected>=0)[self radialAction:selected];else[self resetTouches];}
        }
        [_fingers removeObjectForKey:key];
    }
    _recoveryStarted=0;[self setNeedsDisplay];
}
- (void)touchesEnded:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {[self finishTouches:touches cancelled:NO];}
- (void)touchesCancelled:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {[self resetTouches];}
- (void)readPhysicalController {
#ifndef FNV_PROBE
    GCExtendedGamepad *pad=nil;for(GCController *controller in GCController.controllers)if(controller.extendedGamepad){pad=controller.extendedGamepad;break;}
    FNVPadState state={0};if(pad){
        state.lx=(int16_t)lround(pad.leftThumbstick.xAxis.value*32767);state.ly=(int16_t)lround(pad.leftThumbstick.yAxis.value*32767);state.rx=(int16_t)lround(pad.rightThumbstick.xAxis.value*32767);state.ry=(int16_t)lround(pad.rightThumbstick.yAxis.value*32767);
        state.left_trigger=(uint8_t)lround(pad.leftTrigger.value*255);state.right_trigger=(uint8_t)lround(pad.rightTrigger.value*255);
        if(pad.dpad.up.isPressed)state.buttons|=1;if(pad.dpad.down.isPressed)state.buttons|=2;if(pad.dpad.left.isPressed)state.buttons|=4;if(pad.dpad.right.isPressed)state.buttons|=8;
        if(pad.buttonA.isPressed)state.buttons|=0x1000;if(pad.buttonB.isPressed)state.buttons|=0x2000;if(pad.buttonX.isPressed)state.buttons|=0x4000;if(pad.buttonY.isPressed)state.buttons|=0x8000;
        if(pad.leftShoulder.isPressed)state.buttons|=0x100;if(pad.rightShoulder.isPressed)state.buttons|=0x200;
        if(pad.buttonMenu.isPressed)state.buttons|=0x10;if(pad.buttonOptions.isPressed)state.buttons|=0x20;
        if(pad.leftThumbstickButton.isPressed)state.buttons|=0x40;if(pad.rightThumbstickButton.isPressed)state.buttons|=0x80;
    }
    fnv_pad_physical_state(&state,pad!=nil);
#endif
}
- (void)tick:(CADisplayLink *)link {
    // The app opens fnv.log after constructing this view. Log on the first
    // display tick so the effective migrated camera settings reach that file.
    if(!_reportedCamera){_reportedCamera=YES;fprintf(stderr,"[touch-camera] direct=%d swipe=%.2f,%.2f gyro=%.2f,%.2f multiplier=%.2f\n",[_settings[@"cameraDirect"] boolValue],[_settings[@"swipeX"] doubleValue],[_settings[@"swipeY"] doubleValue],[_settings[@"gyroX"] doubleValue],[_settings[@"gyroY"] doubleValue],[_settings[@"lookMultiplier"] doubleValue]);}
    double now=CACurrentMediaTime(),dt=_lastFrame?now-_lastFrame:1.0/60;_lastFrame=now;if(dt>.15){_lookDX=_lookDY=_smoothX=_smoothY=0;dt=1.0/60;}
    UIInterfaceOrientation orientation=self.window.windowScene.interfaceOrientation;
    if(UIInterfaceOrientationIsLandscape(orientation)){
        if(_lastOrientation!=UIInterfaceOrientationUnknown&&orientation!=_lastOrientation){[self resetTouches];_gyroRateX=_gyroRateY=0;_gyroSampleAt=0;if([_settings[@"gyro"] boolValue])[self calibrate];}
        _lastOrientation=orientation;
    }
    [self updateMotion];
    [self readPhysicalController];fnv_pad_stick_camera(_standardFallback||![_settings[@"cameraDirect"] boolValue]);uint32_t epoch=fnv_pad_input_epoch();FNVInputContext context=fnv_pad_context();
    if(epoch!=_inputEpoch||context!=_context){[self localReset];_inputEpoch=epoch;_context=context;_overlay=0;[self setNeedsLayout];}
    if(_calibrateUntil){if(now<_calibrateUntil){_biasSumX+=_gyroRateX;_biasSumY+=_gyroRateY;_biasSamples++;}else{if(_biasSamples){_biasX=_biasSumX/_biasSamples;_biasY=_biasSumY/_biasSamples;}_calibrateUntil=0;}}
    if(_recoveryStarted&&now-_recoveryStarted>1.2){_recoveryStarted=0;[self openEditor];}
    if(_suspended||_editing||fnv_pad_physical_active()){FNVPadState zero={0};fnv_pad_touch_state(&zero);return;}
    for(FNVFinger *finger in [_fingers.allValues copy]){
        [self recognizeAimHold:finger at:now];
        FNVTouchContact state=finger.state;if(FNVTouchRecognizeHold(&state,now,FNVNumber(_settings,@"hold",.38,.22,.8))){
            CGPoint point=CGPointMake(state.lastX,state.lastY);NSValue *key=nil;for(NSValue *candidate in _fingers)if(_fingers[candidate]==finger){key=candidate;break;}
            [self openOverlay:1 origin:point];state.owner=FNVTouchOverlayOwner;state.fire=0;finger.state=state;if(key)_fingers[key]=finger;break;
        }
    }
    FNVPadState state={0};
    if(_standardFallback){
        for(FNVFinger *finger in _fingers.allValues){FNVTouchContact c=finger.state;
            if(c.owner==FNVTouchFallbackOwner&&finger.action>=0&&[self hitButton:CGPointMake(c.lastX,c.lastY)]==finger.action)FNVTouchFallbackButton(&state,(unsigned)finger.action);
            else if(c.owner==FNVTouchMoveOwner||c.owner==FNVTouchMenuOwner)FNVTouchFallbackStick(&state,c.owner==FNVTouchMenuOwner,c.lastX-finger.origin.x,c.lastY-finger.origin.y,FNVTouchFallbackRadius([self policySafe]));
        }
    }else if(!_overlay){
        for(FNVFinger *finger in _fingers.allValues){FNVTouchContact c=finger.state;
            if(c.owner==FNVTouchMoveOwner||(c.owner==FNVTouchMenuOwner&&FNVTouchRightStickContext(_context))){FNVTouchNavigationStick(&state,_context,c.owner==FNVTouchMenuOwner,c.lastX-finger.origin.x,c.lastY-finger.origin.y,FNVNumber(_settings,@"radius",54,20,120),FNVNumber(_settings,@"moveDeadzone",.1,0,.5),FNVNumber(_settings,@"moveResponse",1,.4,3));}
            else if(c.owner==FNVTouchFireOwner&&c.fire)[self addCode:fnv_pad_binding(4) state:&state];
            else if(c.owner==FNVTouchAimOwner){if(c.fire)[self addCode:fnv_pad_binding(4) state:&state];}
            else if(c.owner==FNVTouchActionOwner&&finger.action>=0&&finger.action<6)[self addCode:fnv_pad_binding(FNVGameplayActions[finger.action]) state:&state];
        }
        BOOL aim=_aimed;if(aim&&[self isGame])[self addCode:fnv_pad_binding(6) state:&state];
        if([self isGame]){
            FNVTouchVector filtered=FNVTouchSmooth((FNVTouchVector){_smoothX,_smoothY},_lookDX,_lookDY,dt,FNVNumber(_settings,@"smoothing",0,0,.12));
            _smoothX=filtered.x;_smoothY=filtered.y;
            double gx=0,gy=0;
            if([_settings[@"gyro"] boolValue]&&!_calibrateUntil&&now-_gyroSampleAt<.15){
                gx=_gyroRateX-_biasX;gy=_gyroRateY-_biasY;if(fabs(gx)<.018)gx=0;if(fabs(gy)<.018)gy=0;
                gx*=[_settings[@"gyroInvertX"] boolValue]?-1:1;gy*=[_settings[@"gyroInvertY"] boolValue]?-1:1;
            }
            double ads=aim?FNVNumber(_settings,@"ads",1,.1,4):1,multiplier=FNVNumber(_settings,@"lookMultiplier",1,.25,10);
            if([_settings[@"cameraDirect"] boolValue]){
                FNVMouseDelta delta=FNVTouchRelative(&_relativeCarry,_smoothX,_smoothY,gx,gy,dt,FNVNumber(_settings,@"swipeX",3,.25,12),FNVNumber(_settings,@"swipeY",3,.25,12),FNVNumber(_settings,@"gyroX",3,.1,20),FNVNumber(_settings,@"gyroY",3,.1,20),fnv_pad_mouse_radians(),multiplier,ads,[_settings[@"invertX"] boolValue],[_settings[@"invertY"] boolValue]);
#ifndef FNV_PROBE
                if(delta.dx||delta.dy)fnv_pad_mouse_move(delta.dx,delta.dy);
#endif
            }else{
                FNVTouchVector look=FNVTouchStick(_smoothX,_smoothY,gx*57.2958*FNVNumber(_settings,@"gyroX",3,.1,20)*multiplier*ads,gy*57.2958*FNVNumber(_settings,@"gyroY",3,.1,20)*multiplier*ads,dt,FNVNumber(_settings,@"lookX",.2,.02,4)*multiplier*ads,FNVNumber(_settings,@"lookY",.2,.02,4)*multiplier*ads,FNVNumber(_settings,@"maxTurnRate",171.887,60,1000),FNVNumber(_settings,@"stickDeadzone",.265175,0,.5),FNVNumber(_settings,@"stickResponse",2,.4,3),[_settings[@"invertX"] boolValue],[_settings[@"invertY"] boolValue]);
#ifndef FNV_PROBE
                state.rx=(int16_t)lround(look.x*32767);state.ry=(int16_t)lround(look.y*32767);
#endif
            }
        }else if(_lookDX||_lookDY){
            double x=FNVTouchClamp(_lookDX/fmax(.001,dt)/600,-1,1),y=FNVTouchClamp(-_lookDY/fmax(.001,dt)/600,-1,1);
            if(_context==FNVContextVATS||_context==FNVContextMinigame||_context==FNVContextLockpick){state.rx=(int16_t)lround(x*32767);state.ry=(int16_t)lround(y*32767);}else{state.lx=(int16_t)lround(x*32767);state.ly=(int16_t)lround(y*32767);}
        }
    }
    for(NSDictionary *pulse in [_pulses copy]){if([pulse[@"until"] doubleValue]<=now)[_pulses removeObject:pulse];else if(pulse[@"code"])[self addCode:[pulse[@"code"] unsignedIntValue] state:&state];else if(pulse[@"axis"]){int16_t v=(int16_t)lround([pulse[@"value"] doubleValue]*32767);NSString *axis=pulse[@"axis"];if([axis isEqualToString:@"lx"])state.lx=v;if([axis isEqualToString:@"ly"])state.ly=v;if([axis isEqualToString:@"rx"])state.rx=v;if([axis isEqualToString:@"ry"])state.ry=v;}else state.buttons|=[pulse[@"mask"] unsignedIntValue];}
    _lookDX=_lookDY=0;fnv_pad_touch_state(&state);[self setNeedsDisplay];
}
- (NSArray *)editorTargets {
    NSMutableArray *names=[[self buttonNames] mutableCopy];[names addObjectsFromArray:_editingPip?@[@"Navigation / zoom region",@"Map / preview stick region",@"Utility radial"]:@[@"Movement region",@"Look region",@"Utility radial"]];return names;
}
- (NSMutableDictionary *)selectedSettings {
    NSMutableArray *buttons=[self buttonSettings];if(_selected<(NSInteger)buttons.count)return buttons[_selected];
    if(_selected==(NSInteger)buttons.count)return _settings[_editingPip?@"pipMove":@"move"];
    if(_selected==(NSInteger)buttons.count+1)return _settings[_editingPip?@"pipLook":@"look"];
    return _settings;
}
- (void)dragSelectionBy:(CGPoint)delta {
    NSMutableDictionary *selected=[self selectedSettings];NSInteger count=[self buttonSettings].count;
    if(_selected==count+2){_settings[@"radialX"]=@(FNVTouchClamp([_settings[@"radialX"] doubleValue]+delta.x/_safe.size.width,0,1));_settings[@"radialY"]=@(FNVTouchClamp([_settings[@"radialY"] doubleValue]+delta.y/_safe.size.height,0,1));}
    else{double maxX=1,maxY=1;if(_selected>=count){maxX=1-[selected[@"w"] doubleValue];maxY=1-[selected[@"h"] doubleValue];}
        selected[@"x"]=@(FNVTouchClamp([selected[@"x"] doubleValue]+delta.x/_safe.size.width,0,maxX));selected[@"y"]=@(FNVTouchClamp([selected[@"y"] doubleValue]+delta.y/_safe.size.height,0,maxY));}
    [self setNeedsLayout];
}
- (UIButton *)editorButton:(NSString *)title rect:(CGRect)rect handler:(void (^)(void))handler {
    UIButton *button=[UIButton buttonWithType:UIButtonTypeSystem];button.frame=rect;[button setTitle:title forState:UIControlStateNormal];button.tintColor=[self amber:1];button.titleLabel.font=[UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];button.layer.borderWidth=1;button.layer.borderColor=[self amber:.5].CGColor;
    [button addAction:[UIAction actionWithHandler:^(UIAction *action){handler();}] forControlEvents:UIControlEventTouchUpInside];return button;
}
- (CGFloat)editorHeading:(NSString *)title at:(CGFloat)y {
    UILabel *label=[[UILabel alloc] initWithFrame:CGRectMake(10,y,_editorPanel.bounds.size.width-20,27)];label.text=title;label.font=[UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];label.textColor=[self amber:1];[_editorPanel addSubview:label];return y+30;
}
- (CGFloat)editorSlider:(NSString *)title target:(NSMutableDictionary *)target key:(NSString *)key low:(double)low high:(double)high y:(CGFloat)y {
    CGFloat w=_editorPanel.bounds.size.width;UILabel *label=[[UILabel alloc] initWithFrame:CGRectMake(10,y,w-20,20)];label.font=[UIFont systemFontOfSize:12];label.textColor=[self amber:.9];double value=FNVNumber(target,key,low,low,high);label.text=[NSString stringWithFormat:@"%@  %.2f",title,value];[_editorPanel addSubview:label];
    UISlider *slider=[[UISlider alloc] initWithFrame:CGRectMake(10,y+20,w-20,28)];slider.minimumValue=low;slider.maximumValue=high;slider.value=value;slider.tintColor=[self amber:1];slider.accessibilityLabel=title;
    __weak FNVGameplayTouchView *weak=self;__weak UISlider *weakSlider=slider;
    [slider addAction:[UIAction actionWithHandler:^(UIAction *action){
        UISlider *control=weakSlider;if(!control)return;double value=control.value;
        if(target[@"w"]&&target[@"h"]){
            if([key isEqualToString:@"x"])value=FNVTouchClamp(value,0,1-[target[@"w"] doubleValue]);
            if([key isEqualToString:@"y"])value=FNVTouchClamp(value,0,1-[target[@"h"] doubleValue]);
            if([key isEqualToString:@"w"])value=FNVTouchClamp(value,.08,1-[target[@"x"] doubleValue]);
            if([key isEqualToString:@"h"])value=FNVTouchClamp(value,.08,1-[target[@"y"] doubleValue]);
        }
        target[key]=@(value);control.value=value;label.text=[NSString stringWithFormat:@"%@  %.2f",title,value];[weak setNeedsLayout];
    }] forControlEvents:UIControlEventValueChanged];[_editorPanel addSubview:slider];return y+53;
}
- (CGFloat)editorSwitch:(NSString *)title target:(NSMutableDictionary *)target key:(NSString *)key y:(CGFloat)y {
    CGFloat w=_editorPanel.bounds.size.width;UILabel *label=[[UILabel alloc] initWithFrame:CGRectMake(10,y,w-80,36)];label.text=title;label.numberOfLines=2;label.font=[UIFont systemFontOfSize:12];label.textColor=[self amber:.9];[_editorPanel addSubview:label];
    UISwitch *toggle=[[UISwitch alloc] initWithFrame:CGRectMake(w-62,y+2,52,32)];toggle.on=[target[key] boolValue];toggle.onTintColor=[self amber:.8];toggle.accessibilityLabel=title;
    __weak FNVGameplayTouchView *weak=self;__weak UISwitch *weakToggle=toggle;[toggle addAction:[UIAction actionWithHandler:^(UIAction *action){UISwitch *control=weakToggle;if(!control)return;target[key]=@(control.isOn);[weak setNeedsDisplay];}] forControlEvents:UIControlEventValueChanged];[_editorPanel addSubview:toggle];return y+40;
}
- (void)openEditor {
    _standardFallback=NO;fnv_pad_stick_camera(![_settings[@"cameraDirect"] boolValue]);
    [self resetTouches];if(_editing)return;_beforeEdit=FNVCopySettings(_settings);_settings=FNVCopySettings(_settings);_editing=YES;_editingPip=NO;_editingUtilities=NO;_editorPreview=NO;_selected=0;
    _editorPanel=[UIScrollView new];_editorPanel.backgroundColor=[UIColor colorWithWhite:.025 alpha:.96];_editorPanel.layer.borderWidth=1;_editorPanel.layer.borderColor=[self amber:.7].CGColor;_editorPanel.keyboardDismissMode=UIScrollViewKeyboardDismissModeOnDrag;[self addSubview:_editorPanel];
    __weak FNVGameplayTouchView *weak=self;_editorReturn=[self editorButton:@"Settings" rect:CGRectZero handler:^{FNVGameplayTouchView *view=weak;if(!view)return;view->_editorPreview=NO;view->_overlay=0;view->_editorPanel.hidden=NO;view->_editorReturn.hidden=YES;[view setNeedsDisplay];}];_editorReturn.backgroundColor=[UIColor colorWithWhite:.03 alpha:.95];_editorReturn.hidden=YES;[self addSubview:_editorReturn];[self setNeedsLayout];[self layoutIfNeeded];[self rebuildEditor];
}
- (void)closeEditorApply:(BOOL)apply {
    if(apply){_settings[@"version"]=@6;[NSUserDefaults.standardUserDefaults setObject:_settings forKey:FNVTouchSettingsKey];}
    else if(_beforeEdit)_settings=_beforeEdit;
    _beforeEdit=nil;_editing=NO;[_editorPanel removeFromSuperview];[_editorReturn removeFromSuperview];_editorPanel=nil;_editorReturn=nil;[self resetTouches];[self setNeedsLayout];
}
- (void)resetSelected {
    NSMutableDictionary *defaults=FNVDefaultSettings();NSInteger count=[self buttonSettings].count;
    if(_selected<count)[self buttonSettings][_selected]=defaults[_editingPip?@"pipButtons":@"gameButtons"][_selected];
    else if(_selected==count)_settings[_editingPip?@"pipMove":@"move"]=defaults[_editingPip?@"pipMove":@"move"];
    else if(_selected==count+1)_settings[_editingPip?@"pipLook":@"look"]=defaults[_editingPip?@"pipLook":@"look"];
    else for(NSString *key in @[@"radialX",@"radialY",@"radialSize",@"hold",@"radialOrder",@"moreOrder"])_settings[key]=defaults[key];
    [self rebuildEditor];[self setNeedsLayout];
}
- (void)rebuildEditor {
    if(!_editing)return;CGPoint offset=_editorPanel.contentOffset;for(UIView *view in _editorPanel.subviews)[view removeFromSuperview];
    CGFloat w=_editorPanel.bounds.size.width,y=8;__weak FNVGameplayTouchView *weak=self;
    NSArray *titles=@[@"Apply",@"Cancel",@"Preview"];
    for(unsigned i=0;i<3;i++){unsigned action=i;UIButton *button=[self editorButton:titles[i] rect:CGRectMake(8+i*(w-16)/3,y,(w-22)/3,36) handler:^{FNVGameplayTouchView *view=weak;if(!view)return;if(action<2)[view closeEditorApply:action==0];else{view->_editorPreview=YES;view->_editorPanel.hidden=YES;view->_editorReturn.hidden=NO;if(view->_editingUtilities){view->_selected=[view buttonSettings].count+2;view->_overlay=1;}[view setNeedsDisplay];}}];button.accessibilityIdentifier=@[@"editor-apply",@"editor-cancel",@"editor-preview"][i];[_editorPanel addSubview:button];}y+=44;
    UISegmentedControl *layout=[[UISegmentedControl alloc] initWithItems:@[@"Gameplay",@"Pip-Boy",@"Utilities"]];layout.frame=CGRectMake(10,y,w-20,31);layout.selectedSegmentIndex=_editingUtilities?2:(_editingPip?1:0);layout.selectedSegmentTintColor=[self amber:.22];layout.accessibilityIdentifier=@"editor-layout";
    [layout setTitleTextAttributes:@{NSForegroundColorAttributeName:[self amber:.9],NSFontAttributeName:[UIFont systemFontOfSize:12 weight:UIFontWeightMedium]} forState:UIControlStateNormal];
    [layout setTitleTextAttributes:@{NSForegroundColorAttributeName:[self amber:1],NSFontAttributeName:[UIFont systemFontOfSize:12 weight:UIFontWeightBold]} forState:UIControlStateSelected];
    __weak UISegmentedControl *weakLayout=layout;[layout addAction:[UIAction actionWithHandler:^(UIAction *action){FNVGameplayTouchView *view=weak;UISegmentedControl *control=weakLayout;if(!view||!control)return;view->_editingPip=control.selectedSegmentIndex==1;view->_editingUtilities=control.selectedSegmentIndex==2;view->_selected=0;view->_editorPanel.contentOffset=CGPointZero;[view setNeedsLayout];[view rebuildEditor];}] forControlEvents:UIControlEventValueChanged];[_editorPanel addSubview:layout];y+=39;
    if(_editingUtilities){y=[self utilityEditorAt:y];_editorPanel.contentSize=CGSizeMake(w,y);_editorPanel.contentOffset=CGPointMake(0,MIN(offset.y,MAX(0,y-_editorPanel.bounds.size.height)));return;}
    NSArray *targets=[self editorTargets];if(_selected>=(NSInteger)targets.count)_selected=0;
    UIButton *selection=[self editorButton:[NSString stringWithFormat:@"Selected: %@",targets[_selected]] rect:CGRectMake(10,y,w-20,38) handler:^{}];NSMutableArray *items=[NSMutableArray new];
    for(NSUInteger i=0;i<targets.count;i++){NSUInteger index=i;[items addObject:[UIAction actionWithTitle:targets[i] image:nil identifier:nil handler:^(UIAction *action){FNVGameplayTouchView *view=weak;if(!view)return;view->_selected=index;[view rebuildEditor];[view setNeedsDisplay];}]];}
    selection.menu=[UIMenu menuWithTitle:@"Choose a control or region" children:items];selection.showsMenuAsPrimaryAction=YES;[_editorPanel addSubview:selection];y+=46;
    UILabel *hint=[[UILabel alloc] initWithFrame:CGRectMake(10,y,w-20,58)];hint.numberOfLines=3;hint.text=@"Preview lets you drag the selected item. Hold four fingers for 1.2 seconds to recover customization. The game continues while editing.";hint.font=[UIFont systemFontOfSize:11];hint.textColor=[self amber:.8];[_editorPanel addSubview:hint];y+=62;
    NSMutableDictionary *selected=[self selectedSettings];NSInteger buttonCount=[self buttonSettings].count;
    if(_selected<buttonCount){
        y=[self editorSlider:@"Size" target:selected key:@"size" low:20 high:140 y:y];
        y=[self editorSlider:@"Button opacity" target:selected key:@"opacity" low:.1 high:1 y:y];
        y=[self editorSwitch:@"Show control" target:selected key:@"visible" y:y];
        y=[self editorSwitch:@"Show label" target:selected key:@"label" y:y];
        y=[self editorSlider:@"Horizontal position" target:selected key:@"x" low:0 high:1 y:y];y=[self editorSlider:@"Vertical position" target:selected key:@"y" low:0 high:1 y:y];
    }else if(_selected<buttonCount+2){
        for(NSString *key in @[@"x",@"y",@"w",@"h"]){NSString *title=@{@"x":@"Left",@"y":@"Top",@"w":@"Width",@"h":@"Height"}[key];y=[self editorSlider:title target:selected key:key low:([key isEqualToString:@"w"]||[key isEqualToString:@"h"]?.08:0) high:1 y:y];}
    }else{
        y=[self editorSlider:@"Radial horizontal position" target:_settings key:@"radialX" low:0 high:1 y:y];y=[self editorSlider:@"Radial vertical position" target:_settings key:@"radialY" low:0 high:1 y:y];y=[self editorSlider:@"Radial size" target:_settings key:@"radialSize" low:200 high:380 y:y];
    }
    UIButton *reset=[self editorButton:@"Reset Selected" rect:CGRectMake(10,y,w-20,36) handler:^{[weak resetSelected];}];[_editorPanel addSubview:reset];y+=44;
    y=[self editorHeading:@"Movement and appearance" at:y];
    y=[self editorSlider:@"Global opacity" target:_settings key:@"opacity" low:.15 high:1 y:y];
    y=[self editorSlider:@"Floating stick radius" target:_settings key:@"radius" low:20 high:120 y:y];
    y=[self editorSlider:@"Movement dead zone" target:_settings key:@"moveDeadzone" low:0 high:.5 y:y];
    y=[self editorSlider:@"Movement response" target:_settings key:@"moveResponse" low:.4 high:3 y:y];
    y=[self editorHeading:@"Swipe look and aim" at:y];
    y=[self editorSwitch:@"Direct swipe look (classic response)" target:_settings key:@"cameraDirect" y:y];
    y=[self editorSlider:@"Horizontal swipe sensitivity" target:_settings key:@"swipeX" low:.25 high:12 y:y];y=[self editorSlider:@"Vertical swipe sensitivity" target:_settings key:@"swipeY" low:.25 high:12 y:y];
    y=[self editorSlider:@"Look multiplier (swipe + gyro)" target:_settings key:@"lookMultiplier" low:.25 high:10 y:y];
    y=[self editorSlider:@"Aiming multiplier (swipe + gyro)" target:_settings key:@"ads" low:.1 high:4 y:y];y=[self editorSlider:@"Fire-drag sensitivity" target:_settings key:@"fireGain" low:.2 high:3 y:y];
    y=[self editorSwitch:@"Invert horizontal swipe" target:_settings key:@"invertX" y:y];y=[self editorSwitch:@"Invert vertical swipe" target:_settings key:@"invertY" y:y];
    y=[self editorSlider:@"Direction smoothing" target:_settings key:@"smoothing" low:0 high:.12 y:y];
    y=[self editorHeading:@"Controller response (Direct off)" at:y];
    y=[self editorSlider:@"Horizontal controller gain" target:_settings key:@"lookX" low:.02 high:4 y:y];y=[self editorSlider:@"Vertical controller gain" target:_settings key:@"lookY" low:.02 high:4 y:y];
    y=[self editorSlider:@"Stick dead-zone calibration" target:_settings key:@"stickDeadzone" low:0 high:.5 y:y];y=[self editorSlider:@"Stick response calibration" target:_settings key:@"stickResponse" low:.4 high:3 y:y];y=[self editorSlider:@"Maximum turn-rate calibration" target:_settings key:@"maxTurnRate" low:60 high:1000 y:y];
    y=[self editorHeading:@"Aim: tap gyro, hold ADS, tap to exit" at:y];
    y=[self editorSlider:@"Aim hold time (seconds)" target:_settings key:@"aimDelay" low:.2 high:.8 y:y];
    y=[self editorHeading:@"Gyroscope" at:y];
    y=[self editorSwitch:@"Enable gyro (independent of ADS)" target:_settings key:@"gyro" y:y];
    y=[self editorSlider:@"Gyro horizontal multiplier" target:_settings key:@"gyroX" low:.1 high:20 y:y];y=[self editorSlider:@"Gyro vertical multiplier" target:_settings key:@"gyroY" low:.1 high:20 y:y];y=[self editorSwitch:@"Invert horizontal gyro" target:_settings key:@"gyroInvertX" y:y];y=[self editorSwitch:@"Invert vertical gyro" target:_settings key:@"gyroInvertY" y:y];
    UIButton *calibrate=[self editorButton:@"Calibrate / Recenter gyro" rect:CGRectMake(10,y,w-20,36) handler:^{[weak calibrate];}];[_editorPanel addSubview:calibrate];y+=44;
    UIButton *resetLayout=[self editorButton:@"Reset Layout" rect:CGRectMake(10,y,w-20,38) handler:^{FNVGameplayTouchView *view=weak;if(!view)return;NSMutableDictionary *defaults=FNVDefaultSettings();NSString *buttons=view->_editingPip?@"pipButtons":@"gameButtons",*move=view->_editingPip?@"pipMove":@"move",*look=view->_editingPip?@"pipLook":@"look";view->_settings[buttons]=defaults[buttons];view->_settings[move]=defaults[move];view->_settings[look]=defaults[look];[view setNeedsLayout];[view rebuildEditor];}];[_editorPanel addSubview:resetLayout];y+=48;
    _editorPanel.contentSize=CGSizeMake(w,y);_editorPanel.contentOffset=CGPointMake(0,MIN(offset.y,MAX(0,y-_editorPanel.bounds.size.height)));
}
- (void)assignUtility:(NSUInteger)action radial:(BOOL)radial slot:(NSUInteger)slot {
    if(!_editing||!FNVUtilityAssign(_settings,radial,slot,action))return;
    [self rebuildEditor];[self setNeedsDisplay];
}
- (CGFloat)utilityEditorAt:(CGFloat)y {
    CGFloat w=_editorPanel.bounds.size.width;__weak FNVGameplayTouchView *weak=self;
    UILabel *hint=[[UILabel alloc] initWithFrame:CGRectMake(10,y,w-20,58)];hint.text=@"Choose an action to swap with this slot. Move actions between Radial and More. More stays on the wheel so every action stays reachable.";hint.numberOfLines=4;hint.font=[UIFont systemFontOfSize:12];hint.textColor=[self amber:.9];[_editorPanel addSubview:hint];y+=64;
    for(unsigned group=0;group<2;group++){
        BOOL radial=group==0;NSArray *order=_settings[radial?@"radialOrder":@"moreOrder"];
        y=[self editorHeading:radial?@"Radial sectors":@"More actions" at:y];
        for(NSUInteger slot=0;slot<order.count;slot++){
            NSUInteger current=[order[slot] unsignedIntegerValue];
            UIButton *entry=[self editorButton:[NSString stringWithFormat:@"%lu: %@",(unsigned long)slot+1,FNVUtilityNames()[current]] rect:CGRectMake(10,y,w-20,36) handler:^{}];
            entry.accessibilityIdentifier=[NSString stringWithFormat:@"utility-%@-%lu",radial?@"radial":@"more",(unsigned long)slot];
            NSMutableArray *groups=[NSMutableArray new];
            for(unsigned source=0;source<2;source++){
                NSMutableArray *choices=[NSMutableArray new];
                for(NSNumber *item in _settings[source==0?@"radialOrder":@"moreOrder"]){NSUInteger action=item.unsignedIntegerValue;
                    UIAction *choice=[UIAction actionWithTitle:FNVUtilityNames()[action] image:nil identifier:nil handler:^(UIAction *sender){[weak assignUtility:action radial:radial slot:slot];}];
                    choice.state=action==current?UIMenuElementStateOn:UIMenuElementStateOff;
                    if((!radial&&action==FNVUtilityMore)||(radial&&current==FNVUtilityMore&&source==1))choice.attributes=UIMenuElementAttributesDisabled;
                    [choices addObject:choice];
                }
                [groups addObject:[UIMenu menuWithTitle:source==0?@"Radial":@"More" image:nil identifier:nil options:UIMenuOptionsDisplayInline children:choices]];
            }
            entry.menu=[UIMenu menuWithTitle:@"Swap this slot with…" children:groups];entry.showsMenuAsPrimaryAction=YES;[_editorPanel addSubview:entry];y+=42;
        }
    }
    y=[self editorHeading:@"Radial placement and hold" at:y];
    y=[self editorSlider:@"Horizontal position" target:_settings key:@"radialX" low:0 high:1 y:y];
    y=[self editorSlider:@"Vertical position" target:_settings key:@"radialY" low:0 high:1 y:y];
    y=[self editorSlider:@"Radial size" target:_settings key:@"radialSize" low:200 high:380 y:y];
    y=[self editorSlider:@"Hold threshold (seconds)" target:_settings key:@"hold" low:.22 high:.8 y:y];
    UIButton *reset=[self editorButton:@"Reset Utilities" rect:CGRectMake(10,y,w-20,38) handler:^{FNVGameplayTouchView *view=weak;if(!view)return;NSMutableDictionary *defaults=FNVDefaultSettings();for(NSString *key in @[@"radialOrder",@"moreOrder",@"radialX",@"radialY",@"radialSize",@"hold"])view->_settings[key]=defaults[key];[view rebuildEditor];[view setNeedsDisplay];}];reset.accessibilityIdentifier=@"utilities-reset";[_editorPanel addSubview:reset];return y+48;
}
@end
