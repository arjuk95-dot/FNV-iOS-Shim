// DirectSound PCM buffers mixed into native float stereo. All decoding remains on game workers.
#include "FNVNativeMedia.h"
#include <math.h>
#include <pthread.h>
#include <stdlib.h>
#include <string.h>
#define MAX_VOICES 4096
typedef struct {uint8_t *data;uint32_t bytes,refs;unsigned channels,rate,bits,format,alignment;} PCM;
typedef struct {PCM *pcm;double frame;unsigned frequency;float left,right;int volume,pan,playing,loop;} Voice;
static Voice *voices[MAX_VOICES];
static pthread_mutex_t audio_lock=PTHREAD_MUTEX_INITIALIZER;
static float master_gain=1;
static float gain(int db){return db<=-10000?0:powf(10.0f,fminf(0,db)/2000.0f);}
static void gains(Voice *v){v->left=gain(v->volume)*gain(v->pan>0?-v->pan:0);v->right=gain(v->volume)*gain(v->pan<0?v->pan:0);}
static uint32_t add(Voice *v){for(uint32_t i=1;i<MAX_VOICES;i++)if(!voices[i]){voices[i]=v;return i;}return 0;}
static Voice *get(uint32_t id){return id<MAX_VOICES?voices[id]:NULL;}
uint32_t fnv_audio_voice_create(uint32_t bytes,unsigned channels,unsigned rate,unsigned bits,unsigned format){
    if(!bytes || bytes>64u*1024*1024 || channels<1 || channels>2 || rate<100 || rate>200000 ||
       !((format==1&&(bits==8||bits==16||bits==24||bits==32))||(format==3&&bits==32)))return 0;
    PCM *p=calloc(1,sizeof *p);Voice *v=calloc(1,sizeof *v);
    if(!p||!v){free(p);free(v);return 0;}
    p->data=calloc(1,bytes);if(!p->data){free(p);free(v);return 0;}
    p->bytes=bytes;p->refs=1;p->channels=channels;p->rate=rate;p->bits=bits;p->format=format;p->alignment=channels*(bits/8);
    if(format==1&&bits==8)memset(p->data,128,bytes);
    v->pcm=p;v->frequency=rate;gains(v);
    pthread_mutex_lock(&audio_lock);uint32_t id=add(v);pthread_mutex_unlock(&audio_lock);
    if(!id){free(p->data);free(p);free(v);}return id;
}
uint32_t fnv_audio_voice_duplicate(uint32_t id){
    uint32_t copy=0;pthread_mutex_lock(&audio_lock);Voice *old=get(id);
    if(old){Voice *v=malloc(sizeof *v);if(v){*v=*old;v->frame=0;v->playing=0;copy=add(v);if(copy)v->pcm->refs++;else free(v);}}
    pthread_mutex_unlock(&audio_lock);return copy;
}
int fnv_audio_voice_destroy(uint32_t id){
    int last=0;pthread_mutex_lock(&audio_lock);Voice *v=get(id);
    if(v){voices[id]=NULL;if(!--v->pcm->refs){free(v->pcm->data);free(v->pcm);last=1;}free(v);}
    pthread_mutex_unlock(&audio_lock);return last;
}
void fnv_audio_voice_write(uint32_t id,uint32_t offset,const void *data,uint32_t bytes){
    pthread_mutex_lock(&audio_lock);Voice *v=get(id);
    if(v&&offset<v->pcm->bytes){if(bytes>v->pcm->bytes-offset)bytes=v->pcm->bytes-offset;memcpy(v->pcm->data+offset,data,bytes);}
    pthread_mutex_unlock(&audio_lock);
}
void fnv_audio_voice_play(uint32_t id,int loop){pthread_mutex_lock(&audio_lock);Voice *v=get(id);if(v){v->playing=1;v->loop=!!loop;}pthread_mutex_unlock(&audio_lock);}
void fnv_audio_voice_stop(uint32_t id){pthread_mutex_lock(&audio_lock);Voice *v=get(id);if(v)v->playing=0;pthread_mutex_unlock(&audio_lock);}
void fnv_audio_voice_seek(uint32_t id,uint32_t offset){pthread_mutex_lock(&audio_lock);Voice *v=get(id);if(v)v->frame=(offset%v->pcm->bytes)/v->pcm->alignment;pthread_mutex_unlock(&audio_lock);}
uint32_t fnv_audio_voice_cursor(uint32_t id,int *playing,int *loop){
    uint32_t cursor=0;pthread_mutex_lock(&audio_lock);Voice *v=get(id);
    if(v){cursor=(uint32_t)v->frame*v->pcm->alignment;if(playing)*playing=v->playing;if(loop)*loop=v->loop;}
    else{if(playing)*playing=0;if(loop)*loop=0;}pthread_mutex_unlock(&audio_lock);return cursor;
}
void fnv_audio_voice_volume(uint32_t id,int db){pthread_mutex_lock(&audio_lock);Voice *v=get(id);if(v){v->volume=db;gains(v);}pthread_mutex_unlock(&audio_lock);}
void fnv_audio_voice_pan(uint32_t id,int db){pthread_mutex_lock(&audio_lock);Voice *v=get(id);if(v){v->pan=db;gains(v);}pthread_mutex_unlock(&audio_lock);}
void fnv_audio_voice_frequency(uint32_t id,unsigned hz){pthread_mutex_lock(&audio_lock);Voice *v=get(id);if(v)v->frequency=hz?hz:v->pcm->rate;pthread_mutex_unlock(&audio_lock);}
void fnv_audio_master_volume(int db){pthread_mutex_lock(&audio_lock);master_gain=gain(db);pthread_mutex_unlock(&audio_lock);}
static float sample(const PCM *p,uint32_t frame,unsigned channel){
    const uint8_t *s=p->data+(size_t)frame*p->alignment+(channel<p->channels?channel:0)*(p->bits/8);
    if(p->format==3){float f;memcpy(&f,s,4);return isfinite(f)?f:0;}
    if(p->bits==8)return ((int)*s-128)/128.0f;
    if(p->bits==16){int16_t v;memcpy(&v,s,2);return v/32768.0f;}
    if(p->bits==24){int32_t v=(int32_t)((uint32_t)s[0]<<8|(uint32_t)s[1]<<16|(uint32_t)s[2]<<24);return v/2147483648.0f;}
    int32_t v;memcpy(&v,s,4);return v/2147483648.0f;
}
void fnv_audio_mix(float *left,float *right,unsigned frames,double rate){
    memset(left,0,frames*sizeof *left);memset(right,0,frames*sizeof *right);
    if(rate<=0 || pthread_mutex_trylock(&audio_lock))return; // audio thread never waits for guest writes
    for(unsigned id=1;id<MAX_VOICES;id++){
        Voice *v=voices[id];if(!v||!v->playing)continue;PCM *p=v->pcm;uint32_t total=p->bytes/p->alignment;
        if(!total){v->playing=0;continue;}double step=v->frequency/rate;
        for(unsigned i=0;i<frames;i++){
            if(v->frame>=total){if(v->loop)v->frame=fmod(v->frame,total);else{v->playing=0;v->frame=0;break;}}
            uint32_t a=(uint32_t)v->frame,b=a+1<total?a+1:v->loop?0:a;float fraction=(float)(v->frame-a);
            float l=sample(p,a,0),r=sample(p,a,p->channels==1?0:1);
            l+=(sample(p,b,0)-l)*fraction;r+=(sample(p,b,p->channels==1?0:1)-r)*fraction;
            left[i]+=l*v->left*master_gain;right[i]+=r*v->right*master_gain;v->frame+=step;
        }
        if(v->frame>=total){if(v->loop)v->frame=fmod(v->frame,total);else{v->playing=0;v->frame=0;}}
    }
    pthread_mutex_unlock(&audio_lock);
    for(unsigned i=0;i<frames;i++){left[i]=fmaxf(-1,fminf(1,left[i]));right[i]=fmaxf(-1,fminf(1,right[i]));}
}
