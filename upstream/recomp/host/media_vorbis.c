// Marshal the 32-bit guest Vorbisfile ABI to native libvorbisfile. Native pointers stay out of guest memory.
#ifdef FNV_HAVE_VORBIS
#define OV_EXCLUDE_STATIC_CALLBACKS
#include <vorbis/vorbisfile.h>
#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#include "shims.h"
extern int host_run_guest(CPU *,uint32_t);
typedef struct VorbisContext {
    uint32_t key,datasource,callbacks[4],scratch,scratch_size,info;
    CPU *cpu;int callback_failed;OggVorbis_File native;
    struct VorbisContext *next;
} VorbisContext;
static VorbisContext *contexts;
static pthread_mutex_t vorbis_lock=PTHREAD_MUTEX_INITIALIZER;
static VorbisContext *find(uint32_t key){for(VorbisContext *v=contexts;v;v=v->next)if(v->key==key)return v;return NULL;}
static uint32_t callback(VorbisContext *v,unsigned which,const uint32_t *args,unsigned n){
    if(!v->callbacks[which]||v->callback_failed)return 0;
    CPU saved=*v->cpu;uint32_t sp=REG(v->cpu,R_ESP);
    if(sp<64){v->callback_failed=1;return 0;}
    sp-=64;P32(sp,HOST_EXIT_THUNK);for(unsigned i=0;i<n;i++)P32(sp+4+4*i,args[i]);SETREG(v->cpu,R_ESP,sp);
    int trap=host_run_guest(v->cpu,v->callbacks[which]);uint32_t result=REG(v->cpu,R_EAX);*v->cpu=saved;
    if(trap){v->callback_failed=1;fprintf(stderr,"[vorbis] guest callback failed trap=%d callback=%#x caller=%#x\n",trap,v->callbacks[which],G32(REG(v->cpu,R_ESP)));return 0;}
    return result;
}
static size_t read_callback(void *target,size_t size,size_t n,void *opaque){
    VorbisContext *v=opaque;if(!size||!n)return 0;
    if(size>0xffffffffu||n>0xffffffffu||size>16u*1024*1024/n){v->callback_failed=1;return 0;}
    uint32_t bytes=(uint32_t)(size*n);
    if(bytes>v->scratch_size){uint32_t p=gmalloc(bytes);if(!p){v->callback_failed=1;return 0;}if(v->scratch)gfree(v->scratch);v->scratch=p;v->scratch_size=bytes;}
    uint32_t args[]={v->scratch,(uint32_t)size,(uint32_t)n,v->datasource};size_t result=callback(v,0,args,4);
    if(result>n){v->callback_failed=1;return 0;}
    memcpy(target,MEM+v->scratch,result*size);return result;
}
static int seek_callback(void *opaque,ogg_int64_t offset,int whence){VorbisContext *v=opaque;uint64_t u=(uint64_t)offset;uint32_t args[]={v->datasource,(uint32_t)u,(uint32_t)(u>>32),(uint32_t)whence};return (int32_t)callback(v,1,args,4);}
static int close_callback(void *opaque){VorbisContext *v=opaque;uint32_t args[]={v->datasource};return (int32_t)callback(v,2,args,1);}
static long tell_callback(void *opaque){VorbisContext *v=opaque;uint32_t args[]={v->datasource};return (int32_t)callback(v,3,args,1);}
static void release(VorbisContext *v){if(v->scratch)gfree(v->scratch);if(v->info)gfree(v->info);free(v);}
void ov_open_callbacks_(CPU *c){
    pthread_mutex_lock(&vorbis_lock);uint32_t key=ARG(c,1),initial=ARG(c,2),bytes=ARG(c,3);
    int result=OV_EINVAL;
    if(key&&!find(key)&&bytes<=16u*1024*1024&&(!bytes||initial<=0xffffffffu-bytes)){
        VorbisContext *v=calloc(1,sizeof *v);
        if(v){v->key=key;v->datasource=ARG(c,0);v->cpu=c;for(unsigned i=0;i<4;i++)v->callbacks[i]=ARG(c,4+i);
            ov_callbacks cb={v->callbacks[0]?read_callback:NULL,v->callbacks[1]?seek_callback:NULL,v->callbacks[2]?close_callback:NULL,v->callbacks[3]?tell_callback:NULL};
            if(!cb.read_func){result=OV_EINVAL;release(v);}
            else{
                result=ov_open_callbacks(v,&v->native,bytes?(const char*)MEM+initial:NULL,bytes,cb);
                if(v->callback_failed&&result==0){ov_clear(&v->native);result=OV_EREAD;}
                if(result==0){v->next=contexts;contexts=v;vorbis_info *info=ov_info(&v->native,-1);fprintf(stderr,"[vorbis] opened guest=%#x channels=%d rate=%ld seekable=%ld\n",key,info?info->channels:0,info?info->rate:0,ov_seekable(&v->native));}
                else release(v);
            }
        }else result=OV_EFAULT;
    }
    if(result)fprintf(stderr,"[vorbis] open failed error=%d guest=%#x caller=%#x\n",result,key,G32(REG(c,R_ESP)));
    pthread_mutex_unlock(&vorbis_lock);RET(c,(uint32_t)result,0);
}
void ov_clear_(CPU *c){
    pthread_mutex_lock(&vorbis_lock);uint32_t key=ARG(c,0);VorbisContext **link=&contexts;
    while(*link&&(*link)->key!=key)link=&(*link)->next;
    int result=OV_EINVAL;if(*link){VorbisContext *v=*link;*link=v->next;v->cpu=c;result=ov_clear(&v->native);release(v);}
    pthread_mutex_unlock(&vorbis_lock);RET(c,(uint32_t)result,0);
}
void ov_info_(CPU *c){
    pthread_mutex_lock(&vorbis_lock);VorbisContext *v=find(ARG(c,0));uint32_t result=0;
    if(v){v->cpu=c;vorbis_info *i=ov_info(&v->native,(int32_t)ARG(c,1));if(i){if(!v->info)v->info=gmalloc(32);if(v->info){uint32_t values[]={i->version,i->channels,(uint32_t)i->rate,(uint32_t)i->bitrate_upper,(uint32_t)i->bitrate_nominal,(uint32_t)i->bitrate_lower,(uint32_t)i->bitrate_window,0};memcpy(MEM+v->info,values,sizeof values);result=v->info;}}}
    pthread_mutex_unlock(&vorbis_lock);RET(c,result,0);
}
void ov_pcm_total_(CPU *c){
    pthread_mutex_lock(&vorbis_lock);VorbisContext *v=find(ARG(c,0));ogg_int64_t result=OV_EINVAL;
    if(v){v->cpu=c;result=ov_pcm_total(&v->native,(int32_t)ARG(c,1));if(v->callback_failed)result=OV_EREAD;}
    pthread_mutex_unlock(&vorbis_lock);SETREG(c,R_EDX,(uint32_t)((uint64_t)result>>32));RET(c,(uint32_t)result,0);
}
void ov_seekable_(CPU *c){pthread_mutex_lock(&vorbis_lock);VorbisContext *v=find(ARG(c,0));uint32_t result=v?(uint32_t)ov_seekable(&v->native):0;pthread_mutex_unlock(&vorbis_lock);RET(c,result,0);}
void ov_read_(CPU *c){
    pthread_mutex_lock(&vorbis_lock);VorbisContext *v=find(ARG(c,0));uint32_t buffer=ARG(c,1),length=ARG(c,2),out=ARG(c,6);long result=OV_EINVAL;int stream=0;
    if(v&&length<=16u*1024*1024&&buffer<=0xffffffffu-length){v->cpu=c;result=ov_read(&v->native,(char*)MEM+buffer,(int)length,(int)ARG(c,3),(int)ARG(c,4),(int)ARG(c,5),&stream);if(v->callback_failed)result=OV_EREAD;if(out)P32(out,(uint32_t)stream);}
    pthread_mutex_unlock(&vorbis_lock);RET(c,(uint32_t)result,0);
}
#endif
