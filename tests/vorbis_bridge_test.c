// An authored tone and synthetic guest callbacks test the real 32->64-bit Vorbisfile bridge.
#include <vorbis/vorbisenc.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include "shims.h"
uint8_t *MEM;
static uint32_t heap=0x80000;
uint32_t gmalloc(uint32_t n){uint32_t p=heap;heap=(heap+n+15)&~15u;if(heap>=4u<<20)abort();return p;}
void gfree(uint32_t p){(void)p;}
void ov_open_callbacks_(CPU*);void ov_clear_(CPU*);void ov_info_(CPU*);void ov_pcm_total_(CPU*);void ov_seekable_(CPU*);void ov_read_(CPU*);
static uint8_t *compressed;static long length,position;static unsigned reads,seeks,tells,closes;static int fail_read,failed;
static void check(const char *name,int ok){printf("%s: %s\n",ok?"PASS":"FAIL",name);failed+=!ok;}
int host_run_guest(CPU *c,uint32_t entry){
    uint32_t value=0;
    if(entry==0x401000){
        reads++;if(fail_read){fail_read=0;return 6;}
        uint32_t dest=ARG(c,0),size=ARG(c,1),n=ARG(c,2);if(ARG(c,3)!=0xc0ffee)abort();
        value=size?(uint32_t)((length-position)/size):0;if(value>n)value=n;memcpy(MEM+dest,compressed+position,(size_t)value*size);position+=(long)value*size;
    }else if(entry==0x401010){
        seeks++;uint64_t bits=(uint64_t)ARG(c,1)|((uint64_t)ARG(c,2)<<32);int64_t offset=(int64_t)bits;
        int whence=(int)ARG(c,3);int64_t target=(whence==0?0:whence==1?position:length)+offset;
        if(ARG(c,0)!=0xc0ffee)abort();if(target<0||target>length)value=0xffffffffu;else position=(long)target;
    }else if(entry==0x401020){closes++;if(ARG(c,0)!=0xc0ffee)abort();}
    else if(entry==0x401030){tells++;if(ARG(c,0)!=0xc0ffee)abort();value=(uint32_t)position;}
    else abort();
    // Legal caller-saved clobbers must not escape the native callback into the outer guest call.
    SETREG(c,R_ECX,0xdeadbeef);SETREG(c,R_EDX,0xbadf00d);SETREG(c,R_EAX,value);SETREG(c,R_ESP,REG(c,R_ESP)+4);return 0;
}
static CPU state;
static uint32_t call(void(*fn)(CPU*),const uint32_t *args,unsigned n){
    memset(&state,0,sizeof state);SETREG(&state,R_ESP,0x2000);SETREG(&state,R_ECX,0x12345678);P32(0x2000,0x123abc);
    for(unsigned i=0;i<n;i++)P32(0x2004+4*i,args[i]);fn(&state);
    if(REG(&state,R_ESP)!=0x2004||REG(&state,R_ECX)!=0x12345678)abort();return REG(&state,R_EAX);
}
#define CALL(fn,...) call(fn,(uint32_t[]){__VA_ARGS__},sizeof((uint32_t[]){__VA_ARGS__})/4)
static void page(FILE *f,ogg_page *p){fwrite(p->header,1,p->header_len,f);fwrite(p->body,1,p->body_len,f);}
static void make_tone(FILE *f){
    vorbis_info vi;vorbis_comment vc;vorbis_dsp_state vd;vorbis_block vb;ogg_stream_state os;ogg_packet packets[3],packet;ogg_page pg;
    vorbis_info_init(&vi);if(vorbis_encode_init_vbr(&vi,1,48000,0.4))abort();vorbis_comment_init(&vc);
    vorbis_analysis_init(&vd,&vi);vorbis_block_init(&vd,&vb);ogg_stream_init(&os,1234);
    vorbis_analysis_headerout(&vd,&vc,&packets[0],&packets[1],&packets[2]);for(int i=0;i<3;i++)ogg_stream_packetin(&os,&packets[i]);while(ogg_stream_flush(&os,&pg))page(f,&pg);
    float **pcm=vorbis_analysis_buffer(&vd,48000);for(int i=0;i<48000;i++)pcm[0][i]=0.5f*sinf((float)(2*3.141592653589793*440*i/48000));vorbis_analysis_wrote(&vd,48000);
    for(int pass=0;pass<2;pass++){
        while(vorbis_analysis_blockout(&vd,&vb)==1){vorbis_analysis(&vb,NULL);vorbis_bitrate_addblock(&vb);while(vorbis_bitrate_flushpacket(&vd,&packet)){ogg_stream_packetin(&os,&packet);while(ogg_stream_pageout(&os,&pg))page(f,&pg);}}
        vorbis_analysis_wrote(&vd,0);
    }
    while(ogg_stream_flush(&os,&pg))page(f,&pg);
    ogg_stream_clear(&os);vorbis_block_clear(&vb);vorbis_dsp_clear(&vd);vorbis_comment_clear(&vc);vorbis_info_clear(&vi);
}
int main(void){
    MEM=calloc(1,4u<<20);FILE *f=tmpfile();make_tone(f);length=ftell(f);rewind(f);compressed=malloc(length);fread(compressed,1,length,f);fclose(f);
    uint32_t key=0x7000;int result=(int32_t)CALL(ov_open_callbacks_,0xc0ffee,key,0,0,0x401000,0x401010,0x401020,0x401030);
    check("actual encoded Vorbis opens through guest callbacks",result==0&&reads&&seeks&&tells);
    uint32_t info=CALL(ov_info_,key,0xffffffffu);check("vorbis_info marshals 32-bit channel/rate fields",info&&G32(info+4)==1&&G32(info+8)==48000);
    uint32_t low=CALL(ov_pcm_total_,key,0xffffffffu);check("64-bit PCM total uses EDX:EAX",low==48000&&REG(&state,R_EDX)==0);
    check("seekability follows callbacks",CALL(ov_seekable_,key)==1);
    uint64_t bytes=0,energy=0;
    for(int i=0;i<100;i++){
        int n=(int32_t)CALL(ov_read_,key,0x30000,4096,0,2,1,0x40000);if(n<0){failed++;break;}if(!n)break;bytes+=(unsigned)n;
        for(int j=0;j<n/2;j++){int16_t sample;memcpy(&sample,MEM+0x30000+2*j,2);energy+=(unsigned)abs(sample);}
    }
    check("decoded signed PCM has expected duration and audible energy",bytes==96000&&energy>1000000);
    check("clear invokes guest close exactly once",CALL(ov_clear_,key)==0&&closes==1);
    position=0;long saved_length=length;length=64;unsigned old_close=closes;
    check("invalid data is an error without taking guest ownership",(int32_t)CALL(ov_open_callbacks_,0xc0ffee,key,0,0,0x401000,0x401010,0x401020,0x401030)<0&&closes==old_close);
    position=0;length=saved_length;fail_read=1;
    check("guest callback trap remains a failed decode",(int32_t)CALL(ov_open_callbacks_,0xc0ffee,key,0,0,0x401000,0x401010,0x401020,0x401030)<0);
    position=0;result=(int32_t)CALL(ov_open_callbacks_,0xc0ffee,key,0,0,0x401000,0x401010,0x401020,0x401030);
    check("callback failure releases bridge locks for later streams",result==0);if(!result)CALL(ov_clear_,key);
    free(compressed);free(MEM);return failed?1:0;
}
