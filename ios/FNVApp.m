#import <UIKit/UIKit.h>
#import "FNVSurface.h"
#import "FNVGameplayTouchView.h"
#import "FNVPad.h"
#include "FNVDisplay.h"
#ifndef FNV_PROBE
#include "FNVNativeMedia.h"
#endif
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

@interface App : UIResponder <UIApplicationDelegate>
@property(nonatomic,strong) UIWindow *window;
@property(nonatomic,strong) UILabel *status;
@property(nonatomic,strong) FNVGameplayTouchView *touch;
@end
@implementation App
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
    CGSize native=UIScreen.mainScreen.nativeBounds.size;fnv_display_configure((unsigned)native.width,(unsigned)native.height);
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
    setenv("FNV_TRACE_FILES", "1", 1);
    setenv("FNV_TRACE_SYNC", "1", 1);
    fnv_use_analog(1);
    // Update only owned display/controller keys; preserve the synchronous NavMesh setting and all other INI content.
    NSString *prefs=[root.path stringByAppendingPathComponent:@"UserDocuments/My Games/FalloutNV/FalloutPrefs.ini"];
    for(NSString *leaf in [NSFileManager.defaultManager contentsOfDirectoryAtPath:prefs.stringByDeletingLastPathComponent error:NULL])
        if([leaf caseInsensitiveCompare:@"FalloutPrefs.ini"]==NSOrderedSame){prefs=[prefs.stringByDeletingLastPathComponent stringByAppendingPathComponent:leaf];break;}
    NSString *text=[NSString stringWithContentsOfFile:prefs encoding:NSISOLatin1StringEncoding error:NULL]?:@"";
    if([NSFileManager.defaultManager fileExistsAtPath:prefs]&&![NSFileManager.defaultManager fileExistsAtPath:[prefs stringByAppendingString:@".before-native-display"]])
        [NSFileManager.defaultManager copyItemAtPath:prefs toPath:[prefs stringByAppendingString:@".before-native-display"] error:NULL];
    NSMutableArray<NSString*> *lines=[[text componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet] mutableCopy];
    NSDictionary *settings=@{@"display":@{@"isize w":@[@"iSize W",@(fnv_display_width())],@"isize h":@[@"iSize H",@(fnv_display_height())],@"bfull screen":@[@"bFull Screen",@1]},@"controls":@{@"buse joystick":@[@"bUse Joystick",@1]}};
    for(NSString *section in settings){NSDictionary *keys=settings[section];NSMutableSet *pending=[NSMutableSet setWithArray:keys.allKeys];BOOL inside=NO;NSInteger insert=-1;
        for(NSUInteger i=0;i<lines.count;i++){NSString *line=[lines[i] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
            if([line hasPrefix:@"["]&&[line hasSuffix:@"]"]){if(inside&&insert<0)insert=i;inside=[[[line substringWithRange:NSMakeRange(1,line.length-2)] lowercaseString] isEqualToString:section];}
            else if(inside){NSRange equal=[line rangeOfString:@"="];if(equal.location!=NSNotFound){NSString *key=[[[line substringToIndex:equal.location] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet] lowercaseString];NSArray *value=keys[key];if(value){lines[i]=[NSString stringWithFormat:@"%@=%@",value[0],value[1]];[pending removeObject:key];}}}
        }
        if(insert<0){insert=lines.count;if(!inside){[lines addObject:[NSString stringWithFormat:@"[%@]",section]];insert++;}}
        for(NSString *key in pending){NSArray *value=keys[key];[lines insertObject:[NSString stringWithFormat:@"%@=%@",value[0],value[1]] atIndex:insert++];}
    }
    [NSFileManager.defaultManager createDirectoryAtPath:prefs.stringByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:NULL];
    NSError *prefsError=nil;BOOL prefsOK=[[lines componentsJoinedByString:@"\n"] writeToFile:prefs atomically:YES encoding:NSISOLatin1StringEncoding error:&prefsError];
    fprintf(stderr,"[display] preferred %ux%u native aspect; controller + relative swipe; preferences=%s\n",fnv_display_width(),fnv_display_height(),prefsOK?"written":prefsError.localizedDescription.UTF8String);
    fnv_audio_start();
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
    fnv_media_active(0);
    for (int i=0; i<2; ++i) input_mouse_button(i, 0);
    int keys[] = {0xc8,0xd0,0x1c,0x01,0x12,0x0f};
    for (unsigned i=0; i<sizeof keys/sizeof keys[0]; ++i) input_key(keys[i],0);
#endif
    setActive(NO); }
- (void)applicationDidBecomeActive:(UIApplication *)app {
#ifndef FNV_PROBE
    fnv_media_active(1);
#endif
    setActive(YES); }
@end

int main(int argc, char **argv) {
    @autoreleasepool { return UIApplicationMain(argc,argv,nil,NSStringFromClass(App.class)); }
}
