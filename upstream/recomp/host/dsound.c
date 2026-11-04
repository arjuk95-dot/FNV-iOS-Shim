// DirectSound8 PCM storage/cursors with native audio output. Guest callbacks never run on the audio thread.
#include <stdio.h>
#include <stdlib.h>
#include <time.h>
#include <pthread.h>
#include "com.h"
#include "FNVNativeMedia.h"

static uint32_t vt_ds, vt_buf, vt_3dbuf, vt_listener;

// buffer instance data (after the 12-byte COM header)
enum { B_SIZE = 0, B_DATA = 4, B_BPS = 8, B_FLAGS = 12, B_PLAYING = 16, B_LOOP = 20, B_T0LO = 24, B_T0HI = 28,
       B_POS = 32, B_FMT = 36 /* 20-byte WAVEFORMATEX copy */, B_VOICE=56,B_VOLUME=60,B_PAN=64,B_FREQUENCY=68,
       B_SPATIAL=72,B_LISTENER=76,B_GROUPS=80,B_END=84 };

static uint64_t now_ns(void) { return clock_gettime_nsec_np(CLOCK_UPTIME_RAW); }

static uint32_t play_cursor(uint32_t b) {
    uint32_t d = COM_DATA(b), size = G32(d + B_SIZE);
    uint32_t voice=G32(d+B_VOICE);
    if(voice){int playing,loop;uint32_t cursor=fnv_audio_voice_cursor(voice,&playing,&loop);P32(d+B_PLAYING,playing);P32(d+B_LOOP,loop);return cursor;}
    if (!size) return 0;
    if (!G32(d + B_PLAYING)) return G32(d + B_POS) % size;
    uint64_t t0 = ((uint64_t)G32(d + B_T0HI) << 32) | G32(d + B_T0LO);
    uint64_t bytes = (now_ns() - t0) * G32(d + B_BPS) / 1000000000ull + G32(d + B_POS);
    if (!G32(d + B_LOOP) && bytes >= size) { P32(d + B_PLAYING, 0); P32(d + B_POS, 0); return 0; }
    return (uint32_t)(bytes % size);
}

#define DS_IID(first) {first,0xfa,0x9a,0x27,0x81,0x49,0xce,0x11,0xa5,0x21,0,0x20,0xaf,0x0b,0xe5,0x60}
static const uint8_t IID_3DBUFFER[16]=DS_IID(0x86),IID_3DLISTENER[16]=DS_IID(0x84),IID_BUFFER[16]=DS_IID(0x85),IID_DS[16]=DS_IID(0x83);
static const uint8_t IID_BUFFER8[16]={0x49,0xa4,0x25,0x68,0x24,0x75,0x82,0x4d,0x92,0x0f,0x50,0xe3,0x6a,0xb3,0xab,0x1e};
static const uint8_t IID_DS8[16]={0x93,0x7e,0x0a,0xc5,0x95,0xf3,0x34,0x48,0x9e,0xf6,0x7f,0xa9,0x9d,0xe5,0x09,0x66};
static const uint8_t IID_UNKNOWN[16]={0,0,0,0,0,0,0,0,0xc0,0,0,0,0,0,0,0x46};
static int iid_is(uint32_t iid,const uint8_t *expected){return iid&&!memcmp(MEM+iid,expected,16);}
static pthread_mutex_t sound_lifetime_lock=PTHREAD_MUTEX_INITIALIZER;
// Each interface has its own externally visible count. The shared backing owner
// survives until every interface count is zero, independently of duplicate PCM owners.
static uint32_t buffer_owner(uint32_t o){return G32(o)==vt_buf?o:G32(COM_DATA(o));}
static uint32_t interface_addref_locked(uint32_t o){
    uint32_t b=buffer_owner(o),r=G32(o+4);
    if(!r)P32(COM_DATA(b)+B_GROUPS,G32(COM_DATA(b)+B_GROUPS)+1);
    P32(o+4,r+1);return r+1;
}
static void buffer_destroy_locked(uint32_t b,uint32_t caller){
    uint32_t d=COM_DATA(b),spatial=G32(d+B_SPATIAL),listener=G32(d+B_LISTENER),voice=G32(d+B_VOICE),data=G32(d+B_DATA);
    static unsigned reported;
    if(reported++<16)fprintf(stderr,"[audio-lifetime] destroy owner=%#x spatial=%#x listener=%#x voice=%u caller=%#x\n",b,spatial,listener,voice,caller);
    if(fnv_audio_voice_destroy(voice)&&data)gfree(data);
    if(spatial)gfree(spatial);if(listener)gfree(listener);gfree(b);
}
static uint32_t interface_release_locked(uint32_t o,uint32_t caller){
    uint32_t r=G32(o+4);if(!r)return 0;
    uint32_t b=buffer_owner(o);P32(o+4,--r);
    if(!r){uint32_t d=COM_DATA(b),groups=G32(d+B_GROUPS);P32(d+B_GROUPS,--groups);if(!groups)buffer_destroy_locked(b,caller);}
    return r;
}
static void Sound_AddRef(CPU *c){pthread_mutex_lock(&sound_lifetime_lock);uint32_t r=interface_addref_locked(COM_THIS(c));pthread_mutex_unlock(&sound_lifetime_lock);RET(c,r,1);}
static void Sound_Release(CPU *c){pthread_mutex_lock(&sound_lifetime_lock);uint32_t r=interface_release_locked(COM_THIS(c),G32(REG(c,R_ESP)));pthread_mutex_unlock(&sound_lifetime_lock);RET(c,r,1);}
static uint32_t buffer_query_locked(uint32_t b,uint32_t iid,uint32_t out,uint32_t caller){
    P32(out,0);uint32_t o=0,d=COM_DATA(b),flags=G32(d+B_FLAGS);
    if(iid_is(iid,IID_UNKNOWN)||iid_is(iid,IID_BUFFER)||iid_is(iid,IID_BUFFER8))o=b;
    else if((iid_is(iid,IID_3DBUFFER)&&!(flags&1)&&(flags&0x10)) || (iid_is(iid,IID_3DLISTENER)&&(flags&1))){
        int listener=iid_is(iid,IID_3DLISTENER);uint32_t field=listener?B_LISTENER:B_SPATIAL;
        o=G32(d+field);
        if(!o){o=com_new(listener?vt_listener:vt_3dbuf,4);P32(o+4,0);P32(COM_DATA(o),b);P32(d+field,o);}
    }
    if(!o){static unsigned rejected;if(rejected++<16)fprintf(stderr,"[audio-qi] unsupported iid=%08x-%08x-%08x-%08x owner=%#x caller=%#x\n",G32(iid),G32(iid+4),G32(iid+8),G32(iid+12),b,caller);return 0x80004002u;}
    interface_addref_locked(o);P32(out,o);return 0;
}
static void Buf_QueryInterface(CPU *c){
    pthread_mutex_lock(&sound_lifetime_lock);uint32_t hr=buffer_query_locked(COM_THIS(c),ARG(c,1),ARG(c,2),G32(REG(c,R_ESP)));pthread_mutex_unlock(&sound_lifetime_lock);RET(c,hr,3);
}
static void Buf_GetCaps(CPU *c) { uint32_t p = ARG(c, 1), d = COM_DATA(COM_THIS(c)); P32(p + 4, G32(d + B_FLAGS)); P32(p + 8, G32(d + B_SIZE)); P32(p + 12, 0); P32(p + 16, 0); RET(c, 0, 2); }
static void Buf_GetCurrentPosition(CPU *c) {
    uint32_t pc = play_cursor(COM_THIS(c)), size = G32(COM_DATA(COM_THIS(c)) + B_SIZE);
    if (ARG(c, 1)) P32(ARG(c, 1), pc);
    if (ARG(c, 2)) P32(ARG(c, 2), size ? (pc + G32(COM_DATA(COM_THIS(c)) + B_BPS) / 50) % size : 0);  // write cursor ~20 ms ahead
    RET(c, 0, 3);
}
static void Buf_GetFormat(CPU *c) {
    uint32_t d = COM_DATA(COM_THIS(c)), out = ARG(c, 1), n = ARG(c, 2);
    if (out) memcpy(MEM + out, MEM + d + B_FMT, n < 18 ? n : 18);
    if (ARG(c, 3)) P32(ARG(c, 3), 18);
    RET(c, 0, 4);
}
static void Buf_GetStatus(CPU *c) { play_cursor(COM_THIS(c)); uint32_t d = COM_DATA(COM_THIS(c)); P32(ARG(c, 1), G32(d + B_PLAYING) ? (1 | (G32(d + B_LOOP) ? 4 : 0)) : 0); RET(c, 0, 2); }
static void Buf_Lock(CPU *c) {
    uint32_t d = COM_DATA(COM_THIS(c)), size = G32(d + B_SIZE), data = G32(d + B_DATA);
    uint32_t off = ARG(c, 1), n = ARG(c, 2), flags = ARG(c, 7);
    if (flags & 2) n = size;                       // DSBLOCK_ENTIREBUFFER
    if (flags & 1) off = play_cursor(COM_THIS(c)); // DSBLOCK_FROMWRITECURSOR (approximately)
    if (!size) { RET(c, 0x80070057u, 8); return; }
    off %= size; if (n > size) n = size;
    uint32_t first = off + n <= size ? n : size - off;
    P32(ARG(c, 3), data + off); P32(ARG(c, 4), first);
    if (ARG(c, 5)) P32(ARG(c, 5), first < n ? data : 0);
    if (ARG(c, 6)) P32(ARG(c, 6), n - first);
    RET(c, 0, 8);
}
static void Buf_Play(CPU *c) {
    uint32_t d = COM_DATA(COM_THIS(c)); uint64_t t = now_ns();
    play_cursor(COM_THIS(c));
    uint32_t voice=G32(d+B_VOICE);
    if(voice){if(!G32(d+B_PLAYING))fnv_audio_voice_write(voice,0,MEM+G32(d+B_DATA),G32(d+B_SIZE));fnv_audio_voice_play(voice,ARG(c,3)&1);}
    if (!G32(d + B_PLAYING)) { P32(d + B_T0LO, (uint32_t)t); P32(d + B_T0HI, (uint32_t)(t >> 32)); }
    P32(d + B_PLAYING, 1); P32(d + B_LOOP, ARG(c, 3) & 1);
    RET(c, 0, 4);
}
static void Buf_Stop(CPU *c) { uint32_t b = COM_THIS(c), d = COM_DATA(b); P32(d + B_POS, play_cursor(b));fnv_audio_voice_stop(G32(d+B_VOICE)); P32(d + B_PLAYING, 0); RET(c, 0, 1); }
static void Buf_SetCurrentPosition(CPU *c) {
    uint32_t d = COM_DATA(COM_THIS(c)); uint64_t t = now_ns();
    P32(d + B_POS, ARG(c, 1)); P32(d + B_T0LO, (uint32_t)t); P32(d + B_T0HI, (uint32_t)(t >> 32));
    fnv_audio_voice_seek(G32(d+B_VOICE),ARG(c,1));
    RET(c, 0, 2);
}
static void Buf_SetFormat(CPU *c) { uint32_t d = COM_DATA(COM_THIS(c));if(G32(d+B_VOICE)){RET(c,0x80070057u,2);return;}memcpy(MEM + d + B_FMT, MEM + ARG(c, 1), 18);P32(d+B_BPS,G32(ARG(c,1)+8));P32(d+B_FREQUENCY,G32(ARG(c,1)+4));RET(c,0,2); }
static void Buf_GetVolume(CPU *c){P32(ARG(c,1),G32(COM_DATA(COM_THIS(c))+B_VOLUME));RET(c,0,2);}
static void Buf_GetPan(CPU *c){P32(ARG(c,1),G32(COM_DATA(COM_THIS(c))+B_PAN));RET(c,0,2);}
static void Buf_GetFrequency(CPU *c) {uint32_t d=COM_DATA(COM_THIS(c));P32(ARG(c,1),G32(d+B_FREQUENCY));RET(c,0,2);}
static void Buf_SetVolume(CPU *c){uint32_t d=COM_DATA(COM_THIS(c));int value=(int32_t)ARG(c,1);P32(d+B_VOLUME,value);if(G32(d+B_FLAGS)&1)fnv_audio_master_volume(value);else fnv_audio_voice_volume(G32(d+B_VOICE),value);RET(c,0,2);}
static void Buf_SetPan(CPU *c){uint32_t d=COM_DATA(COM_THIS(c));int value=(int32_t)ARG(c,1);P32(d+B_PAN,value);fnv_audio_voice_pan(G32(d+B_VOICE),value);RET(c,0,2);}
static void Buf_SetFrequency(CPU *c){uint32_t d=COM_DATA(COM_THIS(c)),hz=ARG(c,1);if(!hz)hz=G32(d+B_FMT+4);P32(d+B_FREQUENCY,hz);fnv_audio_voice_frequency(G32(d+B_VOICE),hz);RET(c,0,2);}
static void Buf_Unlock(CPU *c){
    uint32_t d=COM_DATA(COM_THIS(c)),voice=G32(d+B_VOICE),base=G32(d+B_DATA),size=G32(d+B_SIZE);
    for(int i=0;i<2;i++){uint32_t p=ARG(c,1+2*i),n=ARG(c,2+2*i);if(p>=base&&p-base<size&&n<=size-(p-base))fnv_audio_voice_write(voice,p-base,MEM+p,n);}
    RET(c,0,5);
}
static void Buf_Release(CPU *c){
    Sound_Release(c);
}
COM_STUB_OK(Buf_Restore, 0)
COM_STUB_OK(Buf_Initialize, 2)
static void Buf_SetFX(CPU *c) { RET(c, 0, 4); }

static const ComMethod buf_methods[] = {
    {"QueryInterface", Buf_QueryInterface, 2}, {"AddRef", Sound_AddRef, 0}, {"Release", Buf_Release, 0},
    {"GetCaps", Buf_GetCaps, 1}, {"GetCurrentPosition", Buf_GetCurrentPosition, 2}, {"GetFormat", Buf_GetFormat, 3},
    {"GetVolume", Buf_GetVolume, 1}, {"GetPan", Buf_GetPan, 1}, {"GetFrequency", Buf_GetFrequency, 1},
    {"GetStatus", Buf_GetStatus, 1}, {"Initialize", Buf_Initialize, 2}, {"Lock", Buf_Lock, 7},
    {"Play", Buf_Play, 3}, {"SetCurrentPosition", Buf_SetCurrentPosition, 1}, {"SetFormat", Buf_SetFormat, 1},
    {"SetVolume", Buf_SetVolume, 1}, {"SetPan", Buf_SetPan, 1}, {"SetFrequency", Buf_SetFrequency, 1}, {"Stop", Buf_Stop, 0},
    {"Unlock", Buf_Unlock, 4}, {"Restore", Buf_Restore, 0}, {"SetFX", Buf_SetFX, 3},
    {"AcquireResources", NULL, 3}, {"GetObjectInPath", NULL, 4},
};

// IDirectSound3DBuffer / IDirectSound3DListener: positional parameters are accepted and dropped
static void S3D_QI(CPU *c){
    pthread_mutex_lock(&sound_lifetime_lock);uint32_t hr=buffer_query_locked(buffer_owner(COM_THIS(c)),ARG(c,1),ARG(c,2),G32(REG(c,R_ESP)));pthread_mutex_unlock(&sound_lifetime_lock);RET(c,hr,3);
}
static void S3D_Release(CPU *c){Sound_Release(c);}
#define S3(n, k) static void n(CPU *c) { RET(c, 0, (k) + 1); }
S3(S3_1, 1) S3(S3_2, 2) S3(S3_3, 3) S3(S3_4, 4) S3(S3_7, 7) S3(S3_0, 0)
static void S3_GetZero(CPU *c) { if (ARG(c, 1)) memset(MEM + ARG(c, 1), 0, 4); RET(c, 0, 2); }
static const ComMethod buf3d_methods[] = {
    {"QueryInterface", S3D_QI, 2}, {"AddRef", Sound_AddRef, 0}, {"Release", S3D_Release, 0},
    {"GetAllParameters", S3_1, 1}, {"GetConeAngles", S3_2, 2}, {"GetConeOrientation", S3_1, 1},
    {"GetConeOutsideVolume", S3_GetZero, 1}, {"GetMaxDistance", S3_GetZero, 1}, {"GetMinDistance", S3_GetZero, 1},
    {"GetMode", S3_GetZero, 1}, {"GetPosition", S3_1, 1}, {"GetVelocity", S3_1, 1}, {"SetAllParameters", S3_2, 2},
    {"SetConeAngles", S3_3, 3}, {"SetConeOrientation", S3_4, 4}, {"SetConeOutsideVolume", S3_2, 2},
    {"SetMaxDistance", S3_2, 2}, {"SetMinDistance", S3_2, 2}, {"SetMode", S3_2, 2}, {"SetPosition", S3_4, 4},
    {"SetVelocity", S3_4, 4},
};
static const ComMethod listener_methods[] = {
    {"QueryInterface", S3D_QI, 2}, {"AddRef", Sound_AddRef, 0}, {"Release", S3D_Release, 0},
    {"GetAllParameters", S3_1, 1}, {"GetDistanceFactor", S3_GetZero, 1}, {"GetDopplerFactor", S3_GetZero, 1},
    {"GetOrientation", S3_2, 2}, {"GetPosition", S3_1, 1}, {"GetRolloffFactor", S3_GetZero, 1},
    {"GetVelocity", S3_1, 1}, {"SetAllParameters", S3_2, 2}, {"SetDistanceFactor", S3_2, 2},
    {"SetDopplerFactor", S3_2, 2}, {"SetOrientation", S3_7, 7}, {"SetPosition", S3_4, 4},
    {"SetRolloffFactor", S3_2, 2}, {"SetVelocity", S3_4, 4}, {"CommitDeferredSettings", S3_0, 0},
};

// ---- IDirectSound8 ----------------------------------------------------------------------------
static void DS_CreateSoundBuffer(CPU *c) {
    uint32_t desc = ARG(c, 1), flags = G32(desc + 4), size = G32(desc + 8), wfx = G32(desc + 16);
    if(!(flags&1)&&(!size||!wfx)){P32(ARG(c,2),0);RET(c,0x80070057u,4);return;}
    uint32_t b = com_new(vt_buf, B_END);
    uint32_t d = COM_DATA(b);
    P32(d+B_GROUPS,1);
    P32(d + B_SIZE, size); P32(d + B_DATA, size ? gmalloc(size) : 0); P32(d + B_FLAGS, flags);
    if (wfx) { memcpy(MEM + d + B_FMT, MEM + wfx, 18); P32(d + B_BPS, G32(wfx + 8)); }
    else { P32(d + B_BPS, 44100 * 4); }
    if(size&&wfx){
        unsigned format=(unsigned)LD(MEM+wfx,2),channels=(unsigned)LD(MEM+wfx+2,2),rate=G32(wfx+4),bits=(unsigned)LD(MEM+wfx+14,2);
        uint32_t voice=fnv_audio_voice_create(size,channels,rate,bits,format);
        if(!voice){fprintf(stderr,"[audio] unsupported buffer format=%u channels=%u rate=%u bits=%u bytes=%u caller=%#x\n",format,channels,rate,bits,size,G32(REG(c,R_ESP)));gfree(G32(d+B_DATA));gfree(b);P32(ARG(c,2),0);RET(c,0x80070057u,4);return;}
        P32(d+B_VOICE,voice);P32(d+B_FREQUENCY,rate);
        if(format==1&&bits==8)memset(MEM+G32(d+B_DATA),128,size);
        static unsigned reported;if(reported++<16)fprintf(stderr,"[audio] PCM buffer voice=%u %uch %uHz %ubit bytes=%u\n",voice,channels,rate,bits,size);
    }
    P32(ARG(c, 2), b);
    RET(c, 0, 4);
}
static void DS_GetCaps(CPU *c) { uint32_t p = ARG(c, 1), n = G32(p); memset(MEM + p + 4, 0, n > 4 ? n - 4 : 0); RET(c, 0, 2); }
static void DS_GetSpeakerConfig(CPU *c) { P32(ARG(c, 1), 4 /* stereo */); RET(c, 0, 2); }
static void DS_Duplicate(CPU *c) {
    uint32_t src = ARG(c, 1), b = com_new(vt_buf, B_END);
    memcpy(MEM + COM_DATA(b), MEM + COM_DATA(src), B_END);
    P32(COM_DATA(b)+B_SPATIAL,0);P32(COM_DATA(b)+B_LISTENER,0);P32(COM_DATA(b)+B_GROUPS,1);
    uint32_t old_voice=G32(COM_DATA(src)+B_VOICE),voice=fnv_audio_voice_duplicate(old_voice);
    if(old_voice&&!voice){gfree(b);P32(ARG(c,2),0);RET(c,0x8007000eu,3);return;}
    P32(COM_DATA(b)+B_VOICE,voice);
    P32(COM_DATA(b) + B_PLAYING, 0); P32(COM_DATA(b) + B_POS, 0);
    P32(ARG(c, 2), b); RET(c, 0, 3);
}
static void DS_QI(CPU *c) {uint32_t iid=ARG(c,1),o=COM_THIS(c);if(iid_is(iid,IID_DS)||iid_is(iid,IID_DS8)||iid_is(iid,IID_UNKNOWN)){P32(o+4,G32(o+4)+1);P32(ARG(c,2),o);RET(c,0,3);}else{P32(ARG(c,2),0);RET(c,0x80004002u,3);}}
COM_STUB_OK(DS_SetCooperativeLevel, 2)
COM_STUB_OK(DS_Compact, 0)
COM_STUB_OK(DS_SetSpeakerConfig, 1)
COM_STUB_OK(DS_Initialize, 1)
COM_STUB_OK(DS_VerifyCertification, 1)

static const ComMethod ds_methods[] = {
    {"QueryInterface", DS_QI, 2}, {"AddRef", com_AddRef, 0}, {"Release", com_Release, 0},
    {"CreateSoundBuffer", DS_CreateSoundBuffer, 3}, {"GetCaps", DS_GetCaps, 1},
    {"DuplicateSoundBuffer", DS_Duplicate, 2}, {"SetCooperativeLevel", DS_SetCooperativeLevel, 2},
    {"Compact", DS_Compact, 0}, {"GetSpeakerConfig", DS_GetSpeakerConfig, 1},
    {"SetSpeakerConfig", DS_SetSpeakerConfig, 1}, {"Initialize", DS_Initialize, 1},
    {"VerifyCertification", DS_VerifyCertification, 1},
};

static void DirectSoundCreate8_(CPU *c) {
    if (!vt_ds) {
        vt_ds = com_vtable("IDirectSound8", ds_methods, (int)(sizeof ds_methods / sizeof *ds_methods));
        vt_buf = com_vtable("IDirectSoundBuffer8", buf_methods, (int)(sizeof buf_methods / sizeof *buf_methods));
        vt_3dbuf = com_vtable("IDirectSound3DBuffer", buf3d_methods, (int)(sizeof buf3d_methods / sizeof *buf3d_methods));
        vt_listener = com_vtable("IDirectSound3DListener", listener_methods, (int)(sizeof listener_methods / sizeof *listener_methods));
    }
    P32(ARG(c, 1), com_new(vt_ds, 0));
    fprintf(stderr, "[dsound] DirectSoundCreate8 -> native PCM device, output_ready=%d\n",fnv_audio_start());
    RET(c, 0, 3);
}

const ShimTable dsound_shims = { (const Shim[]){ {"dsound#11", DirectSoundCreate8_}, {"DirectSoundCreate8", DirectSoundCreate8_} }, 2 };
