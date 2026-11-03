// Exercise the actual Win32 file shims against real case-sensitive host files.
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include "shims.h"
uint8_t *MEM;
_Thread_local uint32_t host_last_error;
extern const ShimTable file_shims;
static void *objects[32];
static int types[32];
uint32_t handle_new(int type,void *object){for(int i=1;i<32;i++)if(!objects[i]){objects[i]=object;types[i]=type;return i;}abort();}
void *handle_get(uint32_t h,int type){return h<32&&types[h]==type?objects[h]:NULL;}
int handle_type(uint32_t h){return h<32?types[h]:0;}
void handle_close(uint32_t h){if(h<32&&objects[h]){if(types[h]==H_FILE){close(*(int *)objects[h]);free(objects[h]);}objects[h]=NULL;types[h]=0;}}
static uint32_t call(const char *name,const uint32_t *args,int count){
    CPU c={0};SETREG(&c,R_ESP,0x1000);P32(0x1000,0xabc);
    for(int i=0;i<count;i++)P32(0x1004+4*i,args[i]);
    for(int i=0;i<file_shims.count;i++)if(!strcmp(file_shims.list[i].name,name)){file_shims.list[i].fn(&c);return REG(&c,R_EAX);}
    abort();
}
static uint32_t str(const char *s){static uint32_t at=0x10000;uint32_t p=at;strcpy((char *)MEM+p,s);at+=(uint32_t)strlen(s)+1;return p;}
static uint32_t wide(const char *s){static uint32_t at=0x20000;uint32_t p=at;do{uint16_t w=(uint8_t)*s;memcpy(MEM+at,&w,2);at+=2;}while(*s++);return p;}
static int failed;
static void check(const char *name,int good){printf("%s: %s\n",good?"PASS":"FAIL",name);failed+=!good;}
int main(int argc,char **argv){
    if(argc!=2||chdir(argv[1]))return 2;setenv("FNV_ROOT",argv[1],1);MEM=calloc(1,1<<20);
    uint32_t a[]={str("data\\fallout - misc.bsa"),0x80000000,0,0,3,0,0};
    uint32_t h=call("CreateFileA",a,7);check("CreateFileA mixed directory and basename",h!=0xffffffffu);
    if(h!=0xffffffffu){uint32_t r[]={h,0x30000,6,0x31000,0};check("ReadFile original content",call("ReadFile",r,5)&&G32(0x31000)==6&&!memcmp(MEM+0x30000,"marker",6));handle_close(h);}
    uint32_t at[]={str("DATA\\FALLOUT - MISC.BSA")};check("GetFileAttributesA case aliases",call("GetFileAttributesA",at,1)!=0xffffffffu);
    uint32_t ini[]={str("archive"),str("sarchivelist"),str("missing"),0x32000,256,str("c:\\games\\falloutnv\\userdocuments\\my games\\falloutnv\\Fallout.ini")};
    call("GetPrivateProfileStringA",ini,6);check("INI drive path, component and key case",!strcmp((char *)MEM+0x32000,"example.bsa"));
    uint32_t find[]={str("dAtA\\*.BSA"),0x33000};uint32_t fh=call("FindFirstFileA",find,2);check("FindFirstFileA mixed parent and pattern",fh!=0xffffffffu);if(fh!=0xffffffffu){uint32_t cl[]={fh};call("FindClose",cl,1);}
    uint32_t w[]={wide("C:\\Games\\FALLOUTNV\\DATA\\New.txt"),0x40000000,0,0,2,0,0};h=call("CreateFileW",w,7);check("CreateFileW resolves existing parents for new files",h!=0xffffffffu);if(h!=0xffffffffu)handle_close(h);
    uint32_t reopen[]={str("data\\NEW.TXT"),0x80000000,0,0,3,0,0};h=call("CreateFileA",reopen,7);check("Reopen new file with alternate case",h!=0xffffffffu);if(h!=0xffffffffu)handle_close(h);
    char path[1024];host_path("DATA\\not-present.bin",path,sizeof path);check("Missing leaf remains missing",access(path,F_OK)!=0);
    free(MEM);return failed?1:0;
}
