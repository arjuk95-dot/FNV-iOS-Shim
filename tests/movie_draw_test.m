// Authored pixels through the original movie's D3D9 COM sequence and real Metal.
// Original EC0280: XYZRHW|TEX1 (0x104), 24-byte vertices, triangle strip, null VS/PS.
#import <Foundation/Foundation.h>
#include "FNVGuestMemory.h"
#include "shims.h"
#ifndef FNV_METAL_SOURCE
#define FNV_METAL_SOURCE "../upstream/recomp/host/d3d9_metal.m"
#endif
#include FNV_METAL_SOURCE
#include <assert.h>

uint8_t *MEM;
HostImport host_imports[MAX_IMPORTS];
int host_import_count;
extern D3DState g_d3d;
extern const ShimTable d3d9_shims;
static uint32_t test_stack, device;
static int failures;
enum { TEST_W=128, TEST_H=96 };

// No native window/input is needed. FNV_HEADLESS still executes real GPU commands.
CAMetalLayer *fnv_surface(id<MTLDevice> d,CGSize s){(void)d;(void)s;abort();}
void fnv_resize_surface(CGSize s){(void)s;}
void fnv_wait_active(void){}
void input_script_tick(uint64_t f){(void)f;}
void input_frame_draws(uint64_t n){(void)n;}
int input_take_dump_request(void){return 0;}
void rt_trap(CPU *c,int kind,uint32_t address){(void)c;fprintf(stderr,"unexpected trap %d at %#x\n",kind,address);abort();}

static void check(const char *name,int ok){printf("%s: %s\n",ok?"PASS":"FAIL",name);failures+=!ok;}
static uint32_t invoke(ShimFn fn,const uint32_t *args,unsigned n){
    CPU c={0};SETREG(&c,R_ESP,test_stack);P32(test_stack,0x12345678);
    for(unsigned i=0;i<n;i++)P32(test_stack+4+4*i,args[i]);
    fn(&c);assert(REG(&c,R_ESP)==test_stack+4+4*n);return REG(&c,R_EAX);
}
static uint32_t method(uint32_t object,unsigned slot,const uint32_t *extra,unsigned n){
    uint32_t thunk=G32(G32(object)+4*slot),args[16]={object};
    assert(n<16&&thunk>=IMPORT_THUNK_BASE&&(thunk-IMPORT_THUNK_BASE)%4==0);
    unsigned i=(thunk-IMPORT_THUNK_BASE)/4;assert(i<(unsigned)host_import_count);
    for(unsigned j=0;j<n;j++)args[j+1]=extra[j];
    return invoke(host_imports[i].fn,args,n+1);
}
#define COM(o,s,...) method(o,s,(uint32_t[]){__VA_ARGS__},sizeof((uint32_t[]){__VA_ARGS__})/4)
#define HR(o,s,...) assert(COM(o,s,__VA_ARGS__)==0)
static uint32_t float_bits(float f){uint32_t v;memcpy(&v,&f,4);return v;}

static void create_device(void){
    uint32_t d3d=0;
    for(int i=0;i<d3d9_shims.count;i++)if(!strcmp(d3d9_shims.list[i].name,"Direct3DCreate9"))
        d3d=invoke(d3d9_shims.list[i].fn,(uint32_t[]){32},1);
    assert(d3d);
    uint32_t pp=gmalloc(56),out=gmalloc(4);memset(MEM+pp,0,56);
    P32(pp,TEST_W);P32(pp+4,TEST_H);P32(pp+8,21);P32(pp+12,1);P32(pp+32,1);
    HR(d3d,16,0,1,0,0,pp,out);device=G32(out);assert(device);
    // A real saved declaration checks that SetFVF cleanup restores its owner.
    const uint8_t elements[16]={0,0,0,0,2,0,0,0,255,0,0,0,17,0,0,0};
    uint32_t declaration=gmalloc(sizeof elements);memcpy(MEM+declaration,elements,sizeof elements);
    HR(device,86,declaration,out);HR(device,87,G32(out));
    // Nonzero origin exercises viewport-relative conversion of pretransformed XY.
    uint32_t vp=gmalloc(24);const uint32_t viewport[6]={8,4,112,88,0,0x3f800000};memcpy(MEM+vp,viewport,sizeof viewport);
    HR(device,47,vp);
}

// RGB colors have alpha zero deliberately: X8R8G8B8 must sample opaque.
static const uint32_t colors[2][4]={
    {0x00ef1010,0x0010ef10,0x001010ef,0x00efef10},
    {0x00ef10ef,0x0010efef,0x00ef8010,0x008010ef}
};
static void update_texture(uint32_t texture,unsigned variant){
    uint32_t locked=gmalloc(8);HR(texture,19,0,locked,0,0);
    uint32_t pitch=G32(locked),pixels=G32(locked+4);assert(pitch>=32*4&&pixels);
    for(unsigned y=0;y<32;y++)for(unsigned x=0;x<32;x++)
        P32(pixels+y*pitch+4*x,colors[variant][(y>=16)*2+(x>=16)]);
    HR(texture,20,0);gfree(locked);
}
static uint32_t create_texture(unsigned variant){
    uint32_t out=gmalloc(4);HR(device,23,32,32,1,0x200,22,0,out,0);
    uint32_t texture=G32(out);assert(texture);gfree(out);update_texture(texture,variant);return texture;
}
static void original_state(void){
    HR(device,57,27,0);HR(device,57,7,0);HR(device,57,14,0);HR(device,57,168,15);
    HR(device,67,0,4,2);HR(device,67,0,2,2);HR(device,67,0,5,2);HR(device,67,0,1,4);
    // The original helper leaves COLORARG2 at the previous stage/current color;
    // initialize its documented stage-zero default explicitly for this fixture.
    HR(device,67,0,3,1);
    HR(device,69,0,6,2);HR(device,69,0,5,2);HR(device,69,0,7,2);
    HR(device,69,0,1,3);HR(device,69,0,2,3);
    HR(device,92,0);HR(device,107,0);
}
typedef struct {float x,y,z,rhw,u,v;} MovieVertex;
static void draw_tile(uint32_t texture,float left,float right){
    MovieVertex vertices[4]={{left,16,0,1,0,0},{left,80,0,1,0,1},{right,16,0,1,1,0},{right,80,0,1,1,1}};
    uint32_t data=gmalloc(sizeof vertices),saved=gmalloc(4);memcpy(MEM+data,vertices,sizeof vertices);
    HR(device,65,0,texture);HR(device,88,saved);uint32_t declaration=G32(saved);
    HR(device,89,0x104);HR(device,83,5,2,data,sizeof(MovieVertex));
    HR(device,89,0);HR(device,87,declaration);COM(declaration,2);
    assert(!g_d3d.fvf&&g_d3d.decl==declaration&&!g_d3d.stream[0]);
    gfree(data);gfree(saved);
}
static NSData *read_pixels(void){
    end_pass();ensure_cmd();NSUInteger level,slice;
    id<MTLTexture> target=surf_target(g_d3d.rt[0],&level,&slice);assert(target);
    NSUInteger pitch=TEST_W*4;
    id<MTLBuffer> buffer=[dev newBufferWithLength:pitch*TEST_H options:MTLResourceStorageModeShared];assert(buffer);
    id<MTLBlitCommandEncoder> blitter=[cmd blitCommandEncoder];
    [blitter copyFromTexture:target sourceSlice:slice sourceLevel:level sourceOrigin:MTLOriginMake(0,0,0)
        sourceSize:MTLSizeMake(TEST_W,TEST_H,1) toBuffer:buffer destinationOffset:0 destinationBytesPerRow:pitch destinationBytesPerImage:pitch*TEST_H];
    [blitter endEncoding];[cmd commit];[cmd waitUntilCompleted];
    check("real Metal command buffer completes",cmd.status==MTLCommandBufferStatusCompleted);
    if(cmd.error)fprintf(stderr,"Metal: %s\n",cmd.error.localizedDescription.UTF8String);
    cmd=nil;return [NSData dataWithBytes:buffer.contents length:pitch*TEST_H];
}
static NSData *draw_frame(uint32_t left,uint32_t right){
    HR(device,43,0,0,1,0xff000000,float_bits(1),0);HR(device,41);
    original_state();draw_tile(left,16,64);draw_tile(right,64,112);
    HR(device,57,7,1);HR(device,57,14,1);HR(device,65,0,0);HR(device,42);
    check("original cleanup restores declaration, texture, FVF, and UP stream",g_d3d.decl&&!g_d3d.fvf&&!g_d3d.tex[0]&&!g_d3d.stream[0]);
    return read_pixels();
}
static int near_color(NSData *data,unsigned x,unsigned y,uint32_t color){
    const uint8_t *p=(const uint8_t *)data.bytes+4*(y*TEST_W+x);
    for(unsigned c=0;c<3;c++)if(abs((int)p[c]-(int)((color>>(8*c))&255))>8)return 0;
    return p[3]>=247;
}
static int black_image(NSData *data){
    const uint8_t *p=data.bytes;for(unsigned i=0;i<TEST_W*TEST_H;i++)if(p[4*i]||p[4*i+1]||p[4*i+2])return 0;return 1;
}
static void check_frame(NSData *data,unsigned left_variant){
    check("left tile preserves top/bottom and RGB orientation",
        near_color(data,28,32,colors[left_variant][0])&&near_color(data,52,32,colors[left_variant][1])&&
        near_color(data,28,64,colors[left_variant][2])&&near_color(data,52,64,colors[left_variant][3]));
    check("second tile renders independently",
        near_color(data,76,32,colors[1][0])&&near_color(data,100,32,colors[1][1])&&
        near_color(data,76,64,colors[1][2])&&near_color(data,100,64,colors[1][3]));
    check("letterbox and outside viewport remain black",
        near_color(data,64,8,0)&&near_color(data,64,88,0)&&near_color(data,4,48,0)&&near_color(data,124,48,0));
    check("adjacent movie tiles leave no black seam",!near_color(data,63,32,0)&&!near_color(data,64,32,0));
}
int main(void){@autoreleasepool{
    setenv("FNV_HEADLESS","1",1);unsetenv("FNV_RECORD");unsetenv("FNV_DUMP_FRAMES");
    id<MTLDevice> available=MTLCreateSystemDefaultDevice();
    if(!available){
#ifdef FNV_MOVIE_REFERENCE
        D3DState state={0};state.fvf=0x104;
        d3d_backend_draw_up(&state,5,2,1,24,0,0,0,0);
        check("historical renderer rejects exact movie draw before accessing a GPU",ff_skipped==1&&draws_done==0);
        puts("SKIP: Metal pixel readback unavailable; historical rejection only was reproduced.");return failures?1:0;
#else
        puts("SKIP: no Metal device; no GPU rendering or pixel checks ran.");return 77;
#endif
    }
    MEM=fnv_reserve_guest();assert(MEM!=MAP_FAILED);test_stack=gmalloc(256);create_device();
    uint32_t left=create_texture(0),right=create_texture(1);uint64_t skipped_before=ff_skipped;
    NSData *first=draw_frame(left,right);
#ifdef FNV_MOVIE_REFERENCE
    check("historical original movie sequence produces only the black clear",black_image(first));
    check("historical backend drops both fixed-function tile draws",ff_skipped==skipped_before+2&&draws_done==0);
    return failures?1:0;
#else
    check_frame(first,0);
    check("both original movie tile draws reach Metal",draws_done==2&&ff_skipped==skipped_before);
    update_texture(left,1);NSData *second=draw_frame(left,right);check_frame(second,1);
    check("LockRect/UnlockRect uploads a changed movie frame",!near_color(first,28,32,colors[1][0])&&near_color(second,28,32,colors[1][0]));
    check("updated movie draws still reach Metal",draws_done==4&&ff_skipped==skipped_before);
    // Keep unsupported fixed-function layouts outside this deliberately narrow path.
    HR(device,89,4);MovieVertex vertices[4]={{0}};uint32_t v=gmalloc(sizeof vertices);memcpy(MEM+v,vertices,sizeof vertices);
    HR(device,83,5,2,v,sizeof(MovieVertex));check("unsupported FVF remains rejected",ff_skipped==skipped_before+1&&draws_done==4);
    HR(device,89,0);HR(device,65,0,0);COM(left,2);COM(right,2);
    return failures?1:0;
#endif
}}
