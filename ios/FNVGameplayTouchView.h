#import <UIKit/UIKit.h>

@interface FNVGameplayTouchView : UIView
@property (nonatomic, copy) void (^movementChanged)(float right, float forward);
@property (nonatomic) CGFloat lookGain;        // Mouse counts per UIKit point
@property (nonatomic) CGFloat movementRadius;  // UIKit points
- (void)resetTouches;
@end
