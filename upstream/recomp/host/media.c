// Bink ABI bridge to an owner-local native movie cache; Vorbisfile uses native BSD codecs.
#include <stdio.h>
#include <pthread.h>
#include "shims.h"
#include "FNVNativeMedia.h"

typedef struct {uint32_t guest,frames,rate,divisor;uintptr_t native;int paused;} BinkMovie;
static BinkMovie movies[32];
static pthread_mutex_t movie_lock=PTHREAD_MUTEX_INITIALIZER;
static BinkMovie *find_movie(uint32_t guest){for(unsigned i=0;i<32;i++)if(movies[i].guest==guest)return &movies[i];return NULL;}
static uint32_t word(const uint8_t *p){uint32_t v;memcpy(&v,p,4);return v;}

// binkw32 exports are stdcall: the @N decoration is the argument byte count
static void BinkSetSoundSystem_(CPU *c) { RET(c, fnv_audio_start(), 2); }
static void BinkOpen_(CPU *c) {
    char path[1024],cache[1024],relative[512];uint8_t header[44];uint32_t guest=0;
    const char *requested=GSTR(ARG(c,0));if(!requested){RET(c,0,2);return;}
    host_path(requested,path,sizeof path);FILE *f=fopen(path,"rb");
    if(!f || fread(header,1,sizeof header,f)!=sizeof header){if(f)fclose(f);fprintf(stderr,"[bink] source open failed path=%s caller=%#x\n",requested,G32(REG(c,R_ESP)));RET(c,0,2);return;}
    fclose(f);
    uint32_t frames=word(header+8),width=word(header+20),height=word(header+24),rate=word(header+28),divisor=word(header+32);
    if(memcmp(header,"BIK",3)||!frames||frames>10000000||!width||width>8192||!height||height>8192||!rate||!divisor){fprintf(stderr,"[bink] unsupported source header path=%s caller=%#x\n",requested,G32(REG(c,R_ESP)));RET(c,0,2);return;}
    const char *leaf=strrchr(path,'/');leaf=leaf?leaf+1:path;const char *extension=strrchr(leaf,'.');size_t stem=extension?(size_t)(extension-leaf):strlen(leaf);
    if(stem>255){RET(c,0,2);return;}
    snprintf(relative,sizeof relative,"NativeMedia/%.*s.mp4",(int)stem,leaf);host_path(relative,cache,sizeof cache);
    pthread_mutex_lock(&movie_lock);BinkMovie *slot=NULL;for(unsigned i=0;i<32;i++)if(!movies[i].guest){slot=&movies[i];break;}
    uintptr_t native=slot?fnv_video_open(cache):0;
    if(native){
        guest=gmalloc(256);memset(MEM+guest,0,256);
        *slot=(BinkMovie){guest,frames,rate,divisor,native,0};
        P32(guest,width);P32(guest+4,height);P32(guest+8,frames);P32(guest+12,1);P32(guest+20,rate);P32(guest+24,divisor);
        P32(guest+32,ARG(c,1));P32(guest+40,word(header+4)+8);P32(guest+48,1);P32(guest+52,1);
        fprintf(stderr,"[bink] native cached playback path=%s %ux%u frames=%u guest=%#x caller=%#x\n",cache,width,height,frames,guest,G32(REG(c,R_ESP)));
    }else fprintf(stderr,"[bink] native cache unavailable path=%s source=%s caller=%#x\n",cache,requested,G32(REG(c,R_ESP)));
    pthread_mutex_unlock(&movie_lock);RET(c,guest,2);
}
static void BinkOpenDirectSound_(CPU *c) { RET(c, 0, 1); }
static void BinkClose_(CPU *c) {pthread_mutex_lock(&movie_lock);BinkMovie *m=find_movie(ARG(c,0));if(m){fnv_video_close(m->native);gfree(m->guest);memset(m,0,sizeof *m);}pthread_mutex_unlock(&movie_lock);RET(c,0,1);}
static void BinkNextFrame_(CPU *c) {pthread_mutex_lock(&movie_lock);BinkMovie *m=find_movie(ARG(c,0));if(m)P32(m->guest+12,G32(m->guest+12)+1);pthread_mutex_unlock(&movie_lock);RET(c,0,1);}
static void BinkWait_(CPU *c) {uint32_t wait=0;pthread_mutex_lock(&movie_lock);BinkMovie *m=find_movie(ARG(c,0));if(m){double next=(G32(m->guest+12)-1)*(double)m->divisor/m->rate;wait=m->paused||fnv_video_time(m->native)+0.0001<next;}pthread_mutex_unlock(&movie_lock);RET(c,wait,1);}
static void BinkPause_(CPU *c) {uint32_t previous=0;pthread_mutex_lock(&movie_lock);BinkMovie *m=find_movie(ARG(c,0));if(m){previous=m->paused;m->paused=!!ARG(c,1);fnv_video_pause(m->native,m->paused);}pthread_mutex_unlock(&movie_lock);RET(c,previous,2);}
static void BinkDoFrame_(CPU *c) {pthread_mutex_lock(&movie_lock);BinkMovie *m=find_movie(ARG(c,0));if(m){uint32_t frame=G32(m->guest+12);int ok=fnv_video_decode(m->native,frame);P32(m->guest+16,frame);P32(m->guest+28,!ok);static unsigned reports;if((frame<=2||!ok)&&reports++<8)fprintf(stderr,"[bink] decode guest=%#x frame=%u ok=%d\n",m->guest,frame,ok);}pthread_mutex_unlock(&movie_lock);RET(c,0,1);}
static void BinkCopyToBufferRect_(CPU *c) {
    uint32_t result=0,destination=ARG(c,1);int pitch=(int32_t)ARG(c,2);uint32_t height=ARG(c,3);
    pthread_mutex_lock(&movie_lock);BinkMovie *m=find_movie(ARG(c,0));
    uint64_t bytes=pitch>0?(uint64_t)(unsigned)pitch*height:UINT64_MAX;
    if(m&&bytes<=128u*1024*1024&&destination<=0xffffffffu-bytes)
        result=fnv_video_copy(m->native,MEM+destination,pitch,height,ARG(c,4),ARG(c,5),ARG(c,6),ARG(c,7),ARG(c,8),ARG(c,9),ARG(c,10)&15);
    static unsigned good,bad;
    if((result?good++:bad++)<4)fprintf(stderr,"[bink] copy guest=%#x pitch=%d height=%u dst=%u,%u src=%u,%u size=%ux%u format=%#x ok=%u\n",
        ARG(c,0),pitch,height,ARG(c,4),ARG(c,5),ARG(c,6),ARG(c,7),ARG(c,8),ARG(c,9),ARG(c,10),result);
    pthread_mutex_unlock(&movie_lock);RET(c,result,11);
}

// libvorbisfile exports are cdecl: the caller pops
#ifdef FNV_HAVE_VORBIS
void ov_open_callbacks_(CPU *);void ov_clear_(CPU *);void ov_info_(CPU *);void ov_pcm_total_(CPU *);void ov_seekable_(CPU *);void ov_read_(CPU *);
#else
static void ov_open_callbacks_(CPU *c) { fprintf(stderr, "[vorbis] ov_open_callbacks -> OV_ENOTVORBIS (not implemented yet)\n"); RET(c, (uint32_t)-132, 0); }
static void ov_clear_(CPU *c) { RET(c, 0, 0); }
static void ov_info_(CPU *c) { RET(c, 0, 0); }
static void ov_pcm_total_(CPU *c) { SETREG(c, R_EDX, 0); RET(c, 0, 0); }
static void ov_seekable_(CPU *c) { RET(c, 0, 0); }
static void ov_read_(CPU *c) { RET(c, 0, 0); }
#endif

const ShimTable media_shims = { (const Shim[]){
    {"_BinkSetSoundSystem@8", BinkSetSoundSystem_}, {"_BinkOpen@8", BinkOpen_}, {"_BinkOpenDirectSound@4", BinkOpenDirectSound_},
    {"_BinkClose@4", BinkClose_}, {"_BinkNextFrame@4", BinkNextFrame_}, {"_BinkWait@4", BinkWait_}, {"_BinkPause@8", BinkPause_},
    {"_BinkDoFrame@4", BinkDoFrame_}, {"_BinkCopyToBufferRect@44", BinkCopyToBufferRect_},
    {"ov_open_callbacks", ov_open_callbacks_}, {"ov_clear", ov_clear_}, {"ov_info", ov_info_}, {"ov_pcm_total", ov_pcm_total_},
    {"ov_seekable", ov_seekable_}, {"ov_read", ov_read_},
}, 15 };
