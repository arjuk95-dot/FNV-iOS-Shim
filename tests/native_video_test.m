#import <AVFoundation/AVFoundation.h>
#include "FNVNativeMedia.h"
#include <stdio.h>
#include <unistd.h>
int fnv_audio_start(void){return 1;} // Pixel decode test has no audio device requirement.
static int failed;
static void check(const char *name,int ok){printf("%s: %s\n",ok?"PASS":"FAIL",name);failed+=!ok;}
int main(void){@autoreleasepool{
    NSString *path=[NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"fnv-authored-%@.mov",NSUUID.UUID.UUIDString]];
    NSError *error=nil;AVAssetWriter *writer=[[AVAssetWriter alloc] initWithURL:[NSURL fileURLWithPath:path] fileType:AVFileTypeQuickTimeMovie error:&error];
    AVAssetWriterInput *input=[AVAssetWriterInput assetWriterInputWithMediaType:AVMediaTypeVideo outputSettings:@{AVVideoCodecKey:AVVideoCodecTypeH264,AVVideoWidthKey:@64,AVVideoHeightKey:@64}];
    AVAssetWriterInputPixelBufferAdaptor *adaptor=[AVAssetWriterInputPixelBufferAdaptor assetWriterInputPixelBufferAdaptorWithAssetWriterInput:input sourcePixelBufferAttributes:@{(id)kCVPixelBufferPixelFormatTypeKey:@(kCVPixelFormatType_32BGRA),(id)kCVPixelBufferWidthKey:@64,(id)kCVPixelBufferHeightKey:@64}];
    [writer addInput:input];if(![writer startWriting])abort();[writer startSessionAtSourceTime:kCMTimeZero];
    for(unsigned frame=0;frame<2;frame++){
        CVPixelBufferRef pixel=NULL;if(CVPixelBufferCreate(kCFAllocatorDefault,64,64,kCVPixelFormatType_32BGRA,NULL,&pixel))abort();
        CVPixelBufferLockBaseAddress(pixel,0);uint8_t *data=CVPixelBufferGetBaseAddress(pixel);size_t pitch=CVPixelBufferGetBytesPerRow(pixel);
        for(unsigned y=0;y<64;y++)for(unsigned x=0;x<64;x++){uint8_t *p=data+y*pitch+x*4;p[0]=frame?0:240;p[1]=frame?240:0;p[2]=0;p[3]=255;}
        CVPixelBufferUnlockBaseAddress(pixel,0);unsigned tries=0;while(!input.readyForMoreMediaData&&tries++<500)usleep(10000);
        if(![adaptor appendPixelBuffer:pixel withPresentationTime:CMTimeMake(frame,30)])abort();CVPixelBufferRelease(pixel);
    }
    [input markAsFinished];dispatch_semaphore_t done=dispatch_semaphore_create(0);[writer finishWritingWithCompletionHandler:^{dispatch_semaphore_signal(done);}];
    if(dispatch_semaphore_wait(done,dispatch_time(DISPATCH_TIME_NOW,10*NSEC_PER_SEC)))abort();
    check("authored H264 fixture encodes",writer.status==AVAssetWriterStatusCompleted);
    uintptr_t movie=fnv_video_open(path.fileSystemRepresentation);check("AVFoundation cache opens",movie!=0);fnv_video_pause(movie,1);
    uint8_t pixels[64*64*4]={0};check("first frame decodes",fnv_video_decode(movie,1));
    check("first decoded pixels reach guest-compatible BGRA buffer",fnv_video_copy(movie,pixels,256,64,0,0,0,0,64,64,3)&&pixels[0]>200&&pixels[1]<40);
    check("second frame decodes",fnv_video_decode(movie,2));memset(pixels,0,sizeof pixels);
    check("frame advancement changes actual pixel content",fnv_video_copy(movie,pixels,256,64,0,0,0,0,64,64,3)&&pixels[0]<40&&pixels[1]>200);
    memset(pixels,0,sizeof pixels);check("ROI honors destination and source offsets",fnv_video_copy(movie,pixels,256,64,3,4,2,1,10,8,3)&&pixels[4*256+3*4+1]>200&&pixels[0]==0);
    check("out-of-bounds ROI is rejected",!fnv_video_copy(movie,pixels,256,64,64,0,0,0,1,1,3));
    check("end of stream is a decode failure",!fnv_video_decode(movie,3));fnv_video_close(movie);
    check("closed handle cannot copy stale pixels",!fnv_video_copy(movie,pixels,256,64,0,0,0,0,1,1,3));
    [NSFileManager.defaultManager removeItemAtPath:path error:NULL];return failed?1:0;
}}
