#import "FNVGameplayTouchView.h"
#import "FNVTouchMath.h"
#include "input.h"  // recomp/host/input.h in Fallout-NV-MacOS
#include "FNVPad.h"
#import <QuartzCore/QuartzCore.h>

@implementation FNVGameplayTouchView {
    UITouch *_moveTouch;
    UITouch *_lookTouch;
    CGPoint _moveOrigin;
    FNVLook _look;
    NSMutableArray<UIButton *> *_buttons;
    UIView *_stickRing,*_stickThumb;
    UIButton *_sensitivity;
}

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.multipleTouchEnabled = YES;
        self.opaque = NO;
        self.backgroundColor = UIColor.clearColor;
        _lookGain = 1.0;
        _movementRadius = 56.0;
        _buttons=[NSMutableArray new];
#ifndef FNV_PROBE
        [self addPadButton:@"A" hint:@"Use / Confirm" tag:0x1000];
        [self addPadButton:@"B" hint:@"Pip-Boy / Back" tag:0x2000];
        [self addPadButton:@"X" hint:@"Reload / Equip" tag:0x4000];
        [self addPadButton:@"Y" hint:@"Jump" tag:0x8000];
        [self addPadButton:@"LT" hint:@"Aim" tag:-1];[self addPadButton:@"RT" hint:@"Fire" tag:-2];
        [self addPadButton:@"LB" hint:@"View" tag:0x100];[self addPadButton:@"RB" hint:@"VATS" tag:0x200];
        [self addPadButton:@"↑" hint:@"D-pad up" tag:1];[self addPadButton:@"↓" hint:@"D-pad down" tag:2];
        [self addPadButton:@"←" hint:@"D-pad left" tag:4];[self addPadButton:@"→" hint:@"D-pad right" tag:8];
        [self addPadButton:@"Menu" hint:@"Pause" tag:0x10];[self addPadButton:@"Back" hint:@"Wait" tag:0x20];
        [self addPadButton:@"L3" hint:@"Sneak" tag:0x40];[self addPadButton:@"R3" hint:@"Grab" tag:0x80];
        _sensitivity=[UIButton buttonWithType:UIButtonTypeSystem];_sensitivity.tintColor=UIColor.whiteColor;
        _sensitivity.titleLabel.font=[UIFont systemFontOfSize:12];
        [_sensitivity setTitle:@"Aim 1.0×" forState:UIControlStateNormal];
        [_sensitivity addTarget:self action:@selector(changeSensitivity:) forControlEvents:UIControlEventTouchUpInside];
        [self addSubview:_sensitivity];
#endif
        _stickRing=[UIView new];_stickThumb=[UIView new];
        for(UIView *v in @[_stickRing,_stickThumb]){v.userInteractionEnabled=NO;v.layer.borderColor=[UIColor.whiteColor colorWithAlphaComponent:0.45].CGColor;v.layer.borderWidth=1.5;v.backgroundColor=[UIColor.blackColor colorWithAlphaComponent:0.12];[self addSubview:v];}
        [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(willResign:)
            name:UIApplicationWillResignActiveNotification object:nil];
    }
    return self;
}
- (void)addPadButton:(NSString *)name hint:(NSString *)hint tag:(NSInteger)tag{
    UIButton *b=[UIButton buttonWithType:UIButtonTypeCustom];b.tag=tag;
    [b setTitle:name forState:UIControlStateNormal];b.accessibilityLabel=hint;
    b.titleLabel.font=[UIFont systemFontOfSize:name.length>2?12:19 weight:UIFontWeightSemibold];
    b.layer.borderWidth=1;b.layer.borderColor=[UIColor.whiteColor colorWithAlphaComponent:0.38].CGColor;
    b.backgroundColor=[UIColor.blackColor colorWithAlphaComponent:0.23];
    [b addTarget:self action:@selector(padDown:) forControlEvents:UIControlEventTouchDown];
    [b addTarget:self action:@selector(padUp:) forControlEvents:UIControlEventTouchUpInside|UIControlEventTouchUpOutside|UIControlEventTouchCancel];
    [_buttons addObject:b];[self addSubview:b];
}
- (void)padDown:(UIButton *)b{if(b.tag<0)fnv_pad_trigger(b.tag==-2,1);else fnv_pad_button((uint16_t)b.tag,1);b.backgroundColor=[UIColor.whiteColor colorWithAlphaComponent:0.35];}
- (void)padUp:(UIButton *)b{if(b.tag<0)fnv_pad_trigger(b.tag==-2,0);else fnv_pad_button((uint16_t)b.tag,0);b.backgroundColor=[UIColor.blackColor colorWithAlphaComponent:0.23];}
- (void)changeSensitivity:(UIButton *)b{
    const CGFloat values[]={0.5,1,1.5,2,3};NSUInteger selected=0;
    for(NSUInteger i=0;i<5;i++)if(fabs(self.lookGain-values[i])<0.01){selected=(i+1)%5;break;}
    self.lookGain=values[selected];[b setTitle:[NSString stringWithFormat:@"Aim %.1f×",self.lookGain] forState:UIControlStateNormal];
}
- (void)layoutSubviews{
    [super layoutSubviews];CGFloat w=self.bounds.size.width,h=self.bounds.size.height,l=self.safeAreaInsets.left+12,r=w-self.safeAreaInsets.right-12,b=h-self.safeAreaInsets.bottom-12;
    CGFloat cx=r-69,cy=b-83,dx=l+(r-l)*0.37,dy=b-37;
    CGPoint centers[]={CGPointMake(cx,cy+48),CGPointMake(cx+48,cy),CGPointMake(cx-48,cy),CGPointMake(cx,cy-48),
        CGPointMake(l+24,66),CGPointMake(r-24,66),CGPointMake(l+88,66),CGPointMake(r-88,66),
        CGPointMake(dx,dy-34),CGPointMake(dx,dy+34),CGPointMake(dx-34,dy),CGPointMake(dx+34,dy),
        CGPointMake(w/2+51,26),CGPointMake(w/2-51,26),CGPointMake(l+190,b-12),CGPointMake(r-190,b-12)};
    for(NSUInteger i=0;i<_buttons.count;i++){CGFloat size=i>=8&&i<12?32:46;UIButton *button=_buttons[i];button.bounds=CGRectMake(0,0,size,size);button.center=centers[i];button.layer.cornerRadius=size/2;}
    _sensitivity.frame=CGRectMake(w/2-44,47,88,32);
    if(!_moveTouch)_moveOrigin=CGPointMake(l+85,b-72);
    _stickRing.bounds=CGRectMake(0,0,self.movementRadius*2,self.movementRadius*2);_stickRing.center=_moveOrigin;_stickRing.layer.cornerRadius=self.movementRadius;
    _stickThumb.bounds=CGRectMake(0,0,44,44);if(!_moveTouch)_stickThumb.center=_moveOrigin;_stickThumb.layer.cornerRadius=22;
}

- (void)willResign:(NSNotification *)notification {
    [self resetTouches];
}

- (void)resetTouches {
    if (_moveTouch && self.movementChanged) self.movementChanged(0, 0);
    _moveTouch = nil;
    _lookTouch = nil;
    _look = (FNVLook){0};
    fnv_pad_reset();for(UIButton *b in _buttons)[self padUp:b];[self setNeedsLayout];
}

- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    for (UITouch *touch in touches) {
        CGPoint p = [touch locationInView:self];
        if (p.x < CGRectGetMidX(self.bounds)) {
            if (!_moveTouch) {
                _moveTouch = touch;
                _moveOrigin = p;
                _stickRing.center=p;_stickThumb.center=p;
            }
        } else if (!_lookTouch) {
            _lookTouch = touch;
            _look = (FNVLook){ p.x, p.y, 0, 0 };
        }
    }
}

- (void)sample:(UITouch *)touch {
    CGPoint p = [touch locationInView:self];
    if (touch == _lookTouch) {
        FNVMouseDelta d = FNVLookTo(&_look, p.x, p.y, MAX(0.0, self.lookGain));
        if (d.dx || d.dy) input_mouse_move(d.dx, d.dy);
    } else if (touch == _moveTouch && self.movementChanged) {
        FNVMove v = FNVMoveFromOffset(p.x - _moveOrigin.x, p.y - _moveOrigin.y,
                                     MAX(1.0, self.movementRadius));
        self.movementChanged((float)v.x, (float)v.y);
        _stickThumb.center=CGPointMake(_moveOrigin.x+v.x*self.movementRadius,_moveOrigin.y-v.y*self.movementRadius);
    }
}

- (void)touchesMoved:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    for (UITouch *touch in touches) [self sample:touch];
}

- (void)releaseTouches:(NSSet<UITouch *> *)touches {
    if (_moveTouch && [touches containsObject:_moveTouch]) {
        _moveTouch = nil;
        if (self.movementChanged) self.movementChanged(0, 0);
        [self setNeedsLayout];
    }
    if (_lookTouch && [touches containsObject:_lookTouch]) _lookTouch = nil;
}

- (void)touchesEnded:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    if (_lookTouch && [touches containsObject:_lookTouch]) [self sample:_lookTouch];
    [self releaseTouches:touches];
}

- (void)touchesCancelled:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    [self releaseTouches:touches];
}
@end
