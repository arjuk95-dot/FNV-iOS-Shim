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
static uint32_t invoke(ShimFn fn,uint32_t *args,unsigned count){CPU c={0};SETREG(&c,R_ESP,stack);P32(stack,0xe68d00);for(unsigned i=0;i<count;i++)P32(stack+4+4*i,args[i]);fn(&c);assert(REG(&c,R_ESP)==stack+4+4*count);return REG(&c,R_EAX);}
int main(int argc,char **argv){
    assert(argc==3);int surface=!strcmp(argv[1],"surface");uint32_t format=(uint32_t)strtoul(argv[2],NULL,0);
    MEM=fnv_reserve_guest();assert(MEM!=MAP_FAILED);make_vtables();stack=gmalloc(256);
    if(!strcmp(argv[1],"cube-chain")){
        uint32_t source=new_texture(0,K_CUBE,64,64,7,0,format,2),dest=new_texture(0,K_CUBE,16,16,5,0,format,0);
        for(unsigned f=0;f<6;f++)for(unsigned l=0;l<7;l++){
            uint32_t pitch,bytes,p=d3d9_texture_level_data(source,f,l,&pitch,&bytes);memset(MEM+p,0x20+f*8+l,bytes);
        }
        d3d9_texture_dirty(source);
        assert(invoke(Dev_UpdateTexture,(uint32_t[]){0,source,dest},3)==0);
        for(unsigned f=0;f<6;f++)for(unsigned l=0;l<5;l++){
            uint32_t pitch,bytes,p=d3d9_texture_level_data(dest,f,l,&pitch,&bytes);
            for(unsigned i=0;i<bytes;i++)assert(MEM[p+i]==0x20+f*8+l+2);
        }
        d3d9_texture_dirty(dest);printf("PASS: six cube faces / matching five-level bottom chain fmt=%#x\n",format);return 0;
    }
    if(!strcmp(argv[1],"rectangle")){
        uint32_t a=new_surface(0,64,64,format,0,2,0,0,0,0),b=new_surface(0,64,64,format,0,0,0,0,0,0);
        uint32_t pitch,bytes;level_layout(format,64,64,&pitch,&bytes);
        uint32_t pa=surf_pin(a),pb=surf_pin(b);memset(MEM+pa,0x5a,bytes);memset(MEM+pb,0xc7,bytes);
        uint32_t rect=gmalloc(16),point=gmalloc(8);P32(rect,4);P32(rect+4,4);P32(rect+8,16);P32(rect+12,16);P32(point,8);P32(point+4,8);
        assert(invoke(Dev_UpdateSurface,(uint32_t[]){0,a,rect,b,point},5)==0);
        uint32_t block=d3d_fmt_block(format),unit=block?block:d3d_fmt_bpp(format),firstrow=block?2:8,rows=block?3:12,start=(block?2:8)*unit,width=(block?3:12)*unit;
        for(unsigned i=0;i<bytes;i++){unsigned row=i/pitch,col=i%pitch;assert(MEM[pb+i]==(row>=firstrow&&row<firstrow+rows&&col>=start&&col<start+width?0x5a:0xc7));}
        P32(rect+8,1000);assert(invoke(Dev_UpdateSurface,(uint32_t[]){0,a,rect,b,point},5)==D3DERR_INVALIDCALL);
        if(block){P32(rect+8,16);P32(rect,3);assert(invoke(Dev_UpdateSurface,(uint32_t[]){0,a,rect,b,point},5)==D3DERR_INVALIDCALL);}
        printf("PASS: rectangle / untouched bytes / invalid bounds and block alignment fmt=%#x\n",format);return 0;
    }
    uint32_t src=new_texture(0,K_TEX,64,64,1,0,format,1),dst=new_texture(0,K_TEX,64,64,1,0,format,1);
    uint32_t a=tex_surf(src,0,0),b=tex_surf(dst,0,0),pitch,size;
    level_layout(format,64,64,&pitch,&size);
    uint32_t pa=surf_pin(a),pb=surf_pin(b);memset(MEM+pa,0x5a,size);memset(MEM+pb,0,size);
    // Keep pointers pinned throughout the call. The canary is another legitimate live
    // allocation immediately following the destination's size-class storage.
    uint32_t guard=gmalloc(256);memset(MEM+guard,0xc7,256);
    printf("COPY %s fmt=%#x src=%#x dst=%#x bytes=%u guard=%#x\n",argv[1],format,pa,pb,size,guard);
    if(surface)assert(invoke(Dev_UpdateSurface,(uint32_t[]){0,a,0,b,0},5)==0);
    else assert(invoke(Dev_UpdateTexture,(uint32_t[]){0,src,dst},3)==0);
    int good=1;for(unsigned i=0;i<size;i++)if(MEM[pb+i]!=0x5a)good=0;
    for(unsigned i=0;i<256;i++)if(MEM[guard+i]!=0xc7){fprintf(stderr,"OVERWRITE: %s fmt=%#x writes beyond %u-byte layout into live allocation %#x\n",argv[1],format,size,guard);good=0;break;}
    printf("%s: %s fmt=%#x\n",good?"PASS":"FAIL",argv[1],format);return good?0:1;
}
