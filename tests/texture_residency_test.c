// Exercise actual DDS loading, surface pin/eviction, heap reuse and delayed destruction.
#include "FNVGuestMemory.h"
#include "../upstream/recomp/host/d3d9.c"
#include <assert.h>
#include <pthread.h>
uint8_t *MEM;HostImport host_imports[MAX_IMPORTS];int host_import_count;
void rt_trap(CPU *c,int n,uint32_t a){(void)c;fprintf(stderr,"Unexpected trap %d at %#x\n",n,a);abort();}
extern const ShimTable d3dx_shims;
static uint32_t invoke(ShimFn fn,uint32_t *args,unsigned count){CPU c={0};uint32_t stack=gmalloc(128);SETREG(&c,R_ESP,stack);P32(stack,0xe68d00);for(unsigned i=0;i<count;i++)P32(stack+4+4*i,args[i]);fn(&c);uint32_t result=REG(&c,R_EAX);assert(REG(&c,R_ESP)==stack+4+4*count);gfree(stack);return result;}
static uint32_t source,source_bytes;
static void fixture(void){
    source_bytes=128;for(unsigned l=0;l<9;l++){unsigned w=256>>l,h=128>>l;if(!h)h=1;source_bytes+=w*h*4;}
    source=gmalloc(source_bytes);P32(source,FOURCC('D','D','S',' '));P32(source+4,124);P32(source+12,128);P32(source+16,256);P32(source+28,9);
    P32(source+76,32);P32(source+80,0x41);P32(source+88,32);P32(source+92,0xff0000);P32(source+96,0xff00);P32(source+100,0xff);P32(source+104,0xff000000);
    unsigned offset=128;for(unsigned l=0;l<9;l++){unsigned w=256>>l,h=128>>l;if(!h)h=1;unsigned bytes=w*h*4;memset(MEM+source+offset,0x40+l,bytes);offset+=bytes;}
}
static uint32_t load(void){uint32_t out=gmalloc(4),texture=0;for(int i=0;i<d3dx_shims.count;i++)if(!strcmp(d3dx_shims.list[i].name,"D3DXCreateTextureFromFileInMemory")){
    assert(invoke(d3dx_shims.list[i].fn,(uint32_t[]){0,source,source_bytes,out},4)==0);texture=G32(out);break;}
    gfree(out);assert(texture&&OBJ_KIND(texture)==K_TEX&&G32(OBJ_F(texture,T_LEVELS))==9);return texture;}
static void validate(uint32_t t){
    for(unsigned l=0;l<9;l++){uint32_t pitch,size,p=d3d9_texture_level_data(t,0,l,&pitch,&size);assert(p&&size);for(unsigned i=0;i<size;i++)assert(MEM[p+i]==0x40+l);}
    d3d9_texture_dirty(t);
}
int main(void){
    MEM=fnv_reserve_guest();assert(MEM!=MAP_FAILED);make_vtables();fixture();
    for(unsigned i=0;i<2000;i++){
        uint32_t t=load();validate(t);invoke(Unk_Release,(uint32_t[]){t},1);g_d3d.frames+=4;reap();g_d3d.frames+=4;reap();
        if(i%250==0)printf("DDS reuse iteration %u\n",i);
    }
    printf("PASS: 2000 actual DDS loads, all mip bytes, eviction/restore, release and heap reuse\n");
    return 0;
}
