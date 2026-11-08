// Production UIKit view and pad source with synthetic contacts. This exercises
// routing/drawing/actions; actual three-finger recognition still needs a phone.
#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#include <string.h>
#import "FNVGameplayTouchView.h"
#import "FNVTouchSettings.h"

void input_key(int key,int down){(void)key;(void)down;}
void input_touch_mouse_reset(void){}
static int mouseX,mouseY;
void input_touch_mouse_move(int x,int y){mouseX+=x;mouseY+=y;}

@interface FNVFinger : NSObject
@property(nonatomic) FNVTouchContact state;
@end

@interface FNVGameplayTouchView (TestEntryPoints)
- (void)tick:(CADisplayLink *)link;
- (void)toggleStandardController:(UITapGestureRecognizer *)recognizer;
- (void)openEditor;
- (NSArray *)buttonNames;
- (NSArray *)buttonSettings;
- (BOOL)buttonAvailable:(NSInteger)index;
- (void)willResign:(NSNotification *)notification;
- (void)didResume:(NSNotification *)notification;
- (void)openOverlay:(NSInteger)kind origin:(CGPoint)point;
- (void)radialAction:(NSInteger)sector;
- (void)moreAction:(NSInteger)item;
- (NSArray *)radialNames;
- (NSArray *)moreNames;
- (void)assignUtility:(NSUInteger)action radial:(BOOL)radial slot:(NSUInteger)slot;
- (void)closeEditorApply:(BOOL)apply;
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
static CGPoint normalButton(FNVGameplayTouchView *view,unsigned index){NSDictionary *b=view.buttonSettings[index];FNVTouchRect r=FNVTouchPlace(safe(view),[b[@"x"] doubleValue],[b[@"y"] doubleValue],[b[@"size"] doubleValue]);return CGPointMake(r.x+r.w/2,r.y+r.h/2);}
static void age(FNVGameplayTouchView *view,FNVTestContact *touch,double seconds){FNVFinger *f=[view valueForKey:@"fingers"][[NSValue valueWithNonretainedObject:touch]];FNVTouchContact c=f.state;c.began=CACurrentMediaTime()-seconds;f.state=c;}
static void motionSample(FNVGameplayTouchView *view){
    [view setValue:@0 forKey:@"calibrateUntil"];[view setValue:@0 forKey:@"biasX"];[view setValue:@0 forKey:@"biasY"];
    [view setValue:@1 forKey:@"gyroRateX"];[view setValue:@0 forKey:@"gyroRateY"];
    [view setValue:@(CACurrentMediaTime()) forKey:@"gyroSampleAt"];[view setValue:@(CACurrentMediaTime()-1.0/60) forKey:@"lastFrame"];
    mouseX=mouseY=0;[view tick:nil];
}
static void aimChecks(FNVGameplayTouchView *view,NSString *directory){
    if([[view valueForKey:@"standardFallback"] boolValue])toggle(view);
    [view resetTouches];[view setValue:FNVDefaultSettings() forKey:@"settings"];view.frame=CGRectMake(0,0,852,393);
    fnv_pad_context_set(FNVContextGameplay);[view tick:nil];[view setNeedsLayout];[view layoutIfNeeded];
    NSMutableDictionary *settings=[view valueForKey:@"settings"];CGPoint aim=normalButton(view,1),fire=normalButton(view,0);
    FNVTestContact *t=begin(view,aim,@[]);[view tick:nil];
    check(@"Aim down waits for the hold threshold without sending LT or enabling gyro",neutral(snapshot())&&![settings[@"gyro"] boolValue]);
    end(view,t);[view tick:nil];
    check(@"normal Aim tap enables and persists gyro without ADS",[settings[@"gyro"] boolValue]&&snapshot().left_trigger==0&&[[NSUserDefaults.standardUserDefaults objectForKey:FNVTouchSettingsKey][@"gyro"] boolValue]&&[view.buttonNames[1] isEqual:@"Gyro ON"]);
    motionSample(view);check(@"enabled gyro turns the gameplay camera while ADS is off",mouseX>0&&snapshot().left_trigger==0);
    render(view,directory,@"aim-gyro-enabled.png");
    t=begin(view,aim,@[]);age(view,t,1);[view tick:nil];
    check(@"holding Aim enters ADS without changing the gyro preference",snapshot().left_trigger==255&&[settings[@"gyro"] boolValue]);
    end(view,t);[view tick:nil];
    check(@"releasing the hold keeps ADS latched and does not toggle gyro",snapshot().left_trigger==255&&[settings[@"gyro"] boolValue]&&[view.buttonNames[1] isEqual:@"Exit ADS"]);
    motionSample(view);check(@"gyro remains active in ADS",mouseX>0&&snapshot().left_trigger==255);
    render(view,directory,@"aim-ads-latched.png");
    t=begin(view,aim,@[]);end(view,t);[view tick:nil];
    check(@"first tap after ADS exits it while leaving gyro enabled",snapshot().left_trigger==0&&[settings[@"gyro"] boolValue]);
    t=begin(view,aim,@[]);end(view,t);[view tick:nil];
    check(@"the following tap disables gyro without entering ADS",snapshot().left_trigger==0&&![settings[@"gyro"] boolValue]);
    motionSample(view);check(@"disabled gyro cannot turn the camera",mouseX==0&&mouseY==0);
    t=begin(view,aim,@[]);age(view,t,1);end(view,t);[view tick:nil];
    check(@"a hold released between display ticks enters ADS with gyro still off",snapshot().left_trigger==255&&![settings[@"gyro"] boolValue]);
    t=begin(view,aim,@[]);age(view,t,1);[view tick:nil];end(view,t);[view tick:nil];
    check(@"another long hold while in ADS does not toggle either state",snapshot().left_trigger==255&&![settings[@"gyro"] boolValue]);
    t=begin(view,aim,@[]);end(view,t);[view tick:nil];
    check(@"ADS exit also leaves an already disabled gyro off",snapshot().left_trigger==0&&![settings[@"gyro"] boolValue]);
    t=begin(view,aim,@[]);move(view,t,fire);[view tick:nil];
    check(@"Aim slide to Fire enters ADS and fires before the hold deadline",snapshot().left_trigger==255&&snapshot().right_trigger==255&&![settings[@"gyro"] boolValue]);
    end(view,t);[view tick:nil];check(@"slide release stops firing but keeps ADS without a gyro tap",snapshot().left_trigger==255&&snapshot().right_trigger==0&&![settings[@"gyro"] boolValue]);
    [view resetTouches];t=begin(view,aim,@[]);move(view,t,CGPointMake(450,60));age(view,t,1);end(view,t);[view tick:nil];
    check(@"dragging off Aim and releasing outside cancels the gesture",neutral(snapshot())&&![settings[@"gyro"] boolValue]);
    t=begin(view,aim,@[]);[view touchesCancelled:(id)[NSSet setWithObject:t] withEvent:nil];end(view,t);[view tick:nil];
    check(@"cancelled tap leaves gyro unchanged and no ADS input",neutral(snapshot())&&![settings[@"gyro"] boolValue]);
    FNVTestContact *walk=begin(view,CGPointMake(150,150),@[]);move(view,walk,CGPointMake(175,130));
    FNVTestContact *shoot=begin(view,fire,@[walk]);t=begin(view,aim,@[walk,shoot]);end(view,t);[view tick:nil];
    check(@"tapping gyro preserves another finger's movement and held Fire",snapshot().lx>0&&snapshot().ly>0&&snapshot().right_trigger==255&&snapshot().left_trigger==0&&[settings[@"gyro"] boolValue]);
    end(view,walk);end(view,shoot);[view resetTouches];
    t=begin(view,aim,@[]);FNVTestContact *duplicate=begin(view,aim,@[t]);end(view,duplicate);[view tick:nil];
    check(@"a second finger on Aim cannot steal or duplicate the first gesture",[settings[@"gyro"] boolValue]&&snapshot().left_trigger==0);
    end(view,t);[view tick:nil];check(@"the owning Aim finger toggles exactly once",![settings[@"gyro"] boolValue]&&neutral(snapshot()));
    t=begin(view,aim,@[]);fnv_pad_context_set(FNVContextPipMap);end(view,t);[view tick:nil];
    check(@"menu transition before release discards a pending gyro tap",![settings[@"gyro"] boolValue]&&neutral(snapshot()));
    fnv_pad_context_set(FNVContextGameplay);[view tick:nil];[view layoutIfNeeded];t=begin(view,aim,@[]);age(view,t,1);[view tick:nil];[view willResign:nil];end(view,t);[view didResume:nil];[view tick:nil];
    check(@"background and resume release ADS without toggling gyro",neutral(snapshot())&&![settings[@"gyro"] boolValue]);
    t=begin(view,aim,@[]);FNVPadState physical={0};physical.buttons=0x1000;fnv_pad_physical_state(&physical,1);end(view,t);[view tick:nil];
    check(@"physical-controller takeover discards Aim and keeps physical input intact",snapshot().buttons==0x1000&&snapshot().left_trigger==0&&![settings[@"gyro"] boolValue]);
    fnv_pad_physical_state(NULL,0);[view tick:nil];t=begin(view,aim,@[]);age(view,t,1);[view tick:nil];end(view,t);toggle(view);[view tick:nil];
    check(@"standard fallback clears latched ADS and continues to expose raw LT",neutral(snapshot())&&[[view valueForKey:@"standardFallback"] boolValue]);
    toggle(view);[view tick:nil];check(@"return from fallback has no hidden ADS latch",neutral(snapshot())&&![[view valueForKey:@"aimed"] boolValue]);
    settings[@"cameraDirect"]=@NO;settings[@"gyro"]=@YES;motionSample(view);
    check(@"gyro also works independently of ADS in controller-camera mode",snapshot().rx>0&&snapshot().left_trigger==0);
    [view resetTouches];
}
static void render(FNVGameplayTouchView *view,NSString *directory,NSString *name){
    [view layoutIfNeeded];UIGraphicsImageRenderer *renderer=[[UIGraphicsImageRenderer alloc] initWithSize:view.bounds.size];
    UIImage *image=[renderer imageWithActions:^(UIGraphicsImageRendererContext *context){
        [[UIColor colorWithWhite:.04 alpha:1] setFill];CGContextFillRect(context.CGContext,view.bounds);[view drawRect:view.bounds];
    }];
    check([@"native overlay PNG: " stringByAppendingString:name],[UIImagePNGRepresentation(image) writeToFile:[directory stringByAppendingPathComponent:name] atomically:YES]);
}
static void renderEditor(FNVGameplayTouchView *view,NSString *directory){
    [view layoutIfNeeded];UIGraphicsImageRenderer *renderer=[[UIGraphicsImageRenderer alloc] initWithSize:view.bounds.size];
    UIImage *image=[renderer imageWithActions:^(UIGraphicsImageRendererContext *context){
        [[UIColor colorWithWhite:.04 alpha:1] setFill];CGContextFillRect(context.CGContext,view.bounds);[view drawRect:view.bounds];
        for(UIView *child in view.subviews)if(!child.hidden){[child layoutIfNeeded];[child.layer displayIfNeeded];CGContextSaveGState(context.CGContext);CGContextTranslateCTM(context.CGContext,child.frame.origin.x,child.frame.origin.y);[child.layer renderInContext:context.CGContext];CGContextRestoreGState(context.CGContext);}
    }];
    check(@"native Utilities editor PNG",[UIImagePNGRepresentation(image) writeToFile:[directory stringByAppendingPathComponent:@"utilities-editor.png"] atomically:YES]);
}
static void utilityChecks(FNVGameplayTouchView *view,NSString *directory){
    if([[view valueForKey:@"standardFallback"] boolValue])toggle(view);
    view.frame=CGRectMake(0,0,852,393);[view setValue:FNVDefaultSettings() forKey:@"settings"];fnv_pad_context_set(FNVContextGameplay);[view resetTouches];[view layoutIfNeeded];[view tick:nil];
    [view openOverlay:1 origin:CGPointZero];
    check(@"default radial replaces change ammo with Holster / Ready",[view.radialNames[3] isEqual:@"Holster / Ready"]&&![view.radialNames containsObject:@"Change ammo"]);
    render(view,directory,@"utilities-radial-default.png");
    [view radialAction:3];NSArray *pulses=[view valueForKey:@"pulses"];double remaining=[pulses.lastObject[@"until"] doubleValue]-CACurrentMediaTime();[view tick:nil];
    check(@"default radial holster retains the original long X press",remaining>.7&&remaining<=.85&&snapshot().buttons==0x4000);
    [view resetTouches];[view openOverlay:3 origin:CGPointZero];
    check(@"default More has change ammo in holster's previous position",[view.moreNames[1] isEqual:@"Change ammo"]&&![view.moreNames containsObject:@"Holster / Ready"]);
    render(view,directory,@"utilities-more-default.png");
    [view moreAction:1];[view tick:nil];check(@"Change Ammo moved to More retains its native D-pad-up input",snapshot().buttons==1);
    [view openEditor];UIScrollView *panel=[view valueForKey:@"editorPanel"];UISegmentedControl *tabs=nil;
    for(UIView *child in panel.subviews)if([child isKindOfClass:UISegmentedControl.class]&&[child.accessibilityIdentifier isEqual:@"editor-layout"])tabs=(id)child;
    check(@"native editor exposes a dedicated Utilities tab",tabs.numberOfSegments==3&&[[tabs titleForSegmentAtIndex:2] isEqual:@"Utilities"]);
    tabs.selectedSegmentIndex=2;[tabs sendActionsForControlEvents:UIControlEventValueChanged];
    unsigned radial=0,more=0;BOOL choices=YES;
    for(UIView *child in panel.subviews)if([child isKindOfClass:UIButton.class]){
        UIButton *button=(id)child;if([button.accessibilityIdentifier hasPrefix:@"utility-radial-"])radial++;else if([button.accessibilityIdentifier hasPrefix:@"utility-more-"])more++;else continue;
        NSUInteger count=0;for(UIMenu *group in button.menu.children)count+=group.children.count;
        if(!button.showsMenuAsPrimaryAction||count!=FNVUtilityCount)choices=NO;
    }
    check(@"all seven radial and six More slots offer the shared action chooser",radial==7&&more==6&&choices);
    renderEditor(view,directory);
    for(UIView *child in panel.subviews)if([child.accessibilityIdentifier isEqual:@"editor-preview"])[(UIButton *)child sendActionsForControlEvents:UIControlEventTouchUpInside];
    [view tick:nil];check(@"Utilities Preview shows the radial while keeping game input neutral",[[view valueForKey:@"overlay"] intValue]==1&&[[view valueForKey:@"editorPreview"] boolValue]&&neutral(snapshot()));
    [(UIButton *)[view valueForKey:@"editorReturn"] sendActionsForControlEvents:UIControlEventTouchUpInside];
    [view assignUtility:FNVUtilityLight radial:YES slot:3];[view closeEditorApply:YES];
    NSMutableDictionary *settings=[view valueForKey:@"settings"];
    check(@"native editor Apply exchanges Light and Holster across both surfaces",[settings[@"radialOrder"][3] intValue]==FNVUtilityLight&&[settings[@"moreOrder"][2] intValue]==FNVUtilityHolster&&FNVUtilityLayoutValid(settings)&&[FNVTouchLoadSettings(NSUserDefaults.standardUserDefaults) isEqual:settings]);
    [view openOverlay:1 origin:CGPointZero];[view radialAction:3];pulses=[view valueForKey:@"pulses"];remaining=[pulses.lastObject[@"until"] doubleValue]-CACurrentMediaTime();[view tick:nil];
    check(@"Light moved to the radial retains its long native B press",remaining>.85&&remaining<=1&&snapshot().buttons==0x2000);
    [view resetTouches];[view moreAction:2];pulses=[view valueForKey:@"pulses"];remaining=[pulses.lastObject[@"until"] doubleValue]-CACurrentMediaTime();[view tick:nil];
    check(@"Holster moved to More retains its long native X press",remaining>.7&&remaining<=.85&&snapshot().buttons==0x4000);
    [view openEditor];NSMutableDictionary *before=FNVCopySettings([view valueForKey:@"settings"]);[view assignUtility:FNVUtilityReload radial:NO slot:3];[view closeEditorApply:NO];
    check(@"Cancel restores both utility lists after a cross-menu swap",[[view valueForKey:@"settings"] isEqual:before]);
    [view openEditor];[view assignUtility:FNVUtilityCustomize radial:YES slot:0];[view closeEditorApply:YES];[view radialAction:0];
    panel=[view valueForKey:@"editorPanel"];settings=[view valueForKey:@"settings"];
    NSDictionary *editorEvidence=@{@"editing_lookup":[view valueForKey:@"editing"],@"editing_ivar":[view valueForKey:@"_editing"],@"radial":settings[@"radialOrder"],@"more":settings[@"moreOrder"],@"panel_visible":@(panel.superview==view&&!panel.hidden),@"overlay":[view valueForKey:@"overlay"]};
    [[NSJSONSerialization dataWithJSONObject:editorEvidence options:NSJSONWritingPrettyPrinted error:NULL] writeToFile:[directory stringByAppendingPathComponent:@"customize-radial-state.json"] atomically:YES];
    check(@"Customize Controls works when moved directly onto the radial",panel.superview==view&&!panel.hidden&&[settings[@"radialOrder"][0] intValue]==FNVUtilityCustomize&&[[view valueForKey:@"_editing"] boolValue]);[view closeEditorApply:NO];
    [view openEditor];[view assignUtility:FNVUtilityGyro radial:NO slot:0];[view closeEditorApply:YES];BOOL oldGyro=[[[view valueForKey:@"settings"] objectForKey:@"gyro"] boolValue];[view moreAction:0];
    check(@"Gyro moved to More toggles and persists with an updated label",[[[view valueForKey:@"settings"] objectForKey:@"gyro"] boolValue]!=oldGyro&&[view.moreNames[0] isEqual:oldGyro?@"Gyro OFF":@"Gyro ON"]&&[[NSUserDefaults.standardUserDefaults objectForKey:FNVTouchSettingsKey][@"gyro"] boolValue]!=oldGyro);
    [view openEditor];[view assignUtility:FNVUtilityWeapons radial:NO slot:4];[view closeEditorApply:YES];[view moreAction:4];[view tick:nil];
    check(@"Weapons moved to More opens a persistent unarmed wheel with no B leakage",[[view valueForKey:@"overlay"] integerValue]==2&&![[view valueForKey:@"radialArmed"] boolValue]&&neutral(snapshot()));
    [view radialAction:0];[view tick:nil];check(@"nested weapon selection retains its original hotkey mask",snapshot().buttons==5);
    [view resetTouches];[view moreAction:6];[view tick:nil];check(@"More's Back returns to the radial with neutral input",[[view valueForKey:@"overlay"] integerValue]==1&&neutral(snapshot()));
    [view openEditor];settings=[view valueForKey:@"settings"];settings[@"swipeX"]=@4.5;settings[@"gyroX"]=@12;
    panel=[view valueForKey:@"editorPanel"];tabs=nil;
    for(UIView *child in panel.subviews)if([child.accessibilityIdentifier isEqual:@"editor-layout"])tabs=(id)child;
    tabs.selectedSegmentIndex=2;[tabs sendActionsForControlEvents:UIControlEventValueChanged];
    for(UIView *child in [panel.subviews copy])if([child.accessibilityIdentifier isEqual:@"utilities-reset"])[(UIButton *)child sendActionsForControlEvents:UIControlEventTouchUpInside];
    check(@"Reset Utilities restores holster and ammo placement without resetting camera settings",[settings[@"radialOrder"] isEqual:FNVDefaultRadialOrder()]&&[settings[@"moreOrder"] isEqual:FNVDefaultMoreOrder()]&&[settings[@"swipeX"] doubleValue]==4.5&&[settings[@"gyroX"] doubleValue]==12);
    [view closeEditorApply:YES];
    [view resetTouches];
}
static void run(NSString *directory){
    results=[NSMutableArray new];fnv_use_analog(1);
    NSMutableDictionary *custom=FNVDefaultSettings();custom[@"gyro"]=@YES;custom[@"swipeX"]=@4.5;custom[@"gameButtons"][5][@"visible"]=@NO;
    [NSUserDefaults.standardUserDefaults setObject:custom forKey:FNVTouchSettingsKey];
    FNVTestView *view=[[FNVTestView alloc] initWithFrame:CGRectMake(0,0,852,393)];[view layoutIfNeeded];[view tick:nil];
    UITapGestureRecognizer *gesture=(id)view.gestureRecognizers.firstObject;
    check(@"global recovery uses an exact three-finger double-tap without delaying ordinary touches",[gesture isKindOfClass:UITapGestureRecognizer.class]&&gesture.numberOfTapsRequired==2&&gesture.numberOfTouchesRequired==3&&gesture.cancelsTouchesInView&&!gesture.delaysTouchesBegan&&!gesture.delaysTouchesEnded);
    check(@"game view reserves the shortcut from system text-editing gestures",view.editingInteractionConfiguration==UIEditingInteractionConfigurationNone);
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
    utilityChecks(view,directory);
    aimChecks(view,directory);
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
