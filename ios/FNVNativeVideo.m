#import <AVFoundation/AVFoundation.h>
#import "FNVNativeMedia.h"
#include <stdio.h>
#include <string.h>
@interface FNVNativeMovie:NSObject
@property(nonatomic,strong) AVURLAsset *asset;
@property(nonatomic,strong) AVPlayer *player;
@property(nonatomic,strong) AVAssetReader *reader;
@property(nonatomic,strong) AVAssetReaderTrackOutput *output;
@property(nonatomic) CVPixelBufferRef pixels;
@property(nonatomic) unsigned decoded;
@property(nonatomic) BOOL paused;
@end
@implementation FNVNativeMovie
- (void)dealloc{if(_pixels)CVPixelBufferRelease(_pixels);}
@end
static NSMutableDictionary<NSNumber*,FNVNativeMovie*> *movies;
static uintptr_t nextMovie=1;
static BOOL videosActive=YES;
static FNVNativeMovie *movieFor(uintptr_t handle){@synchronized(FNVNativeMovie.class){return movies[@(handle)];}}
uintptr_t fnv_video_open(const char *path){
    @autoreleasepool{
        if(!path || ![NSFileManager.defaultManager fileExistsAtPath:[NSString stringWithUTF8String:path]])return 0;
        FNVNativeMovie *movie=[FNVNativeMovie new];
        movie.asset=[AVURLAsset URLAssetWithURL:[NSURL fileURLWithPath:[NSString stringWithUTF8String:path]] options:@{AVURLAssetPreferPreciseDurationAndTimingKey:@YES}];
        AVAssetTrack *track=[movie.asset tracksWithMediaType:AVMediaTypeVideo].firstObject;
        NSError *error=nil;
        if(!track){fprintf(stderr,"[video] no native video track: %s\n",path);return 0;}
        movie.reader=[[AVAssetReader alloc] initWithAsset:movie.asset error:&error];
        movie.output=[[AVAssetReaderTrackOutput alloc] initWithTrack:track outputSettings:@{(id)kCVPixelBufferPixelFormatTypeKey:@(kCVPixelFormatType_32BGRA)}];
        movie.output.alwaysCopiesSampleData=NO;
        if(![movie.reader canAddOutput:movie.output])return 0;
        [movie.reader addOutput:movie.output];
        if(![movie.reader startReading]){fprintf(stderr,"[video] native reader failed: %s\n",movie.reader.error.localizedDescription.UTF8String);return 0;}
        movie.player=[AVPlayer playerWithPlayerItem:[AVPlayerItem playerItemWithAsset:movie.asset]];
        movie.player.actionAtItemEnd=AVPlayerActionAtItemEndPause;
        fnv_audio_start();
        uintptr_t handle;
        @synchronized(FNVNativeMovie.class){if(!movies)movies=[NSMutableDictionary new];handle=nextMovie++;movies[@(handle)]=movie;if(videosActive)[movie.player play];}
        fprintf(stderr,"[video] native cached movie opened handle=%llu duration=%.3f\n",(unsigned long long)handle,CMTimeGetSeconds(movie.asset.duration));
        return handle;
    }
}
double fnv_video_time(uintptr_t handle){FNVNativeMovie *movie=movieFor(handle);double value=CMTimeGetSeconds(movie.player.currentTime);return isfinite(value)&&value>0?value:0;}
int fnv_video_decode(uintptr_t handle,unsigned frame){
    FNVNativeMovie *movie=movieFor(handle);if(!movie || !frame)return 0;
    @synchronized(movie){
        while(movie.decoded<frame){
            CMSampleBufferRef sample=[movie.output copyNextSampleBuffer];
            if(!sample){if(movie.reader.status==AVAssetReaderStatusFailed)fprintf(stderr,"[video] frame decode failed: %s\n",movie.reader.error.localizedDescription.UTF8String);return 0;}
            CVPixelBufferRef pixels=CMSampleBufferGetImageBuffer(sample);
            if(pixels)CVPixelBufferRetain(pixels);
            if(movie.pixels)CVPixelBufferRelease(movie.pixels);movie.pixels=pixels;movie.decoded++;
            CFRelease(sample);
        }
        return movie.pixels!=NULL;
    }
}
int fnv_video_copy(uintptr_t handle,void *destination,int pitch,unsigned dh,unsigned dx,unsigned dy,unsigned sx,unsigned sy,unsigned width,unsigned height,unsigned format){
    FNVNativeMovie *movie=movieFor(handle);if(!movie || !destination || pitch<=0 || format!=3)return 0;
    @synchronized(movie){
        CVPixelBufferRef pixels=movie.pixels;if(!pixels)return 0;
        unsigned sw=(unsigned)CVPixelBufferGetWidth(pixels),sh=(unsigned)CVPixelBufferGetHeight(pixels),dw=(unsigned)pitch/4;
        if(sx>=sw||sy>=sh||dx>=dw||dy>=dh)return 0;
        width=MIN(width,MIN(sw-sx,dw-dx));height=MIN(height,MIN(sh-sy,dh-dy));
        if(CVPixelBufferLockBaseAddress(pixels,kCVPixelBufferLock_ReadOnly)!=kCVReturnSuccess)return 0;
        const uint8_t *source=CVPixelBufferGetBaseAddress(pixels);size_t row=CVPixelBufferGetBytesPerRow(pixels);
        for(unsigned y=0;y<height;y++)memcpy((uint8_t*)destination+(size_t)(dy+y)*pitch+4*dx,source+(size_t)(sy+y)*row+4*sx,4*width);
        CVPixelBufferUnlockBaseAddress(pixels,kCVPixelBufferLock_ReadOnly);return 1;
    }
}
void fnv_video_pause(uintptr_t handle,int paused){FNVNativeMovie *movie=movieFor(handle);@synchronized(movie){movie.paused=!!paused;if(paused)[movie.player pause];else if(videosActive)[movie.player play];}}
void fnv_video_close(uintptr_t handle){FNVNativeMovie *movie=movieFor(handle);if(!movie)return;[movie.player pause];[movie.reader cancelReading];@synchronized(FNVNativeMovie.class){[movies removeObjectForKey:@(handle)];}fprintf(stderr,"[video] closed native movie %llu\n",(unsigned long long)handle);}
void fnv_video_all_active(int active){
    @synchronized(FNVNativeMovie.class){videosActive=!!active;for(FNVNativeMovie *movie in movies.allValues){if(!active)[movie.player pause];else if(!movie.paused)[movie.player play];}}
}
