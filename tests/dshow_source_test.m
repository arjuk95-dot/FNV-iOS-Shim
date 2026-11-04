// An authored pull-source exercises the same AddFilter/Render(IPin) sequence as
// the original game. It never supplies commercial audio or private game code.
#ifndef FNV_DSHOW_SOURCE
#define FNV_DSHOW_SOURCE "../upstream/recomp/host/dshow.m"
#endif
#include FNV_DSHOW_SOURCE
#include <assert.h>
#include <unistd.h>

uint8_t *MEM;HostImport host_imports[MAX_IMPORTS];int host_import_count;
static uint32_t heap=0x100000;static unsigned freed;
uint32_t gmalloc(uint32_t n){uint32_t p=heap;heap=(heap+n+15)&~15u;assert(heap<16u*1024*1024);memset(MEM+p,0,n);return p;}
void gfree(uint32_t p){if(p)freed++;}
void rt_trap(CPU *c,int n,uint32_t a){(void)c;(void)n;(void)a;abort();}
void host_path(const char *win,char *out,size_t n){snprintf(out,n,"%s",win);}
void w2a(uint32_t p,char *out,size_t n){size_t i=0;while(i+1<n){uint16_t w;memcpy(&w,MEM+p+2*i,2);if(!w)break;out[i++]=(char)w;}out[i]=0;}

static uint32_t filter,pin,reader;static unsigned filterRefs=1,readerRefs;
static NSData *tone;static unsigned reads,lengthCalls,queries;static int failRead,badPop,trapRead,hugeLength,unavailable;
static const uint8_t asyncIID[]={0xaa,0x68,0xa8,0x56,0xd4,0x0a,0xce,0x11,0xb0,0x3a,0,0x20,0xaf,0x0b,0xa7,0x70};
static void source_QI(CPU *c){queries++;assert(ARG(c,0)==pin);uint32_t out=ARG(c,2);if(!memcmp(MEM+ARG(c,1),asyncIID,16)){P32(out,reader);readerRefs++;RET(c,0,3);}else{P32(out,0);RET(c,0x80004002u,3);}}
static void source_AddRef(CPU *c){assert(ARG(c,0)==filter);RET(c,++filterRefs,1);}
static void source_Release(CPU *c){uint32_t object=ARG(c,0);if(object==filter){assert(filterRefs);RET(c,--filterRefs,1);}else{assert(object==reader&&readerRefs);RET(c,--readerRefs,1);}}
static void source_Length(CPU *c){assert(ARG(c,0)==reader);lengthCalls++;int64_t total=hugeLength?((int64_t)1<<40):(int64_t)tone.length,available=unavailable?total-1:total;memcpy(MEM+ARG(c,1),&total,8);memcpy(MEM+ARG(c,2),&available,8);RET(c,0,3);}
static void source_Read(CPU *c){
    assert(ARG(c,0)==reader);uint64_t offset=(uint64_t)ARG(c,1)|((uint64_t)ARG(c,2)<<32);uint32_t count=ARG(c,3),out=ARG(c,4);reads++;
    if(failRead){RET(c,0x80004005u,5);return;}
    assert(offset+count<=tone.length&&count<=65536);memcpy(MEM+out,(const uint8_t*)tone.bytes+offset,count);RET(c,0,5);
}
static void source_unused(CPU *c){(void)c;abort();}
int host_run_guest(CPU *c,uint32_t target){
    assert(target>=IMPORT_THUNK_BASE&&((target-IMPORT_THUNK_BASE)&3)==0);unsigned i=(target-IMPORT_THUNK_BASE)/4;assert(i<(unsigned)host_import_count);
    // Emulate an exception registration left on the callback stack when a
    // translated frame traps before executing its normal FS:[0] epilogue.
    P32(REG(c,272),0xdeadff00);
    if(trapRead&&host_imports[i].fn==source_Read){trapRead=0;return 6;}
    host_imports[i].fn(c);uint32_t result=REG(c,R_EAX),stack=REG(c,R_ESP);
    if(badPop&&host_imports[i].fn==source_Read)stack-=4;
    // Every other register/flag/XMM/x87 byte is deliberately clobbered. The
    // production callback bridge must restore the complete outer CPU snapshot.
    memset(c,0xa5,sizeof *c);SETREG(c,R_EAX,result);SETREG(c,R_ESP,stack);return 0;
}
static uint32_t call(uint32_t object,unsigned slot,const uint32_t *args,unsigned n){
    CPU c;memset(&c,0x35,sizeof c);SETREG(&c,R_ESP,0x80000);SETREG(&c,272,0x70000);CPU expected=c;P32(0x70000,0x70010);P32(0x80000,0xabcdef);P32(0x80004,object);
    for(unsigned i=0;i<n;i++)P32(0x80008+4*i,args[i]);uint32_t target=G32(G32(object)+4*slot);
    assert(target>=IMPORT_THUNK_BASE);host_imports[(target-IMPORT_THUNK_BASE)/4].fn(&c);
    SETREG(&expected,R_EAX,REG(&c,R_EAX));SETREG(&expected,R_ESP,0x80008+4*n);
    assert(!memcmp(&c,&expected,sizeof c));assert(G32(0x70000)==0x70010);return REG(&c,R_EAX);
}
#define CALL(o,s,...) call(o,s,(uint32_t[]){__VA_ARGS__},sizeof((uint32_t[]){__VA_ARGS__})/4)
static unsigned failed;
static void check(const char *name,int ok){printf("%s: %s\n",ok?"PASS":"FAIL",name);failed+=!ok;}
static uint32_t guid(uint32_t first,const uint8_t *tail){uint32_t p=gmalloc(16);P32(p,first);memcpy(MEM+p+4,tail,12);return p;}
static uint32_t standard(uint32_t first){static const uint8_t tail[]={0xd4,0x0a,0xce,0x11,0xb0,0x3a,0,0x20,0xaf,0x0b,0xa7,0x70};return guid(first,tail);}
static uint32_t query(uint32_t object,uint32_t iid){uint32_t out=gmalloc(4);assert(CALL(object,0,iid,out)==0);return G32(out);}
static uint32_t graph(void){return dshow_create_filtergraph(standard(0x56a8689f));}
static NSData *make_tone(void){
    const uint32_t samples=24000,bytes=samples*4;NSMutableData *wav=[NSMutableData dataWithLength:44+bytes];uint8_t *p=wav.mutableBytes;
    memcpy(p,"RIFF",4);uint32_t x=36+bytes;memcpy(p+4,&x,4);memcpy(p+8,"WAVEfmt ",8);x=16;memcpy(p+16,&x,4);
    uint16_t w=1;memcpy(p+20,&w,2);w=2;memcpy(p+22,&w,2);x=48000;memcpy(p+24,&x,4);x=192000;memcpy(p+28,&x,4);w=4;memcpy(p+32,&w,2);w=16;memcpy(p+34,&w,2);memcpy(p+36,"data",4);x=bytes;memcpy(p+40,&x,4);
    for(unsigned i=0;i<samples;i++){int16_t v=(int16_t)(sin(2*M_PI*440*i/48000.0)*10000);memcpy(p+44+i*4,&v,2);memcpy(p+46+i*4,&v,2);}return wav;
}
static void sources(void){
    static const ComMethod fm[]={{"QI",source_unused,2},{"AddRef",source_AddRef,0},{"Release",source_Release,0}};
    static const ComMethod pm[]={{"QI",source_QI,2},{"AddRef",source_unused,0},{"Release",source_unused,0}};
    static const ComMethod rm[]={{"QI",source_unused,2},{"AddRef",source_unused,0},{"Release",source_Release,0},{"RequestAllocator",source_unused,3},{"Request",source_unused,2},{"WaitForNext",source_unused,3},{"SyncReadAligned",source_unused,1},{"SyncRead",source_Read,4},{"Length",source_Length,2},{"BeginFlush",source_unused,0},{"EndFlush",source_unused,0}};
    filter=com_new(com_vtable("AuthoredFilter",fm,3),0);pin=com_new(com_vtable("AuthoredPin",pm,3),0);reader=com_new(com_vtable("AuthoredReader",rm,11),0);
}
int main(int argc,char **argv){@autoreleasepool{
    assert(argc==2);MEM=calloc(1,16u*1024*1024);tone=make_tone();sources();const char *mode=argv[1];uint32_t g=graph();assert(g);
    if(!strcmp(mode,"source-render")){
        check("AddFilter retains guest filter",CALL(g,3,filter,0)==0&&filterRefs==2);
        check("Render pulls and decodes the standard guest reader",CALL(g,12,pin)==0&&queries==1&&lengthCalls==1&&reads==2&&readerRefs==0);
        DSGraph *native=graphs[@(G32(COM_DATA(g)))];
#ifdef FNV_DSHOW_REFERENCE
        check("native decoded duration matches authored source",native.player&&fabs(native.player.duration-0.5)<0.001);
#else
        check("native decoded duration and bytes match authored source",native.player&&fabs(native.player.duration-0.5)<0.001&&native.encodedAudio.length==tone.length);
#endif
        check("final graph release drops filter reference",CALL(g,2)==0&&filterRefs==1&&graphs.count==0);
#ifndef FNV_DSHOW_REFERENCE
    }else if(!strcmp(mode,"interfaces")){
        uint32_t control=query(g,standard(0x56a868b1));check("base interface can reach zero while control remains live",CALL(g,2)==0&&graphs.count==1);
        uint32_t reacquired=query(control,standard(0x56a8689f));check("canonical graph identity survives base-first release",reacquired==g);CALL(reacquired,2);
        uint32_t unknown=standard(0x56a868b1),out=gmalloc(4);MEM[unknown+15]^=1;P32(out,0xfeed);check("full IID suffix mismatch is rejected",CALL(control,0,unknown,out)==0x80004002u&&G32(out)==0);
        check("unknown creation IID is rejected",dshow_create_filtergraph(unknown)==0);check("last interface releases shared backing",CALL(control,2)==0&&graphs.count==0);
    }else if(!strcmp(mode,"playback")){
        assert(CALL(g,3,filter,0)==0&&CALL(g,12,pin)==0);uint32_t control=query(g,standard(0x56a868b1)),audio=query(g,standard(0x56a868b3)),position=query(g,standard(0x56a868b2)),event=query(g,standard(0x56a868b6));DSGraph *native=graphs[@(G32(COM_DATA(g)))];
        check("volume uses native dB conversion",CALL(audio,7,(uint32_t)-2000)==0&&fabs(native.player.volume-0.1)<0.0001);
        check("invalid volume is rejected",CALL(audio,7,1)==0x80070057u);check("balance reaches native pan",CALL(audio,9,5000)==0&&fabs(native.player.pan-0.5)<0.0001);
        double time=0.125;uint64_t bits;memcpy(&bits,&time,8);check("double position marshals two guest words",CALL(position,8,(uint32_t)bits,(uint32_t)(bits>>32))==0&&fabs(native.player.currentTime-time)<0.005);
        fnv_dshow_all_active(0);check("Run while suspended preserves pending running state",CALL(control,7)==0&&native.running);uint32_t state=gmalloc(4);CALL(control,10,0,state);check("running state ABI is correct",G32(state)==2);
        check("suspension does not emit a completion event",CALL(event,8,gmalloc(4),gmalloc(4),gmalloc(4),0)==0x80004004u);
        fnv_dshow_all_active(1);BOOL played=native.player.playing;printf("Native host playing=%d (speaker output requires phone acceptance)\n",played);
        if(played){
            // Block this thread's run loop so completion cannot rely only on
            // delegate delivery. The native player's own EOS must be polled.
            usleep(650000);uint32_t ended=gmalloc(4),p1=gmalloc(4),p2=gmalloc(4);
            check("native playback reaches EOS without delegate delivery",CALL(event,8,ended,p1,p2,0)==0&&G32(ended)==1);
            fnv_dshow_all_active(0);CALL(control,7);fnv_dshow_all_active(1);
        }else printf("SKIP: native playback EOS requires an available host output device\n");
        CALL(control,8);CALL(control,10,0,state);check("Pause reports paused",!native.running&&G32(state)==1);CALL(control,9);CALL(control,10,0,state);check("Stop reports stopped",G32(state)==0);
        fnv_dshow_all_active(0);CALL(control,7);fnv_dshow_all_active(1);[native audioPlayerDidFinishPlaying:native.player successfully:YES];uint32_t code=gmalloc(4),p1=gmalloc(4),p2=gmalloc(4);
        check("native finish delegate emits EC_COMPLETE once",CALL(event,8,code,p1,p2,0)==0&&G32(code)==1&&CALL(event,8,code,p1,p2,0)==0x80004004u);
        CALL(control,2);CALL(audio,2);CALL(position,2);CALL(event,2);CALL(g,2);check("all interfaces and filter release",graphs.count==0&&filterRefs==1);
    }else{
        if(!strcmp(mode,"callback-trap"))trapRead=1;else if(!strcmp(mode,"callback-stack"))badPop=1;else if(!strcmp(mode,"oversize"))hugeLength=1;else if(!strcmp(mode,"incomplete"))unavailable=1;else if(!strcmp(mode,"read-failure"))failRead=1;else return 2;
        assert(CALL(g,3,filter,0)==0);check("invalid source callback is rejected without leaking reader",CALL(g,12,pin)!=0&&readerRefs==0);CALL(g,2);check("failed graph drops retained filter",filterRefs==1&&graphs.count==0);
#endif
    }
    free(MEM);return failed?1:0;
}}
