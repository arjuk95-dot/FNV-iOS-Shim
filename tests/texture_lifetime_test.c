// Real guest COM calls, bindings, deferred destruction, and subsequent heap reuse.
#include "FNVGuestMemory.h"
#ifndef FNV_D3D_SOURCE
#define FNV_D3D_SOURCE "../upstream/recomp/host/d3d9.c"
#endif
#include FNV_D3D_SOURCE
#include <assert.h>
uint8_t *MEM; HostImport host_imports[MAX_IMPORTS]; int host_import_count;
void rt_trap(CPU *c,int n,uint32_t a){(void)c;fprintf(stderr,"trap %d at %#x\n",n,a);abort();}
static uint32_t stack;
static uint32_t invoke(ShimFn fn,const uint32_t *args,unsigned count){
    CPU c={0}; SETREG(&c,R_ESP,stack);P32(stack,0xe7d2e0);
    for(unsigned i=0;i<count;i++)P32(stack+4+4*i,args[i]);
    fn(&c);assert(REG(&c,R_ESP)==stack+4+4*count);return REG(&c,R_EAX);
}
#define CALL(fn,...) invoke(fn,(uint32_t[]){__VA_ARGS__},sizeof((uint32_t[]){__VA_ARGS__})/4)
static int good=1;
#define CHECK(x) do{if(!(x)){fprintf(stderr,"FAIL: %s\n",#x);good=0;}}while(0)
static void reap_all(void){g_d3d.frames+=4;reap();g_d3d.frames+=4;reap();}
int main(int argc,char **argv){
    assert(argc==2);MEM=fnv_reserve_guest();assert(MEM!=MAP_FAILED);make_vtables();stack=gmalloc(256);
    const char *mode=argv[1];
    if(!strcmp(mode,"bound-get-rebind")){
        uint32_t t=new_texture(0,K_TEX,64,64,1,0,21,1),out=gmalloc(4);
        CALL(Dev_SetTexture,0,0,t);
        CHECK(G32(t+4)==2);
        CALL(Unk_Release,t);
        CALL(Dev_GetTexture,0,0,out);CHECK(G32(out)==t);
        CALL(Unk_Release,G32(out));
        CALL(Dev_SetTexture,0,0,0);reap_all();
        // The broken binding model enqueues the same zero-ref object twice. Both the
        // texture and a surface use the 128-byte heap class; live allocations then alias.
        uint32_t live[32];
        for(unsigned i=0;i<32;i++){
            live[i]=gmalloc(60);
            for(unsigned j=0;j<i;j++)if(live[j]==live[i]){
                fprintf(stderr,"ALIAS: live allocations %u/%u share %#x after legal Set/Get/Release/unbind\n",j,i,live[i]);good=0;
                return 1;
            }
        }
        CHECK(ngrave==0);
    }else if(!strcmp(mode,"texture-stages")){
        uint32_t t=new_texture(0,K_TEX,64,64,1,0,21,1);
        for(unsigned i=0;i<32;i++)CALL(Dev_SetTexture,0,i<16?i:i-16+257,t);
        CHECK(G32(t+4)==33);
        for(unsigned i=0;i<50;i++)CALL(Dev_SetTexture,0,0,t);
        CHECK(G32(t+4)==33);
        for(unsigned i=0;i<32;i++)CALL(Dev_SetTexture,0,i<16?i:i-16+257,0);
        CHECK(G32(t+4)==1);CALL(Unk_Release,t);reap_all();
    }else if(!strcmp(mode,"stream-index")){
        uint32_t b=new_buffer(0,K_VB,256,0,0,1),ix=new_buffer(0,K_IB,256,0,101,1);
        CALL(Dev_SetStreamSource,0,0,b,0,16);CALL(Dev_SetIndices,0,ix);
        CHECK(G32(b+4)==2&&G32(ix+4)==2);
        CALL(Unk_Release,b);CALL(Unk_Release,ix);reap_all();
        CHECK(OBJ_KIND(b)==K_VB&&OBJ_KIND(ix)==K_IB);
        CALL(Dev_SetStreamSource,0,0,0,0,0);CALL(Dev_SetIndices,0,0);reap_all();CHECK(ngrave==0);
    }else if(!strcmp(mode,"render-target-depth")){
        uint32_t a=new_surface(0,64,64,21,1,0,0,0,0,0),b=new_surface(0,64,64,21,1,0,0,0,0,0);
        uint32_t d=new_surface(0,64,64,75,2,0,0,0,0,0);
        CALL(Dev_SetRenderTarget,0,0,a);CALL(Dev_SetRenderTarget,0,0,b);CHECK(G32(a+4)==1&&G32(b+4)==2);
        CALL(Dev_SetRenderTarget,0,0,b);CHECK(G32(b+4)==2);
        CALL(Dev_SetDepthStencilSurface,0,d);CALL(Dev_SetDepthStencilSurface,0,d);CHECK(G32(d+4)==2);
        CALL(Dev_SetRenderTarget,0,0,0);CALL(Dev_SetDepthStencilSurface,0,0);CHECK(G32(b+4)==1&&G32(d+4)==1);
        CALL(Unk_Release,a);CALL(Unk_Release,b);CALL(Unk_Release,d);reap_all();CHECK(ngrave==0);
    }else return 2;
    printf("%s: %s\n",good?"PASS":"FAIL",mode);return good?0:1;
}
