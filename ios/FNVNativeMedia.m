#import <AVFoundation/AVFoundation.h>
#import "FNVNativeMedia.h"
#include <stdio.h>
#include <string.h>
#include <TargetConditionals.h>
void fnv_video_all_active(int active);
void fnv_dshow_all_active(int active);
static AVAudioEngine *audioEngine;
static AVAudioSourceNode *audioSource;
static BOOL mediaActive=YES;
int fnv_audio_start(void){
    @synchronized(AVAudioEngine.class){
        NSError *error=nil;
#if TARGET_OS_IPHONE
        AVAudioSession *session=AVAudioSession.sharedInstance;
        if(![session setCategory:AVAudioSessionCategoryPlayback mode:AVAudioSessionModeDefault options:0 error:&error] ||
           ![session setActive:YES error:&error]){fprintf(stderr,"[audio] session failed: %s\n",error.localizedDescription.UTF8String);return 0;}
#endif
        if(!audioEngine){
            audioEngine=[AVAudioEngine new];AVAudioFormat *format=[[AVAudioFormat alloc] initStandardFormatWithSampleRate:48000 channels:2];
            audioSource=[[AVAudioSourceNode alloc] initWithFormat:format renderBlock:^OSStatus(BOOL *silence,const AudioTimeStamp *time,AVAudioFrameCount frames,AudioBufferList *data){
                (void)time;*silence=NO;
                if(data->mNumberBuffers==2)fnv_audio_mix(data->mBuffers[0].mData,data->mBuffers[1].mData,frames,48000);
                else for(unsigned i=0;i<data->mNumberBuffers;i++)memset(data->mBuffers[i].mData,0,data->mBuffers[i].mDataByteSize);
                return noErr;
            }];
            [audioEngine attachNode:audioSource];[audioEngine connect:audioSource to:audioEngine.mainMixerNode format:format];
        }
        if(!audioEngine.running && mediaActive && ![audioEngine startAndReturnError:&error]){
            fprintf(stderr,"[audio] output failed: %s\n",error.localizedDescription.UTF8String);return 0;
        }
        fprintf(stderr,"[audio] native stereo PCM output ready at 48000 Hz\n");return 1;
    }
}
void fnv_media_active(int active){
    @synchronized(AVAudioEngine.class){mediaActive=!!active;if(!active)[audioEngine pause];else if(audioEngine)fnv_audio_start();}
    fnv_video_all_active(active);
    fnv_dshow_all_active(active);
}
