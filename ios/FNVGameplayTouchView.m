#import "FNVGameplayTouchView.h"
#import "FNVTouchMath.h"
#include "input.h"  // recomp/host/input.h in Fallout-NV-MacOS

@implementation FNVGameplayTouchView {
    UITouch *_moveTouch;
    UITouch *_lookTouch;
    CGPoint _moveOrigin;
    FNVLook _look;
}

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.multipleTouchEnabled = YES;
        self.opaque = NO;
        self.backgroundColor = UIColor.clearColor;
        _lookGain = 1.0;
        _movementRadius = 56.0;
        [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(willResign:)
            name:UIApplicationWillResignActiveNotification object:nil];
    }
    return self;
}

- (void)willResign:(NSNotification *)notification {
    [self resetTouches];
}

- (void)resetTouches {
    if (_moveTouch && self.movementChanged) self.movementChanged(0, 0);
    _moveTouch = nil;
    _lookTouch = nil;
    _look = (FNVLook){0};
}

- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    for (UITouch *touch in touches) {
        CGPoint p = [touch locationInView:self];
        if (p.x < CGRectGetMidX(self.bounds)) {
            if (!_moveTouch) {
                _moveTouch = touch;
                _moveOrigin = p;
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
    }
}

- (void)touchesMoved:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    for (UITouch *touch in touches) [self sample:touch];
}

- (void)releaseTouches:(NSSet<UITouch *> *)touches {
    if (_moveTouch && [touches containsObject:_moveTouch]) {
        _moveTouch = nil;
        if (self.movementChanged) self.movementChanged(0, 0);
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
