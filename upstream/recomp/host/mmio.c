// winmm multimedia file I/O (RIFF chunk navigation) used by the sound loader.
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include "shims.h"

typedef struct { int fd; uint32_t buf, bufsize, info, proc, scratch; } Mmio;
extern int host_run_guest(CPU *,uint32_t);
#define FCC(a, b, c_, d) ((uint32_t)(a) | ((uint32_t)(b) << 8) | ((uint32_t)(c_) << 16) | ((uint32_t)(d) << 24))
enum { H_MMIO = 40 };
#define MMIOERR_CHUNKNOTFOUND 265
#define MMIOERR_CANNOTREAD 261
#define MMIOERR_CANNOTOPEN 259

static Mmio *mm(uint32_t h) { return handle_get(h, H_MMIO); }

// MMIOPROC is a four-argument x86 stdcall callback, not a host function pointer.
// The game's AF0400 procedure opens BSFile streams (including BSA members).
static int io_proc(CPU *c,Mmio *m,uint32_t message,uint32_t p1,uint32_t p2,int32_t *value) {
    uint32_t sp=REG(c,R_ESP),teb=REG(c,272);
    if(sp<128)return 0;
    CPU saved=*c;uint32_t stack=sp-128,seh=teb&&teb<=0xfffffffcu?G32(teb):0;
    P32(stack,HOST_EXIT_THUNK);P32(stack+4,m->info);P32(stack+8,message);P32(stack+12,p1);P32(stack+16,p2);
    SETREG(c,R_ESP,stack);
    int trap=host_run_guest(c,m->proc);int32_t result=(int32_t)REG(c,R_EAX);uint32_t returned=REG(c,R_ESP);
    *c=saved;if(teb&&teb<=0xfffffffcu)P32(teb,seh);
    if(trap||returned!=stack+20) {
        static unsigned reported;
        if(reported++<8)fprintf(stderr,"[mmio] IOProc failed target=%#x message=%u trap=%d esp=%#x expected=%#x\n",m->proc,message,trap,returned,stack+20);
        return 0;
    }
    *value=result;return 1;
}
static int32_t mm_seek(CPU *c,Mmio *m,int32_t offset,int whence) {
    int32_t result;
    if(m->proc) {
        if(!io_proc(c,m,2,(uint32_t)offset,(uint32_t)whence,&result)||result<0)return -1;
        // AF0400 publishes the BSFile position in lDiskOffset and returns zero.
        // IOProcs own this field; do not overwrite it with the callback result.
        result=(int32_t)G32(m->info+44);
    } else {
        off_t at=lseek(m->fd,offset,whence);if(at<0||at>INT32_MAX)return -1;result=(int32_t)at;
    }
    if(result>=0)P32(m->info+44,(uint32_t)result);
    return result;
}
static int32_t mm_read(CPU *c,Mmio *m,uint32_t destination,uint32_t count) {
    if(count>INT32_MAX || destination>UINT32_MAX-count)return -1;
    int32_t result;
    if(m->proc) {
        if(!io_proc(c,m,0,destination,count,&result)||result<0||(uint32_t)result>count)return -1;
    } else {
        ssize_t n=read(m->fd,MEM+destination,count);if(n<0)return -1;result=(int32_t)n;
        off_t at=lseek(m->fd,0,SEEK_CUR);if(at>=0&&at<=INT32_MAX)P32(m->info+44,(uint32_t)at);
    }
    return result;
}
static void mm_free(Mmio *m) {
    if(m->fd>=0)close(m->fd);
    if(m->buf)gfree(m->buf);if(m->scratch)gfree(m->scratch);if(m->info)gfree(m->info);free(m);
}

static void mmioOpenA_(CPU *c) {
    uint32_t name=ARG(c,0),info=ARG(c,1),flags=ARG(c,2),error=0;
    Mmio *m=calloc(1,sizeof *m);if(!m){RET(c,0,3);return;}m->fd=-1;
    m->info=gmalloc(72);m->scratch=gmalloc(16);memset(MEM+m->info,0,72);
    if(info)memcpy(MEM+m->info,MEM+info,72);
    m->proc=G32(m->info+8);P32(m->info,flags);P32(m->info+44,0);
    uint32_t handle=handle_new(H_MMIO,m);P32(m->info+68,handle);
    if(m->proc) {
        int32_t result;
        if(!io_proc(c,m,3,name,0,&result))error=MMIOERR_CANNOTREAD;
        else if(result)error=(uint32_t)result;
        static unsigned reported;
        if(reported++<16)fprintf(stderr,"[mmio] custom open path=%s proc=%#x error=%u\n",name?GSTR(name):"(null)",m->proc,error);
    } else {
        char path[1024];host_path(name?GSTR(name):"",path,sizeof path);m->fd=open(path,O_RDONLY);
        if(m->fd<0)error=MMIOERR_CANNOTOPEN;
    }
    P32(m->info+12,error);
    if(info)memcpy(MEM+info,MEM+m->info,72);
    if(error){handle_close(handle);mm_free(m);handle=0;}
    RET(c,handle,3);
}
static void mmioClose_(CPU *c) {
    Mmio *m=mm(ARG(c,0));uint32_t result=MMIOERR_CANNOTREAD;
    if(m){result=0;if(m->proc){int32_t value;result=io_proc(c,m,4,0,0,&value)?(uint32_t)value:MMIOERR_CANNOTREAD;}handle_close(ARG(c,0));mm_free(m);}
    RET(c,result,2);
}
static void mmioRead_(CPU *c) {
    Mmio *m = mm(ARG(c, 0));
    int32_t r = m ? mm_read(c,m,ARG(c,1),ARG(c,2)) : -1;
    RET(c, r < 0 ? 0xFFFFFFFFu : (uint32_t)r, 3);
}
// MMCKINFO: ckid, cksize, fccType, dwDataOffset, dwFlags
static void mmioDescend_(CPU *c) {
    Mmio *m = mm(ARG(c, 0)); uint32_t ck = ARG(c, 1), parent = ARG(c, 2), flags = ARG(c, 3);
    if (!m) { RET(c, MMIOERR_CANNOTREAD, 4); return; }
    uint32_t want_id = G32(ck), want_type = G32(ck + 8);
    uint64_t limit = parent ? (uint64_t)G32(parent + 12)+G32(parent + 4) : INT32_MAX;
    for (;;) {
        int32_t at=mm_seek(c,m,0,SEEK_CUR);
        if (at<0 || (uint64_t)at+8>limit) { RET(c, MMIOERR_CHUNKNOTFOUND, 4); return; }
        uint32_t hdr[3];
        if (mm_read(c,m,m->scratch,8)!=8) { RET(c, MMIOERR_CHUNKNOTFOUND, 4); return; }
        memcpy(hdr,MEM+m->scratch,8);
        uint32_t id = hdr[0], size = hdr[1], type = 0;
        if((uint64_t)at+8+size>limit){RET(c,MMIOERR_CHUNKNOTFOUND,4);return;}
        int container = id == FCC('R', 'I', 'F', 'F') || id == FCC('L', 'I', 'S', 'T');
        if(container){if(size<4||mm_read(c,m,m->scratch,4)!=4){RET(c,MMIOERR_CHUNKNOTFOUND,4);return;}memcpy(&type,MEM+m->scratch,4);}
        int match = 1;
        if (flags & 0x10) match = id == want_id;                                   // MMIO_FINDCHUNK
        if (flags & 0x20) match = id == FCC('R', 'I', 'F', 'F') && type == want_type; // MMIO_FINDRIFF
        if (flags & 0x40) match = id == FCC('L', 'I', 'S', 'T') && type == want_type; // MMIO_FINDLIST
        if (match) {
            P32(ck, id); P32(ck + 4, size); P32(ck + 8, type);
            P32(ck + 12, (uint32_t)(at + 8)); P32(ck + 16, 0);
            RET(c, 0, 4); return;
        }
        uint64_t next=(uint64_t)at+8+size+(size&1);
        if(next>INT32_MAX || mm_seek(c,m,(int32_t)next,SEEK_SET)<0){RET(c,MMIOERR_CHUNKNOTFOUND,4);return;}
    }
}
static void mmioAscend_(CPU *c) {
    Mmio *m = mm(ARG(c, 0)); uint32_t ck = ARG(c, 1);
    uint32_t result=MMIOERR_CANNOTREAD;
    if(m){uint32_t size=G32(ck+4);uint64_t next=(uint64_t)G32(ck+12)+size+(size&1);if(next<=INT32_MAX&&mm_seek(c,m,(int32_t)next,SEEK_SET)>=0)result=0;}
    RET(c,result,3);
}
// buffered access: MMIOINFO fields used: cchBuffer(+20) pchBuffer(+24) pchNext(+28) pchEndRead(+32)
// pchEndWrite(+36) lBufOffset(+40) lDiskOffset(+44)
static void mmioGetInfo_(CPU *c) {
    Mmio *m = mm(ARG(c, 0)); uint32_t info = ARG(c, 1);
    if (!m||!info) { RET(c, MMIOERR_CANNOTREAD, 3); return; }
    if (!m->buf) { m->bufsize = 0x10000; m->buf = gmalloc(m->bufsize); }
    int32_t pos=mm_seek(c,m,0,SEEK_CUR);if(pos<0){RET(c,MMIOERR_CANNOTREAD,3);return;}
    P32(m->info+20,m->bufsize);P32(m->info+24,m->buf);P32(m->info+28,m->buf);P32(m->info+32,m->buf);P32(m->info+36,m->buf);
    P32(m->info+40,(uint32_t)pos);memcpy(MEM+info,MEM+m->info,72);
    RET(c, 0, 3);
}
static void mmioAdvance_(CPU *c) {
    Mmio *m = mm(ARG(c, 0)); uint32_t info = ARG(c, 1);
    if (!m || !info) { RET(c, MMIOERR_CANNOTREAD, 3); return; }
    // the guest consumed up to pchNext: continue reading the file from there
    uint32_t consumed=G32(info+28)-G32(info+24);uint64_t next=(uint64_t)G32(info+40)+consumed;
    if(!m->buf||G32(info+24)!=m->buf||consumed>m->bufsize||next>INT32_MAX||mm_seek(c,m,(int32_t)next,SEEK_SET)<0){RET(c,MMIOERR_CANNOTREAD,3);return;}
    int32_t r=mm_read(c,m,m->buf,m->bufsize);if(r<0){RET(c,MMIOERR_CANNOTREAD,3);return;}
    P32(m->info+24,m->buf);P32(m->info+28,m->buf);P32(m->info+32,m->buf+(uint32_t)r);P32(m->info+40,(uint32_t)next);
    memcpy(MEM+info,MEM+m->info,72);
    RET(c, 0, 3);
}

const ShimTable mmio_shims = { (const Shim[]){
    {"mmioOpenA", mmioOpenA_}, {"mmioClose", mmioClose_}, {"mmioRead", mmioRead_}, {"mmioDescend", mmioDescend_},
    {"mmioAscend", mmioAscend_}, {"mmioGetInfo", mmioGetInfo_}, {"mmioAdvance", mmioAdvance_},
}, 7 };
