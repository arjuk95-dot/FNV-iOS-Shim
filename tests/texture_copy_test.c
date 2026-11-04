// Check the complete compressed layout rather than assuming height == stored rows.
#include "FNVGuestMemory.h"
#ifndef FNV_D3D_SOURCE
#define FNV_D3D_SOURCE "../upstream/recomp/host/d3d9.c"
#endif
#include FNV_D3D_SOURCE
#include <assert.h>
uint8_t *MEM;HostImport host_imports[MAX_IMPORTS];int host_import_count;
void rt_trap(CPU *c,int n,uint32_t a){(void)c;fprintf(stderr,"trap %d at %#x\n",n,a);abort();}
static uint32_t stack;
static void invoke(ShimFn fn,uint32_t *args,unsigned count){CPU c={0};SETREG(&c,R_ESP,stack);P32(stack,0xe68d00);for(unsigned i=0;i<count;i++)P32(stack+4+4*i,args[i]);fn(&c);assert(REG(&c,R_ESP)==stack+4+4*count&&REG(&c,R_EAX)==0);}
int main(int argc,char **argv){
    assert(argc==3);int surface=!strcmp(argv[1],"surface");uint32_t format=(uint32_t)strtoul(argv[2],NULL,0);
    MEM=fnv_reserve_guest();assert(MEM!=MAP_FAILED);make_vtables();stack=gmalloc(256);
    uint32_t src=new_texture(0,K_TEX,64,64,1,0,format,1),dst=new_texture(0,K_TEX,64,64,1,0,format,1);
    uint32_t a=tex_surf(src,0,0),b=tex_surf(dst,0,0),pitch,size;
    level_layout(format,64,64,&pitch,&size);
    uint32_t pa=surf_pin(a),pb=surf_pin(b);memset(MEM+pa,0x5a,size);memset(MEM+pb,0,size);
    // Keep pointers pinned throughout the call. The canary is another legitimate live
    // allocation immediately following the destination's size-class storage.
    uint32_t guard=gmalloc(256);memset(MEM+guard,0xc7,256);
    printf("COPY %s fmt=%#x src=%#x dst=%#x bytes=%u guard=%#x\n",argv[1],format,pa,pb,size,guard);
    if(surface)invoke(Dev_UpdateSurface,(uint32_t[]){0,a,0,b,0},5);
    else invoke(Dev_UpdateTexture,(uint32_t[]){0,src,dst},3);
    int good=1;for(unsigned i=0;i<size;i++)if(MEM[pb+i]!=0x5a)good=0;
    for(unsigned i=0;i<256;i++)if(MEM[guard+i]!=0xc7){fprintf(stderr,"OVERWRITE: %s fmt=%#x writes beyond %u-byte layout into live allocation %#x\n",argv[1],format,size,guard);good=0;break;}
    printf("%s: %s fmt=%#x\n",good?"PASS":"FAIL",argv[1],format);return good?0:1;
}
