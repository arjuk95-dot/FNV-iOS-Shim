#import <UIKit/UIKit.h>
#import "FNVSurface.h"
#import "FNVGameplayTouchView.h"
#import "FNVPad.h"
#import "input.h"
#import <CommonCrypto/CommonDigest.h>
#include <pthread.h>
#include <unistd.h>
#include <stdio.h>
#include <stdlib.h>

@interface MetalView : UIView
@end
@implementation MetalView
+ (Class)layerClass { return CAMetalLayer.class; }
@end

static CAMetalLayer *screenLayer;
static pthread_mutex_t activeLock = PTHREAD_MUTEX_INITIALIZER;
static pthread_cond_t activeChanged = PTHREAD_COND_INITIALIZER;
static BOOL active;

static void setActive(BOOL value) {
    pthread_mutex_lock(&activeLock);
    active = value;
    pthread_cond_broadcast(&activeChanged);
    pthread_mutex_unlock(&activeLock);
}
void fnv_wait_active(void) {
    pthread_mutex_lock(&activeLock);
    while (!active) pthread_cond_wait(&activeChanged, &activeLock);
    pthread_mutex_unlock(&activeLock);
}
static void onMain(dispatch_block_t work) {
    if (NSThread.isMainThread) work(); else dispatch_sync(dispatch_get_main_queue(), work);
}
CAMetalLayer *fnv_surface(id<MTLDevice> device, CGSize size) {
    onMain(^{
        screenLayer.device = device;
        screenLayer.pixelFormat = MTLPixelFormatBGRA8Unorm;
        screenLayer.framebufferOnly = NO;
        screenLayer.drawableSize = size;
        screenLayer.contentsGravity = kCAGravityResizeAspect;
    });
    return screenLayer;
}
void fnv_resize_surface(CGSize size) { onMain(^{ screenLayer.drawableSize = size; }); }

#ifndef FNV_PROBE
static NSString *exeHash(NSURL *url) {
    NSInputStream *stream = [NSInputStream inputStreamWithURL:url];
    CC_SHA256_CTX hash;
    CC_SHA256_Init(&hash);
    [stream open];
    uint8_t buffer[16384]; NSInteger n;
    while ((n = [stream read:buffer maxLength:sizeof buffer]) > 0)
        CC_SHA256_Update(&hash, buffer, (CC_LONG)n);
    [stream close];
    if (n < 0) return nil;
    uint8_t bytes[CC_SHA256_DIGEST_LENGTH]; CC_SHA256_Final(bytes, &hash);
    NSMutableString *result = [NSMutableString string];
    for (size_t i=0; i<sizeof bytes; ++i) [result appendFormat:@"%02x",bytes[i]];
    return result;
}
#endif

#ifndef FNV_PROBE
static void gameButton(UIButton *button, BOOL down) {
    if (button.tag < 0) input_mouse_button((int)-button.tag - 1, down);
    else input_key((int)button.tag, down);
}
#endif
@interface App : UIResponder <UIApplicationDelegate>
@property(nonatomic,strong) UIWindow *window;
@property(nonatomic,strong) UILabel *status;
@property(nonatomic,strong) FNVGameplayTouchView *touch;
@end
@implementation App
#ifndef FNV_PROBE
- (void)buttonDown:(UIButton *)b { gameButton(b,YES); }
- (void)buttonUp:(UIButton *)b { gameButton(b,NO); }
- (void)addActions:(UIView *)view {
    UIStackView *row = [UIStackView new]; row.spacing = 4;
    row.translatesAutoresizingMaskIntoConstraints = NO;
    NSArray *names = @[@"↑",@"↓",@"Enter",@"Back",@"Use",@"Pip",@"Fire",@"Aim"];
    const int codes[] = {0xc8,0xd0,0x1c,0x01,0x12,0x0f,-1,-2};
    for (NSUInteger i=0; i<names.count; i++) {
        UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
        b.tag = codes[i];
        [b setTitle:names[i] forState:UIControlStateNormal];
        b.tintColor = UIColor.whiteColor;
        b.backgroundColor = [UIColor.blackColor colorWithAlphaComponent:0.45];
        [b.widthAnchor constraintGreaterThanOrEqualToConstant:44].active = YES;
        [b.heightAnchor constraintGreaterThanOrEqualToConstant:44].active = YES;
        [b addTarget:self action:@selector(buttonDown:) forControlEvents:UIControlEventTouchDown];
        [b addTarget:self action:@selector(buttonUp:) forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside | UIControlEventTouchCancel];
        [row addArrangedSubview:b];
    }
    [view addSubview:row];
    [NSLayoutConstraint activateConstraints:@[[row.centerXAnchor constraintEqualToAnchor:view.centerXAnchor],
        [row.bottomAnchor constraintEqualToAnchor:view.safeAreaLayoutGuide.bottomAnchor]]];
}
#endif
- (BOOL)application:(UIApplication *)app didFinishLaunchingWithOptions:(NSDictionary *)options {
    self.window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    UIViewController *vc = [UIViewController new];
    MetalView *view = [[MetalView alloc] initWithFrame:self.window.bounds];
    vc.view = view; self.window.rootViewController = vc;
    screenLayer = (CAMetalLayer *)view.layer;
    self.touch = [[FNVGameplayTouchView alloc] initWithFrame:view.bounds];
    self.touch.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.touch.movementChanged = ^(float x, float y){ fnv_move(x,y); };
    [view addSubview:self.touch];
    self.status = [UILabel new];
    self.status.numberOfLines = 0; self.status.textColor = UIColor.whiteColor;
    self.status.backgroundColor = [UIColor.blackColor colorWithAlphaComponent:0.5];
    self.status.font = [UIFont systemFontOfSize:15]; self.status.translatesAutoresizingMaskIntoConstraints = NO;
    [view addSubview:self.status];
    [NSLayoutConstraint activateConstraints:@[
        [self.status.leadingAnchor constraintEqualToAnchor:view.safeAreaLayoutGuide.leadingAnchor constant:12],
        [self.status.topAnchor constraintEqualToAnchor:view.safeAreaLayoutGuide.topAnchor constant:8],
        [self.status.trailingAnchor constraintLessThanOrEqualToAnchor:view.safeAreaLayoutGuide.trailingAnchor constant:-8]]];
    [self.window makeKeyAndVisible];
    NSURL *docs = [NSFileManager.defaultManager URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask].firstObject;
    NSURL *log = [docs URLByAppendingPathComponent:@"fnv.log"];
    freopen(log.fileSystemRepresentation, "w", stderr); setvbuf(stderr, NULL, _IONBF, 0);
#ifdef FNV_PROBE
    fnv_use_analog(1);
    self.status.text = @"Input / Metal probe · Swipe right half to change red and green. Hold left stick to change blue.";
#else
    NSURL *root = [docs URLByAppendingPathComponent:@"FalloutNV" isDirectory:YES];
    NSURL *exe = [root URLByAppendingPathComponent:@"FalloutNV.exe"];
    if (![NSFileManager.defaultManager fileExistsAtPath:[root URLByAppendingPathComponent:@"Data/FalloutNV.esm"].path] ||
        ![NSFileManager.defaultManager fileExistsAtPath:exe.path]) {
        self.status.text = @"Copy your matching FalloutNV.exe and Data folder into Documents/FalloutNV, then reopen.";
        return YES;
    }
    if (chdir(root.fileSystemRepresentation)) { self.status.text = @"Could not open the game directory."; return YES; }
    NSString *expected = [NSBundle.mainBundle objectForInfoDictionaryKey:@"FNVExecutableSHA256"];
    if (![expected isEqualToString:exeHash(exe)]) {
        self.status.text = @"FalloutNV.exe does not match this build. See the build machine’s executable.";
        return YES;
    }
    setenv("FNV_ROOT", root.fileSystemRepresentation, 1);
    // An empty file is an explicit opt-in to testing the game's controller path.
    fnv_use_analog([NSFileManager.defaultManager fileExistsAtPath:[root URLByAppendingPathComponent:@"analog-input.flag"].path]);
    [self addActions:view];
    self.status.text = nil;
#endif
    NSThread *thread = [[NSThread alloc] initWithBlock:^{
        @autoreleasepool {
            fnv_wait_active();
#ifdef FNV_PROBE
            extern int fnv_probe(unsigned);
            int rc = fnv_probe(0);
#else
            extern int fnv_run_game(int, char **);
            char *argv[] = {"fnv-ios", "FalloutNV.exe", NULL};
            int rc = fnv_run_game(2, argv);
#endif
            __block NSString *failureDetail = nil;
            if (rc) {
                NSString *diagnostic = [NSString stringWithContentsOfURL:log encoding:NSUTF8StringEncoding error:NULL];
                [diagnostic enumerateLinesUsingBlock:^(NSString *line, BOOL *stop) {
                    if ([line hasPrefix:@"[host] TRAP"]) failureDetail = line;
                }];
            }
            dispatch_async(dispatch_get_main_queue(), ^{
                self.status.text = failureDetail ?: [NSString stringWithFormat:@"Host returned %d. See Documents/fnv.log.",rc];
            });
        }
    }];
    thread.stackSize = 8 * 1024 * 1024;
    [thread start];
    return YES;
}
- (void)applicationWillResignActive:(UIApplication *)app { [self.touch resetTouches];
#ifndef FNV_PROBE
    for (int i=0; i<2; ++i) input_mouse_button(i, 0);
    int keys[] = {0xc8,0xd0,0x1c,0x01,0x12,0x0f};
    for (unsigned i=0; i<sizeof keys/sizeof keys[0]; ++i) input_key(keys[i],0);
#endif
    setActive(NO); }
- (void)applicationDidBecomeActive:(UIApplication *)app { setActive(YES); }
@end

int main(int argc, char **argv) {
    @autoreleasepool { return UIApplicationMain(argc,argv,nil,NSStringFromClass(App.class)); }
}
