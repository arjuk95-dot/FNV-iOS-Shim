// Production UIKit view and pad source with synthetic contacts. This exercises
// routing/drawing/actions; actual three-finger recognition still needs a phone.
#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#include <string.h>
#import "FNVGameplayTouchView.h"
#import "FNVTouchSettings.h"

void input_key(int key,int down){(void)key;(void)down;}
void input_touch_mouse_reset(void){}
void input_touch_mouse_move(int x,int y){(void)x;(void)y;}

@interface FNVGameplayTouchView (TestEntryPoints)
- (void)tick:(CADisplayLink *)link;
- (void)toggleStandardController:(UITapGestureRecognizer *)recognizer;
- (void)openEditor;
- (NSArray *)buttonNames;
- (NSArray *)buttonSettings;
- (BOOL)buttonAvailable:(NSInteger)index;
- (void)willResign:(NSNotification *)notification;
- (void)didResume:(NSNotification *)notification;
@end
@interface FNVTestView : FNVGameplayTouchView @end
@implementation FNVTestView
- (void)readPhysicalController {} // Test fixture supplies the physical source.
@end
@interface FNVTestContact : NSObject
@property(nonatomic) CGPoint point;
@property(nonatomic) UITouchPhase phase;
- (CGPoint)locationInView:(UIView *)view;
@end
@implementation FNVTestContact
- (CGPoint)locationInView:(UIView *)view {(void)view;return self.point;}
@end
@interface FNVTestEvent : NSObject
@property(nonatomic) NSSet *allTouches;
@end
@implementation FNVTestEvent @end
@interface FNVRecognizedTap : UITapGestureRecognizer @end
@implementation FNVRecognizedTap
- (UIGestureRecognizerState)state {return UIGestureRecognizerStateRecognized;}
@end
static NSMutableArray *results;
static unsigned failures;
static void check(NSString *name,BOOL pass){
    [results addObject:@{@"name":name,@"pass":@(pass)}];failures+=!pass;
    fprintf(stderr,"%s: %s\n",pass?"PASS":"FAIL",name.UTF8String);
}
static FNVPadState snapshot(void){FNVPadState s;fnv_pad_snapshot(&s);return s;}
static BOOL neutral(FNVPadState s){return !(s.buttons||s.left_trigger||s.right_trigger||s.lx||s.ly||s.rx||s.ry);}
static FNVTouchRect safe(FNVGameplayTouchView *view){UIEdgeInsets i=view.safeAreaInsets;return(FNVTouchRect){i.left+8,i.top+8,view.bounds.size.width-i.left-i.right-16,view.bounds.size.height-i.top-i.bottom-16};}
static CGPoint button(FNVGameplayTouchView *view,unsigned index){FNVTouchRect r=FNVTouchFallbackFrame(safe(view),index);return CGPointMake(r.x+r.w/2,r.y+r.h/2);}
static FNVTestContact *begin(FNVGameplayTouchView *view,CGPoint point,NSArray *others){
    FNVTestContact *t=[FNVTestContact new];t.point=point;t.phase=UITouchPhaseBegan;
    FNVTestEvent *event=[FNVTestEvent new];event.allTouches=[NSSet setWithArray:[others arrayByAddingObject:t]];
    [view touchesBegan:(id)[NSSet setWithObject:t] withEvent:(id)event];return t;
}
static void move(FNVGameplayTouchView *view,FNVTestContact *t,CGPoint point){t.point=point;t.phase=UITouchPhaseMoved;[view touchesMoved:(id)[NSSet setWithObject:t] withEvent:nil];}
static void end(FNVGameplayTouchView *view,FNVTestContact *t){t.phase=UITouchPhaseEnded;FNVTestEvent *event=[FNVTestEvent new];event.allTouches=[NSSet setWithObject:t];[view touchesEnded:(id)event.allTouches withEvent:(id)event];}
static void toggle(FNVGameplayTouchView *view){[view toggleStandardController:[FNVRecognizedTap new]];[view layoutIfNeeded];}
static void render(FNVGameplayTouchView *view,NSString *directory,NSString *name){
    [view layoutIfNeeded];UIGraphicsImageRenderer *renderer=[[UIGraphicsImageRenderer alloc] initWithSize:view.bounds.size];
    UIImage *image=[renderer imageWithActions:^(UIGraphicsImageRendererContext *context){
        [[UIColor colorWithWhite:.04 alpha:1] setFill];CGContextFillRect(context.CGContext,view.bounds);[view drawRect:view.bounds];
    }];
    check([@"native overlay PNG: " stringByAppendingString:name],[UIImagePNGRepresentation(image) writeToFile:[directory stringByAppendingPathComponent:name] atomically:YES]);
}
static void run(NSString *directory){
    results=[NSMutableArray new];fnv_use_analog(1);
    NSMutableDictionary *custom=FNVDefaultSettings();custom[@"gyro"]=@YES;custom[@"swipeX"]=@4.5;custom[@"gameButtons"][5][@"visible"]=@NO;
    [NSUserDefaults.standardUserDefaults setObject:custom forKey:FNVTouchSettingsKey];
    FNVTestView *view=[[FNVTestView alloc] initWithFrame:CGRectMake(0,0,852,393)];[view layoutIfNeeded];[view tick:nil];
    UITapGestureRecognizer *gesture=(id)view.gestureRecognizers.firstObject;
    check(@"global recovery uses an exact three-finger double-tap without delaying ordinary touches",[gesture isKindOfClass:UITapGestureRecognizer.class]&&gesture.numberOfTapsRequired==2&&gesture.numberOfTouchesRequired==3&&gesture.cancelsTouchesInView&&!gesture.delaysTouchesBegan&&!gesture.delaysTouchesEnded);
    for(unsigned context=FNVContextGameplay;context<=FNVContextPipMap;context++){
        fnv_pad_context_set(context);[view tick:nil];toggle(view);
        check([NSString stringWithFormat:@"fallback reachable in context %u with hidden utility button",context],[[view valueForKey:@"standardFallback"] boolValue]&&view.buttonNames.count==16&&[view buttonAvailable:0]&&[view buttonAvailable:15]&&fnv_pad_uses_stick_camera());
        toggle(view);
    }
    fnv_pad_context_set(FNVContextMenu);[view tick:nil];[view layoutIfNeeded];
    check(@"generic character-creation menu exposes RT and LT",[view buttonAvailable:0]&&[view buttonAvailable:1]&&[view.buttonNames[0] containsString:@"RT"]&&[view.buttonNames[1] containsString:@"LT"]);
    BOOL genericTriggers=YES;
    for(unsigned i=0;i<2;i++){
        NSDictionary *b=view.buttonSettings[i];FNVTouchRect r=FNVTouchPlace(safe(view),[b[@"x"] doubleValue],[b[@"y"] doubleValue],[b[@"size"] doubleValue]);
        FNVTestContact *t=begin(view,CGPointMake(r.x+r.w/2,r.y+r.h/2),@[]);[view tick:nil];FNVPadState output=snapshot();
        if(output.left_trigger!=(i==1?255:0)||output.right_trigger!=(i==0?255:0)||output.buttons)genericTriggers=NO;
        end(view,t);[view resetTouches];
    }
    check(@"normal generic-menu trigger buttons emit separate native RT and LT pulses",genericTriggers);
    render(view,directory,@"generic-menu-triggers.png");
    toggle(view);
    const uint16_t masks[16]={0,0x100,0x20,0x10,0x200,0,1,2,4,8,0x1000,0x2000,0x4000,0x8000,0x40,0x80};
    BOOL all=YES;
    for(unsigned i=0;i<16;i++){
        FNVTestContact *t=begin(view,button(view,i),@[]);[view tick:nil];FNVPadState s=snapshot();
        if(s.buttons!=masks[i]||s.left_trigger!=(i==0?255:0)||s.right_trigger!=(i==5?255:0))all=NO;
        [view tick:nil];FNVPadState held=snapshot();if(memcmp((char *)&s+4,(char *)&held+4,12))all=NO;
        end(view,t);[view tick:nil];if(!neutral(snapshot()))all=NO;
    }
    check(@"production touch entry points hold and release all sixteen raw XInput controls",all);
    FNVTouchRect left=FNVTouchFallbackRegion(safe(view),0),right=FNVTouchFallbackRegion(safe(view),1);
    FNVTestContact *ls=begin(view,CGPointMake(left.x+left.w/2,left.y+left.h/2),@[]);
    FNVTestContact *rs=begin(view,CGPointMake(right.x+right.w/2,right.y+right.h/2),@[ls]);
    FNVTestContact *rt=begin(view,button(view,5),@[ls,rs]);
    move(view,ls,CGPointMake(ls.point.x+45,ls.point.y-20));move(view,rs,CGPointMake(rs.point.x-35,rs.point.y+20));[view tick:nil];
    FNVPadState s=snapshot();check(@"ordinary three-contact gameplay supports both two-axis sticks and held RT",s.lx>0&&s.ly>0&&s.rx<0&&s.ry<0&&s.right_trigger==255);
    render(view,directory,@"standard-controller-active.png");
    toggle(view);[view tick:nil];check(@"returning to normal clears both sticks and held RT",neutral(snapshot())&&![[view valueForKey:@"standardFallback"] boolValue]);
    move(view,rt,rt.point);end(view,rt);[view tick:nil];check(@"old fingers cannot become fresh normal actions after switching",neutral(snapshot()));
    fnv_pad_context_set(FNVContextGameplay);[view tick:nil];check(@"returning to normal restores the user's direct camera mode",!fnv_pad_uses_stick_camera());
    toggle(view);FNVTestContact *held=begin(view,button(view,5),@[]);[view tick:nil];
    fnv_pad_context_set(FNVContextPipMap);[view tick:nil];check(@"context changes retain fallback with neutral old inputs",[[view valueForKey:@"standardFallback"] boolValue]&&neutral(snapshot()));
    end(view,held);held=begin(view,button(view,0),@[]);[view tick:nil];[view willResign:nil];
    check(@"backgrounding releases raw LT while retaining fallback selection",neutral(snapshot())&&[[view valueForKey:@"standardFallback"] boolValue]);
    [view didResume:nil];[view tick:nil];check(@"resume is neutral",neutral(snapshot()));
    FNVPadState physical={0};physical.buttons=0x1000;physical.rx=18000;fnv_pad_physical_state(&physical,1);toggle(view);
    s=snapshot();check(@"mode changes preserve independently held physical-controller state",s.buttons==0x1000&&s.rx==18000&&s.right_trigger==0);fnv_pad_physical_state(NULL,0);
    [view openEditor];NSMutableDictionary *edited=[view valueForKey:@"settings"];edited[@"swipeX"]=@9;toggle(view);
    check(@"recovery inside editor cancels uncommitted edits and opens fallback",[[view valueForKey:@"standardFallback"] boolValue]&&![[view valueForKey:@"editing"] boolValue]&&[[view valueForKey:@"settings"][@"swipeX"] doubleValue]==4.5);
    check(@"fallback does not persist itself or rewrite saved custom controls",[[NSUserDefaults.standardUserDefaults objectForKey:FNVTouchSettingsKey] isEqual:custom]);
    const CGSize sizes[]={{852,393},{568,320},{1194,834}};NSArray *names=@[@"standard-controller-phone.png",@"standard-controller-compact.png",@"standard-controller-tablet.png"];
    for(unsigned i=0;i<3;i++){view.frame=(CGRect){CGPointZero,sizes[i]};[view setNeedsLayout];[view layoutIfNeeded];render(view,directory,names[i]);}
    NSDictionary *report=@{@"failures":@(failures),@"cases":results,@"production_view":@YES,@"native_uikit":@YES,@"contact_fixture":@"synthetic contacts delivered to production touch entry points",@"physical_gesture_recognition_verified":@NO,@"gameplay_verified":@NO};
    [[NSJSONSerialization dataWithJSONObject:report options:NSJSONWritingPrettyPrinted error:NULL] writeToFile:[directory stringByAppendingPathComponent:@"results.json"] atomically:YES];
    fprintf(stderr,"OVERLAY_TEST_FINISHED failures=%u\n",failures);
}
@interface FNVTestDelegate : UIResponder <UIApplicationDelegate>
@property(nonatomic) UIWindow *window;
@end
@implementation FNVTestDelegate
- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)options{
    self.window=[[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];self.window.rootViewController=[UIViewController new];[self.window makeKeyAndVisible];
    NSString *directory=[NSHomeDirectory() stringByAppendingPathComponent:@"Documents/OverlayTest"];
    [NSFileManager.defaultManager createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:NULL];
    dispatch_async(dispatch_get_main_queue(),^{run(directory);});return YES;
}
@end
int main(int argc,char **argv){@autoreleasepool{return UIApplicationMain(argc,argv,nil,NSStringFromClass(FNVTestDelegate.class));}}
