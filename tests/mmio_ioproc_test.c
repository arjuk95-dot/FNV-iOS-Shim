// Authored RIFF bytes reached only through a standard four-argument IOProc.
// The original game's AF0400 callback uses stdcall RET16 and stores its BSFile
// in MMIOINFO.adwInfo[0]. Its SEEK returns zero and publishes lDiskOffset.
#ifndef FNV_MMIO_SOURCE
#define FNV_MMIO_SOURCE "../upstream/recomp/host/mmio.c"
#endif
#include FNV_MMIO_SOURCE
#include <assert.h>

uint8_t *MEM;
static uint32_t heap=0x100000,allocs[1024];static unsigned allocated,live_allocs;
uint32_t gmalloc(uint32_t n){uint32_t p=heap;heap=(heap+n+15)&~15u;assert(heap<16u*1024*1024&&allocated<1024);memset(MEM+p,0,n);allocs[allocated++]=p;live_allocs++;return p;}
void gfree(uint32_t p){if(!p)return;for(unsigned i=0;i<allocated;i++)if(allocs[i]==p){allocs[i]=0;live_allocs--;return;}assert(!"double or unknown guest free");}
static struct {int type;void *value;} test_handles[32];
uint32_t handle_new(int type,void *value){for(unsigned i=1;i<32;i++)if(!test_handles[i].value){test_handles[i].type=type;test_handles[i].value=value;return 0x5000+i;}abort();}
void *handle_get(uint32_t h,int type){unsigned i=h-0x5000;return i<32&&test_handles[i].type==type?test_handles[i].value:NULL;}
void handle_close(uint32_t h){unsigned i=h-0x5000;assert(i<32);test_handles[i].type=0;test_handles[i].value=NULL;}
static unsigned live_handles(void){unsigned n=0;for(unsigned i=1;i<32;i++)n+=test_handles[i].value!=NULL;return n;}
void host_path(const char *name,char *out,size_t n){snprintf(out,n,"%s",name?name:"");}
void rt_trap(CPU *c,int kind,uint32_t address){(void)c;fprintf(stderr,"unexpected trap %d at %#x\n",kind,address);abort();}

enum { PROC=0x610000, COOKIE=0xf00d1234, PAYLOAD=70002, DATA_OFFSET=70, FIXTURE_BYTES=DATA_OFFSET+PAYLOAD+12 };
static uint8_t fixture[FIXTURE_BYTES];
static uint32_t persistent_info;
static unsigned opens,reads,seeks,closes;
static int fail_message=-1,trap_message=-1,badpop_message=-1;
static unsigned failed;
static void check(const char *name,int ok){printf("%s: %s\n",ok?"PASS":"FAIL",name);failed+=!ok;}
static void put32(unsigned at,uint32_t value){memcpy(fixture+at,&value,4);}
static void make_fixture(void){
    memcpy(fixture,"RIFF",4);put32(4,FIXTURE_BYTES-8);memcpy(fixture+8,"WAVEJUNK",8);put32(16,3);memcpy(fixture+20,"odd",3);
    memcpy(fixture+24,"fmt ",4);put32(28,16);fixture[32]=1;fixture[34]=1;put32(36,48000);put32(40,96000);fixture[44]=2;fixture[46]=16;
    memcpy(fixture+48,"JUNK",4);put32(52,5);memcpy(fixture+56,"abcde",5);
    memcpy(fixture+62,"data",4);put32(66,PAYLOAD);for(unsigned i=0;i<PAYLOAD;i++)fixture[DATA_OFFSET+i]=(uint8_t)(i*37+13);
    memcpy(fixture+DATA_OFFSET+PAYLOAD,"TAIL",4);put32(DATA_OFFSET+PAYLOAD+4,3);memcpy(fixture+DATA_OFFSET+PAYLOAD+8,"end",3);
}
static void authored_ioproc(CPU *c){
    uint32_t info=ARG(c,0),msg=ARG(c,1),p1=ARG(c,2),p2=ARG(c,3),result=0;
    assert(info&&G32(info+8)==PROC);
    if(msg==3){
        opens++;persistent_info=info;assert(!strcmp(GSTR(p1),"archive-only-does-not-exist.wav")&&p2==0);
        if(fail_message==3)result=0x101;
        else{P32(info+44,0);P32(info+48,COOKIE);P32(info+52,0xcafebabe);}
    }else{
        assert(info==persistent_info&&G32(info+48)==COOKIE&&G32(info+52)==0xcafebabe);
        uint32_t position=G32(info+44);
        if(msg==0){
            reads++;assert(p1&&p2<=16u*1024*1024&&position<=FIXTURE_BYTES);
            if(fail_message==0)result=0xffffffffu;
            else{result=p2<FIXTURE_BYTES-position?p2:FIXTURE_BYTES-position;memcpy(MEM+p1,fixture+position,result);P32(info+44,position+result);}
        }else if(msg==2){
            seeks++;int64_t next=(int32_t)p1;
            if(p2==1)next+=position;else if(p2==2)next+=FIXTURE_BYTES;else assert(p2==0);
            assert(next>=0&&next<=FIXTURE_BYTES);P32(info+44,(uint32_t)next);
            // Match the original game's IOProc: lDiskOffset is authoritative.
            result=0;
        }else if(msg==4){closes++;assert(p1==0&&p2==0);result=fail_message==4?0x104:0;}
        else assert(!"unexpected IOProc message");
    }
    RET(c,result,4);
}
int host_run_guest(CPU *c,uint32_t target){
    assert(target==PROC);uint32_t message=ARG(c,1);
    P32(REG(c,272),0xdeadff00); // A trapped translated SEH frame has no epilogue.
    if((int)message==trap_message)return 6;
    authored_ioproc(c);uint32_t result=REG(c,R_EAX),stack=REG(c,R_ESP);
    if((int)message==badpop_message)stack-=4;
    memset(c,0xa5,sizeof *c);SETREG(c,R_EAX,result);SETREG(c,R_ESP,stack);return 0;
}
static uint32_t invoke(const char *name,const uint32_t *args,unsigned n){
    CPU c;memset(&c,0x35,sizeof c);SETREG(&c,R_ESP,0x80000);SETREG(&c,272,0x70000);CPU expected=c;
    P32(0x70000,0x70010);P32(0x80000,0x12345678);for(unsigned i=0;i<n;i++)P32(0x80004+4*i,args[i]);
    for(int i=0;i<mmio_shims.count;i++)if(!strcmp(mmio_shims.list[i].name,name)){
        mmio_shims.list[i].fn(&c);uint32_t result=REG(&c,R_EAX);
        SETREG(&expected,R_EAX,result);SETREG(&expected,R_ESP,0x80004+4*n);
        assert(!memcmp(&c,&expected,sizeof c));assert(G32(0x70000)==0x70010);return result;
    }
    abort();
}
#define CALL(n,...) invoke(n,(uint32_t[]){__VA_ARGS__},sizeof((uint32_t[]){__VA_ARGS__})/4)
static uint32_t open_source(int custom){
    uint32_t name=0x2000,info=0x3000;strcpy(GSTR(name),custom?"archive-only-does-not-exist.wav":"authored-loose.wav");memset(MEM+info,0,72);
    P32(info+4,0x564157);P32(info+8,custom?PROC:0);
    return CALL("mmioOpenA",name,custom?info:0,0x10000);
}
static void navigate(uint32_t h,int custom){
    uint32_t root=0x4000,chunk=0x4040,out=0x5000,info=0x6000;memset(MEM+root,0,20);memset(MEM+chunk,0,20);
    check("root RIFF descends through the real shim",CALL("mmioDescend",h,root,0,0)==0&&G32(root)==0x46464952&&G32(root+8)==0x45564157&&G32(root+12)==8);
    P32(chunk,0x20746d66);check("odd pre-format chunk is skipped with word padding",CALL("mmioDescend",h,chunk,root,0x10)==0&&G32(chunk+4)==16&&G32(chunk+12)==32);
    check("mmioRead returns the exact PCM format",CALL("mmioRead",h,out,16)==16&&!memcmp(MEM+out,fixture+32,16));
    check("format Ascend succeeds",CALL("mmioAscend",h,chunk,0)==0);
    P32(chunk,0x61746164);check("odd intervening chunk does not shift data",CALL("mmioDescend",h,chunk,root,0x10)==0&&G32(chunk+12)==DATA_OFFSET&&G32(chunk+4)==PAYLOAD);
    check("buffered MMIOINFO is available",CALL("mmioGetInfo",h,info,0)==0);
    if(custom)check("GetInfo retains custom procedure and private source state",G32(info+8)==PROC&&G32(info+48)==COOKIE&&G32(info+52)==0xcafebabe);
    int bytes_ok=1;unsigned advances=0;
    for(unsigned i=0;i<PAYLOAD;i++){
        if(G32(info+28)==G32(info+32)){
            if(CALL("mmioAdvance",h,info,0)!=0||G32(info+28)>=G32(info+32)){bytes_ok=0;break;}advances++;
        }
        uint32_t next=G32(info+28);if(MEM[next]!=fixture[DATA_OFFSET+i]){bytes_ok=0;break;}P32(info+28,next+1);
    }
    check("GetInfo/Advance copies exact payload across multiple fills",bytes_ok&&advances>=2);
    check("data Ascend succeeds after buffered consumption",CALL("mmioAscend",h,chunk,0)==0);
    P32(chunk,0x4c494154);check("navigation resumes after data at the trailing chunk",CALL("mmioDescend",h,chunk,root,0x10)==0&&G32(chunk+4)==3&&CALL("mmioRead",h,out,3)==3&&!memcmp(MEM+out,"end",3));
    if(custom)check("real callback READ and SEEK routes were exercised",reads>3&&seeks>1&&G32(persistent_info+48)==COOKIE);
}
int main(int argc,char **argv){
    assert(argc==2);const char *mode=argv[1];MEM=calloc(1,16u*1024*1024);assert(MEM);make_fixture();
    if(!strcmp(mode,"loose")){
        FILE *f=fopen("authored-loose.wav","wb");assert(f&&fwrite(fixture,1,sizeof fixture,f)==sizeof fixture);fclose(f);
        uint32_t h=open_source(0);check("direct loose filename control opens",h!=0);if(h){navigate(h,0);check("loose close releases handle",CALL("mmioClose",h,0)==0&&!live_handles()&&!live_allocs);}
        unlink("authored-loose.wav");
    }else{
        if(!strcmp(mode,"open-trap"))trap_message=3;
        else if(!strcmp(mode,"open-stack"))badpop_message=3;
        else if(!strcmp(mode,"open-failure"))fail_message=3;
        uint32_t h=open_source(1);
        if(!strncmp(mode,"open-",5))check("failed Open restores CPU/SEH and releases temporary guest state",!h&&!live_handles()&&!live_allocs);
        else if(!h)check("custom archive source opens without any loose file",0);
        else if(!strcmp(mode,"archive")){
            check("custom archive source opens through MMIOM_OPEN",opens==1);navigate(h,1);
            check("close dispatches once and frees persistent state",CALL("mmioClose",h,0)==0&&closes==1&&!live_handles()&&!live_allocs);
            CALL("mmioClose",h,0);check("repeated close cannot reenter a stale callback",closes==1);
        }else{
            if(!strcmp(mode,"read-trap"))trap_message=0;
            else if(!strcmp(mode,"read-stack"))badpop_message=0;
            else if(!strcmp(mode,"read-failure"))fail_message=0;
            else if(!strcmp(mode,"close-error"))fail_message=4;
            else return 2;
            if(strcmp(mode,"close-error"))check("invalid read callback fails while preserving caller CPU/SEH",CALL("mmioRead",h,0x5000,8)==0xffffffffu);
            uint32_t result=CALL("mmioClose",h,0);
            check("close error is reported without retaining the stream",(!strcmp(mode,"close-error")?result!=0:result==0)&&closes==1&&!live_handles()&&!live_allocs);
        }
    }
    free(MEM);return failed?1:0;
}
