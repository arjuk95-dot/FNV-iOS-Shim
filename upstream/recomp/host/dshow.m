// DirectShow music graph. The game supplies a guest pull-source filter and calls
// Render(IPin), rather than RenderFile. Marshal its standard IAsyncReader ABI to
// native decoding; never depend on the private source object's memory layout.
#import <AVFoundation/AVFoundation.h>
#include <stdio.h>
#include "com.h"
#include <math.h>
extern int host_run_guest(CPU *, uint32_t);

@interface DSGraph : NSObject <AVAudioPlayerDelegate> {
@public
    uint32_t ifaces[8];
}
@property(nonatomic, strong) AVAudioPlayer *player;
@property(nonatomic, strong) NSData *encodedAudio;
@property(nonatomic, strong) NSMutableArray<NSNumber *> *filters;
@property(nonatomic) BOOL running, completed_reported, complete;
@property(nonatomic) unsigned state;
@property(nonatomic) long volume;
@property(nonatomic) long balance;
@property(nonatomic) uint32_t gid;
@end
@implementation DSGraph
- (void)audioPlayerDidFinishPlaying:(AVAudioPlayer *)player successfully:(BOOL)success {
    (void)success;
    @synchronized(self) { if (self.player == player && self.running) self.complete = YES; }
}
@end

static NSMutableDictionary<NSNumber *, DSGraph *> *graphs;
static uint32_t next_gid = 1;
static BOOL audioActive=YES;
void fnv_dshow_all_active(int active){
    @synchronized(DSGraph.class){audioActive=!!active;for(DSGraph *g in graphs.allValues){if(!active)[g.player pause];else if(g.running)[g.player play];}}
}
enum { I_GRAPH, I_CONTROL, I_EVENT, I_AUDIO, I_SEEKING, I_POSITION, I_COUNT };
static uint32_t vt[I_COUNT];

static DSGraph *G(CPU *c) { @synchronized(DSGraph.class){return graphs[@(G32(COM_DATA(COM_THIS(c))))];} }
static uint32_t iface(DSGraph *g, uint32_t gid, int which) {
    if (!g->ifaces[which]) {
        uint32_t o = com_new(vt[which], 4);
        P32(COM_DATA(o), gid);
        g->ifaces[which] = o;
    } else P32(g->ifaces[which] + 4, G32(g->ifaces[which] + 4) + 1);
    return g->ifaces[which];
}
static const uint8_t iid_tail[] = {0xd4,0x0a,0xce,0x11,0xb0,0x3a,0x00,0x20,0xaf,0x0b,0xa7,0x70};
static int iid_is(uint32_t p, uint32_t d1) { return p && p <= 0xfffffff0u && G32(p) == d1 && !memcmp(MEM+p+4,iid_tail,12); }
static int iid_seek(uint32_t p, uint32_t d1) {
    static const uint8_t tail[]={0xc8,0xc2,0xcf,0x11,0x8b,0x46,0x00,0x80,0x5f,0x6c,0xef,0x60};
    return p && p<=0xfffffff0u && G32(p)==d1 && !memcmp(MEM+p+4,tail,12);
}
static int which_iid(uint32_t iid) {
    static const uint8_t unknown[]={0,0,0,0,0,0,0,0,0xc0,0,0,0,0,0,0,0x46};
    if(!iid || iid>0xfffffff0u) return -1;
    if(!memcmp(MEM+iid,unknown,16) || iid_is(iid,0x56a8689f) || iid_is(iid,0x56a868a9))return I_GRAPH;
    if(iid_is(iid,0x56a868b1))return I_CONTROL;
    if(iid_is(iid,0x56a868b6) || iid_is(iid,0x56a868c0))return I_EVENT;
    if(iid_is(iid,0x56a868b3))return I_AUDIO;
    if(iid_seek(iid,0x36b73880))return I_SEEKING;
    if(iid_is(iid,0x56a868b2))return I_POSITION;
    return -1;
}

// Source callbacks execute on the calling guest thread, with its CPU and stack
// restored after every call. COM arguments include the 32-bit this pointer;
// SyncRead's LONGLONG is explicitly split into two x86 stack words.
static int guest_com(CPU *c,uint32_t object,unsigned slot,const uint32_t *args,unsigned n,uint32_t *value) {
    if(!object || object>0xfffffffcu || n>12 || REG(c,R_ESP)<128)return 0;
    uint32_t table=G32(object);
    if(!table || table>0xffffffffu-4*(slot+1))return 0;
    uint32_t target=G32(table+4*slot);if(!target)return 0;
    CPU saved=*c;uint32_t stack=REG(c,R_ESP)-128;
    uint32_t teb=REG(c,272),seh=teb&&teb<=0xfffffffcu?G32(teb):0;
    P32(stack,HOST_EXIT_THUNK);P32(stack+4,object);
    for(unsigned i=0;i<n;i++)P32(stack+8+4*i,args[i]);
    SETREG(c,R_ESP,stack);
    int trap=host_run_guest(c,target);uint32_t result=REG(c,R_EAX),returned=REG(c,R_ESP);
    *c=saved;
    // A trap longjmps out of translated code, bypassing its SEH epilogue.
    // Restore the outer exception-list head as well as the CPU registers.
    if(teb&&teb<=0xfffffffcu)P32(teb,seh);
    if(trap || returned!=stack+8+4*n){
        fprintf(stderr,"[dshow] guest COM callback failed target=%#x slot=%u trap=%d esp=%#x expected=%#x caller=%#x\n",target,slot,trap,returned,stack+8+4*n,G32(REG(c,R_ESP)));
        return 0;
    }
    if(value)*value=result;return 1;
}
static int guest_ref(CPU *c,uint32_t object,unsigned slot){return guest_com(c,object,slot,NULL,0,NULL);}

static void DS_QI(CPU *c) {
    uint32_t gid = G32(COM_DATA(COM_THIS(c))), iid = ARG(c, 1), out = ARG(c, 2);
    DSGraph *g = G(c);
    int which = which_iid(iid);
    if(!out){RET(c,0x80004003u,3);return;}
    if (which < 0 || !g) { fprintf(stderr, "[dshow] QueryInterface {%08x} -> E_NOINTERFACE\n", G32(iid)); P32(out, 0); RET(c, 0x80004002u, 3); return; }
    @synchronized(g){P32(out, iface(g, gid, which));}
    RET(c, 0, 3);
}
static void DS_AddRef(CPU *c) { DSGraph *g=G(c);uint32_t result=0;@synchronized(g){if(g){uint32_t p=COM_THIS(c);result=G32(p+4)+1;P32(p+4,result);}}RET(c,result,1); }
static void DS_Release(CPU *c) {
    DSGraph *g=G(c);uint32_t result=0;BOOL final=NO;
    @synchronized(g){if(g){uint32_t p=COM_THIS(c);result=G32(p+4);if(result)P32(p+4,--result);uint64_t all=0;for(int i=0;i<I_COUNT;i++)if(g->ifaces[i])all+=G32(g->ifaces[i]+4);final=!all;}}
    if(final){
        @synchronized(DSGraph.class){[graphs removeObjectForKey:@(g.gid)];}
        g.running=NO;g.state=0;g.player.delegate=nil;[g.player stop];
        for(NSNumber *filter in g.filters)guest_ref(c,filter.unsignedIntValue,2);
        for(int i=0;i<I_COUNT;i++)if(g->ifaces[i])gfree(g->ifaces[i]);
        fprintf(stderr,"[dshow] released graph=%u\n",g.gid);
    }
    RET(c,result,1);
}
#define OKN(n) static void ok##n(CPU *c) { RET(c, 0, (n) + 1); }
OKN(0) OKN(1) OKN(2) OKN(3) OKN(4) OKN(5) OKN(8)
static void notimpl1(CPU *c) { RET(c, 0x80004001u, 2); }

static void GB_AddFilter(CPU *c){
    DSGraph *g=G(c);uint32_t filter=ARG(c,1);uint32_t result=0x80004003u;
    if(g&&filter){if([g.filters containsObject:@(filter)])result=0x8004022du;else if(guest_ref(c,filter,1)){[g.filters addObject:@(filter)];result=0;}}
    RET(c,result,3);
}
static void GB_RemoveFilter(CPU *c){DSGraph *g=G(c);uint32_t filter=ARG(c,1),result=1;if([g.filters containsObject:@(filter)]){[g.filters removeObject:@(filter)];result=guest_ref(c,filter,2)?0:0x80004005u;}RET(c,result,2);}
static int prepare_player(DSGraph *g,AVAudioPlayer *player){
    if(!player || ![player prepareToPlay])return 0;
    g.player.delegate=nil;[g.player stop];g.player=player;player.delegate=g;
    player.volume=(float)pow(10.0,g.volume/2000.0);player.pan=(float)g.balance/10000.0f;
    g.running=NO;g.state=0;g.complete=NO;g.completed_reported=NO;return 1;
}
static void GB_Render(CPU *c){
    DSGraph *g=G(c);uint32_t pin=ARG(c,1),scratch=0,reader=0,result=0x80004005u,hr=0;
    static const uint8_t async_iid[]={0xaa,0x68,0xa8,0x56,0xd4,0x0a,0xce,0x11,0xb0,0x3a,0,0x20,0xaf,0x0b,0xa7,0x70};
    if(!g||!pin){RET(c,0x80004003u,2);return;}
    scratch=gmalloc(65536+64);if(!scratch){RET(c,0x8007000eu,2);return;}
    memcpy(MEM+scratch,async_iid,16);P32(scratch+16,0);
    uint32_t qi[]={scratch,scratch+16};
    if(!guest_com(c,pin,0,qi,2,&hr)||hr)goto done;
    reader=G32(scratch+16);if(!reader)goto done;
    memset(MEM+scratch+24,0,16);uint32_t lengths[]={scratch+24,scratch+32};
    if(!guest_com(c,reader,8,lengths,2,&hr)||hr)goto done;
    int64_t total,available;memcpy(&total,MEM+scratch+24,8);memcpy(&available,MEM+scratch+32,8);
    if(total<=0||total>64ll*1024*1024||available<total){result=0x80070057u;goto done;}
    {
        NSMutableData *bytes=[NSMutableData dataWithLength:(NSUInteger)total];
        for(uint64_t at=0;at<(uint64_t)total;){
            uint32_t count=(uint32_t)MIN((uint64_t)65536,(uint64_t)total-at);
            uint32_t read[]={ (uint32_t)at,(uint32_t)(at>>32),count,scratch+64 };
            if(!guest_com(c,reader,7,read,4,&hr)||hr)goto done;
            memcpy((uint8_t *)bytes.mutableBytes+at,MEM+scratch+64,count);at+=count;
        }
        NSError *error=nil;AVAudioPlayer *player=[[AVAudioPlayer alloc] initWithData:bytes error:&error];
        if(!prepare_player(g,player)){fprintf(stderr,"[dshow] Render(IAsyncReader) decode failed: %s\n",error.localizedDescription.UTF8String);goto done;}
        g.encodedAudio=bytes;result=0;
        fprintf(stderr,"[dshow] Render(IAsyncReader) bytes=%lld duration=%.3f graph=%u caller=%#x\n",(long long)total,player.duration,g.gid,G32(REG(c,R_ESP)));
    }
done:
    if(reader)guest_ref(c,reader,2);if(scratch)gfree(scratch);
    if(result)fprintf(stderr,"[dshow] Render(IAsyncReader) failed hr=%#x callback_hr=%#x pin=%#x caller=%#x\n",result,hr,pin,G32(REG(c,R_ESP)));
    RET(c,result,2);
}

// IGraphBuilder::RenderFile(LPCWSTR file, LPCWSTR playlist)
static void GB_RenderFile(CPU *c) {
    DSGraph *g = G(c);
    char wpath[1024], path[1024];
    w2a(ARG(c, 1), wpath, sizeof wpath);
    host_path(wpath, path, sizeof path);
    NSError *e = nil;
    AVAudioPlayer *player = [[AVAudioPlayer alloc] initWithContentsOfURL:[NSURL fileURLWithPath:[NSString stringWithUTF8String:path]] error:&e];
    if (!prepare_player(g,player)) { fprintf(stderr, "[dshow] RenderFile(%s): %s\n", path, e.localizedDescription.UTF8String); RET(c, 0x80040216u /* VFW_E_NOT_FOUND */, 3); return; }
    g.encodedAudio=nil;
    fprintf(stderr, "[dshow] RenderFile(%s) %.1fs\n", wpath, g.player.duration);
    RET(c, 0, 3);
}
// IMediaControl
static void MC_Run(CPU *c) { DSGraph *g = G(c);uint32_t result=0x80040209u;@synchronized(DSGraph.class){if(g.player){g.complete=NO;g.completed_reported=NO;result=(!audioActive||[g.player play])?0:0x80004005u;g.running=!result;g.state=result?0:2;}}RET(c,result,1); }
static void MC_Pause(CPU *c) { DSGraph *g = G(c); [g.player pause]; g.running = NO;g.state=1;RET(c, 0, 1); }
static void MC_Stop(CPU *c) { DSGraph *g = G(c); [g.player stop]; g.running = NO;g.state=0;g.complete=NO;g.completed_reported=NO;RET(c, 0, 1); }
static void MC_GetState(CPU *c) { DSGraph *g = G(c); P32(ARG(c, 2), g.state); RET(c, 0, 3); }
// IMediaEventEx: EC_COMPLETE once the track has played out
static void ME_GetEvent(CPU *c) {
    DSGraph *g = G(c);
    // Keep polling as a fallback for callers without a delegate-delivery run
    // loop. Run reports native play failures; Pause/suspension cannot complete.
    if (audioActive && g.running && g.player && (g.complete || !g.player.playing) && !g.completed_reported) {
        g.completed_reported = YES; g.complete = YES; g.running = NO;g.state=0;
        P32(ARG(c, 1), 1 /* EC_COMPLETE */); P32(ARG(c, 2), 0); P32(ARG(c, 3), 0);
        RET(c, 0, 5); return;
    }
    RET(c, 0x80004004u /* E_ABORT: no event */, 5);
}
static void ME_GetEventHandle(CPU *c) { P32(ARG(c, 1), 0); RET(c, 0, 2); }
static void ME_WaitForCompletion(CPU *c) { DSGraph *g = G(c); P32(ARG(c, 2), g.complete ? 1 : 0); RET(c, g.complete ? 0 : 0x80040213u /* VFW_E_TIMEOUT */, 3); }
// IBasicAudio: volume in 1/100 dB, -10000..0
static void BA_put_Volume(CPU *c) { DSGraph *g = G(c);long value=(int32_t)ARG(c,1);if(value>0||value< -10000){RET(c,0x80070057u,2);return;}g.volume=value;g.player.volume=(float)pow(10.0,value/2000.0);RET(c,0,2); }
static void BA_get_Volume(CPU *c) { P32(ARG(c, 1), (uint32_t)G(c).volume); RET(c, 0, 2); }
static void BA_put_Balance(CPU *c) { DSGraph *g=G(c);long value=(int32_t)ARG(c,1);if(value< -10000||value>10000){RET(c,0x80070057u,2);return;}g.balance=value;g.player.pan=(float)value/10000.0f;RET(c,0,2); }
static void BA_get_Balance(CPU *c) { P32(ARG(c, 1), (uint32_t)G(c).balance); RET(c, 0, 2); }
// IMediaSeeking (100 ns units)
static void put64(uint32_t p, int64_t v) { memcpy(MEM + p, &v, 8); }
static void MS_GetDuration(CPU *c) { put64(ARG(c, 1), (int64_t)(G(c).player.duration * 1e7)); RET(c, 0, 2); }
static void MS_GetCurrentPosition(CPU *c) { put64(ARG(c, 1), (int64_t)(G(c).player.currentTime * 1e7)); RET(c, 0, 2); }
static void MS_GetStopPosition(CPU *c) { put64(ARG(c, 1), (int64_t)(G(c).player.duration * 1e7)); RET(c, 0, 2); }
static void MS_SetPositions(CPU *c) {
    DSGraph *g = G(c);
    if (ARG(c, 1) && (ARG(c, 2) & 3)) { int64_t t; memcpy(&t, MEM + ARG(c, 1), 8); g.player.currentTime = (double)t / 1e7; g.complete = NO; g.completed_reported = NO; }
    RET(c, 0, 5);
}
static void MS_GetPositions(CPU *c) { if (ARG(c, 1)) put64(ARG(c, 1), (int64_t)(G(c).player.currentTime * 1e7)); if (ARG(c, 2)) put64(ARG(c, 2), (int64_t)(G(c).player.duration * 1e7)); RET(c, 0, 3); }
static void MS_GetCaps(CPU *c) { P32(ARG(c, 1), 0x1F); RET(c, 0, 2); }
static void MS_GetTimeFormat(CPU *c) { static const uint8_t TIME_FORMAT_MEDIA_TIME[16] = {0x70, 0xa6, 0x95, 0x7b, 0xc5, 0x84, 0xd0, 0x11, 0xa1, 0x18, 0x00, 0xa0, 0xc9, 0x05, 0x5e, 0x9e}; memcpy(MEM + ARG(c, 1), TIME_FORMAT_MEDIA_TIME, 16); RET(c, 0, 2); }
static void MS_GetRate(CPU *c) { double r = 1.0; memcpy(MEM + ARG(c, 1), &r, 8); RET(c, 0, 2); }
// IMediaPosition (seconds as double)
static void MP_get_Duration(CPU *c) { double d = G(c).player.duration; memcpy(MEM + ARG(c, 1), &d, 8); RET(c, 0, 2); }
static void MP_get_CurrentPosition(CPU *c) { double d = G(c).player.currentTime; memcpy(MEM + ARG(c, 1), &d, 8); RET(c, 0, 2); }
static void MP_put_CurrentPosition(CPU *c) { double d; uint32_t lo = ARG(c, 1), hi = ARG(c, 2); uint64_t b = ((uint64_t)hi << 32) | lo; memcpy(&d, &b, 8);if(!isfinite(d)||d<0){RET(c,0x80070057u,3);return;}DSGraph *g=G(c);g.player.currentTime=d;g.complete=NO;g.completed_reported=NO;RET(c,0,3); }

#define M(n, f, a) {n, f, a}
#define UNK M("QueryInterface", DS_QI, 2), M("AddRef", DS_AddRef, 0), M("Release", DS_Release, 0)
#define DISP M("GetTypeInfoCount", ok1, 1), M("GetTypeInfo", ok3, 3), M("GetIDsOfNames", ok5, 5), M("Invoke", ok8, 8)
static const ComMethod graph_m[] = {UNK, M("AddFilter", GB_AddFilter, 2), M("RemoveFilter", GB_RemoveFilter, 1), M("EnumFilters", notimpl1, 1),
    M("FindFilterByName", ok2, 2), M("ConnectDirect", ok3, 3), M("Reconnect", ok1, 1), M("Disconnect", ok1, 1),
    M("SetDefaultSyncSource", ok0, 0), M("Connect", ok2, 2), M("Render", GB_Render, 1), M("RenderFile", GB_RenderFile, 2),
    M("AddSourceFilter", ok3, 3), M("SetLogFile", ok1, 1), M("Abort", ok0, 0), M("ShouldOperationContinue", ok0, 0)};
static const ComMethod control_m[] = {UNK, DISP, M("Run", MC_Run, 0), M("Pause", MC_Pause, 0), M("Stop", MC_Stop, 0),
    M("GetState", MC_GetState, 2), M("RenderFile", ok1, 1), M("AddSourceFilter", ok2, 2), M("get_FilterCollection", ok1, 1),
    M("get_RegFilterCollection", ok1, 1), M("StopWhenReady", MC_Stop, 0)};
static const ComMethod event_m[] = {UNK, DISP, M("GetEventHandle", ME_GetEventHandle, 1), M("GetEvent", ME_GetEvent, 4),
    M("WaitForCompletion", ME_WaitForCompletion, 2), M("CancelDefaultHandling", ok1, 1), M("RestoreDefaultHandling", ok1, 1),
    M("FreeEventParams", ok3, 3), M("SetNotifyWindow", ok3, 3), M("SetNotifyFlags", ok1, 1), M("GetNotifyFlags", ok1, 1)};
static const ComMethod audio_m[] = {UNK, DISP, M("put_Volume", BA_put_Volume, 1), M("get_Volume", BA_get_Volume, 1),
    M("put_Balance", BA_put_Balance, 1), M("get_Balance", BA_get_Balance, 1)};
static const ComMethod seeking_m[] = {UNK, M("GetCapabilities", MS_GetCaps, 1), M("CheckCapabilities", ok1, 1),
    M("IsFormatSupported", ok1, 1), M("QueryPreferredFormat", MS_GetTimeFormat, 1), M("GetTimeFormat", MS_GetTimeFormat, 1),
    M("IsUsingTimeFormat", ok1, 1), M("SetTimeFormat", ok1, 1), M("GetDuration", MS_GetDuration, 1),
    M("GetStopPosition", MS_GetStopPosition, 1), M("GetCurrentPosition", MS_GetCurrentPosition, 1),
    M("ConvertTimeFormat", ok5, 5), M("SetPositions", MS_SetPositions, 4), M("GetPositions", MS_GetPositions, 2),
    M("GetAvailable", ok2, 2), M("SetRate", ok2, 2), M("GetRate", MS_GetRate, 1), M("GetPreroll", ok1, 1)};
static const ComMethod position_m[] = {UNK, DISP, M("get_Duration", MP_get_Duration, 1), M("put_CurrentPosition", MP_put_CurrentPosition, 2),
    M("get_CurrentPosition", MP_get_CurrentPosition, 1), M("get_StopTime", MP_get_Duration, 1), M("put_StopTime", ok2, 2),
    M("get_PrerollTime", ok1, 1), M("put_PrerollTime", ok2, 2), M("put_Rate", ok2, 2), M("get_Rate", MS_GetRate, 1),
    M("CanSeekForward", ok1, 1), M("CanSeekBackward", ok1, 1)};

// called by the CoCreateInstance shim for CLSID_FilterGraph
uint32_t dshow_create_filtergraph(uint32_t iid) {
    int which=which_iid(iid);if(which<0)return 0;
    @synchronized(DSGraph.class){
    if (!graphs) {
        graphs = [NSMutableDictionary dictionary];
#define V(i, m) vt[i] = com_vtable(#m, m, (int)(sizeof m / sizeof *m))
        V(I_GRAPH, graph_m); V(I_CONTROL, control_m); V(I_EVENT, event_m); V(I_AUDIO, audio_m); V(I_SEEKING, seeking_m); V(I_POSITION, position_m);
    }
    uint32_t gid = next_gid++;
    DSGraph *g = [DSGraph new];
    g.volume = 0;g.filters=[NSMutableArray new];g.gid=gid;
    graphs[@(gid)] = g;
    return iface(g, gid, which);
    }
}
