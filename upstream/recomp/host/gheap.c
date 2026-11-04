// Guest heap: size-class free lists for small blocks, a first-fit page allocator for large ones.
// Everything lives in [HEAP_LO, HEAP_HI) of the guest space so guest pointers stay 32-bit.
#include <stdio.h>
#include <pthread.h>
#include <stdlib.h>
#include "host.h"

// one lock for the whole guest heap: the game allocates from many threads
static pthread_mutex_t hl = PTHREAD_MUTEX_INITIALIZER;
#define L pthread_mutex_lock(&hl)
#define UL pthread_mutex_unlock(&hl)

#define HEAP_LO 0x40000000u
#define HEAP_HI 0xF0000000u
#define HDR 16                       // [size:4][class:4][pad:8] before every block (16-aligned)
#define NCLASS 20                    // 16 B .. 8 MB
static uint32_t brk_ = HEAP_LO;
static struct {uint32_t lo,hi;} fixed_ranges[4096];
static unsigned fixed_count;
// Shared address ownership: fixed Win32 reservations cannot cover current heap storage,
// and future heap/page allocations must skip them. Called under VirtualAlloc's outer lock.
int gheap_reserve_fixed(uint32_t lo,uint32_t hi){
    if(lo>=hi)return 0;
    L;
    int ok=!(brk_>HEAP_LO&&lo<brk_&&HEAP_LO<hi);
    for(unsigned i=0;ok&&i<fixed_count;i++)if(lo<fixed_ranges[i].hi&&fixed_ranges[i].lo<hi)ok=0;
    if(ok&&lo<HEAP_HI&&HEAP_LO<hi){
        if(fixed_count==4096)ok=0;
        else{fixed_ranges[fixed_count].lo=lo;fixed_ranges[fixed_count++].hi=hi;}
    }
    UL;return ok;
}
// accounting (bytes taken from the bump pointer, by kind; live bytes handed out by gmalloc)
static uint64_t st_bump_class, st_bump_huge, st_bump_pages, st_huge_freed, st_live;
static uint32_t freelist[NCLASS];
static uint32_t hugelist;            // freed huge blocks: [size:4][-1:4][next:4][capacity:4]

// Independent host ownership ledger. Guest writes cannot rewrite these records.
// Guards use existing size-class slack, so guest addresses and capacities do not change.
typedef struct {uint32_t q,size,capacity,kind,live;uint64_t serial;} Allocation;
static Allocation *ownership;static size_t ownership_cap,ownership_used;static uint64_t allocation_serial;
#if defined(__GNUC__)
__attribute__((weak)) void host_heap_fault(const char *why,uint32_t q,uint32_t expected,uint32_t actual){(void)why;(void)q;(void)expected;(void)actual;}
#endif
static void heap_fault(const char *why,uint32_t q,uint32_t expected,uint32_t actual){
    fprintf(stderr,"[heap-corruption] reason=%s guest=%#x expected=%#x actual=%#x serial=%llu\n",why,q,expected,actual,(unsigned long long)allocation_serial);
#if defined(__GNUC__)
    if(host_heap_fault)host_heap_fault(why,q,expected,actual);
#endif
    fflush(stderr);abort();
}
static size_t allocation_hash(uint32_t q,size_t cap){return ((uint64_t)(q>>4)*2654435761u)&(cap-1);}
static void ownership_grow(void){
    size_t cap=ownership_cap?ownership_cap*2:4096;
    if(cap>1u<<22)heap_fault("ownership-ledger-capacity",0,1u<<22,(uint32_t)cap);
    Allocation *next=calloc(cap,sizeof *next);if(!next)heap_fault("ownership-ledger-allocation",0,0,0);
    for(size_t i=0;i<ownership_cap;i++)if(ownership[i].q){size_t at=allocation_hash(ownership[i].q,cap);while(next[at].q)at=(at+1)&(cap-1);next[at]=ownership[i];}
    free(ownership);ownership=next;ownership_cap=cap;
}
static Allocation *allocation_find(uint32_t q,int insert){
    if(!ownership_cap || (insert && (ownership_used+1)*2>=ownership_cap))ownership_grow();
    size_t at=allocation_hash(q,ownership_cap);
    while(ownership[at].q && ownership[at].q!=q)at=(at+1)&(ownership_cap-1);
    if(!ownership[at].q){if(!insert)return NULL;ownership[at].q=q;ownership_used++;}
    return &ownership[at];
}
static unsigned guard_bytes(Allocation *a){uint32_t slack=a->capacity-a->size;return slack<16?slack:16;}
static void allocation_guard(Allocation *a){memset(MEM+a->q+a->size,0xa7,guard_bytes(a));}
static Allocation *allocation_check(uint32_t q){
    Allocation *a=allocation_find(q,0);
    if(!a)heap_fault("unowned-pointer",q,0,0);
    if(!a->live)heap_fault("freed-pointer",q,(uint32_t)a->serial,0);
    if(G32(q-HDR)!=a->size)heap_fault("size-header-overwrite",q,a->size,G32(q-HDR));
    if(G32(q-HDR+4)!=a->kind)heap_fault("class-header-overwrite",q,a->kind,G32(q-HDR+4));
    if(a->kind==0xFFFFFFFFu&&G32(q-HDR+12)!=a->capacity+HDR)heap_fault("capacity-header-overwrite",q,a->capacity+HDR,G32(q-HDR+12));
    for(unsigned i=0;i<guard_bytes(a);i++)if(MEM[q+a->size+i]!=0xa7)heap_fault("tail-overwrite",q+a->size+i,0xa7,MEM[q+a->size+i]);
    return a;
}
static uint32_t allocation_record(uint32_t q,uint32_t size,uint32_t capacity,uint32_t kind){
    Allocation *a=allocation_find(q,1);if(a->live)heap_fault("live-allocation-alias",q,(uint32_t)a->serial,0);
    a->size=size;a->capacity=capacity;a->kind=kind;a->live=1;a->serial=++allocation_serial;allocation_guard(a);return q;
}
static void free_block_check(uint32_t p,uint32_t kind){
    Allocation *a=allocation_find(p+HDR,0);
    if(!a||a->live||a->kind!=kind)heap_fault("free-list-pointer",p+HDR,kind,a?a->kind:0);
    if(G32(p)!=a->size||G32(p+4)!=kind)heap_fault("freed-header-overwrite",p+HDR,kind,G32(p+4));
    if(kind==0xFFFFFFFFu&&G32(p+12)!=a->capacity+HDR)heap_fault("freed-capacity-overwrite",p+HDR,a->capacity+HDR,G32(p+12));
    for(unsigned i=0;i<guard_bytes(a);i++)if(MEM[a->q+a->size+i]!=0xa7)heap_fault("freed-tail-overwrite",a->q+a->size+i,0xa7,MEM[a->q+a->size+i]);
}

static int cls(uint32_t n) { int c = 0; uint32_t s = 16; while (s < n && c < NCLASS - 1) { s <<= 1; c++; } return c; }
static uint32_t csize(int c) { return 16u << c; }

static uint32_t bump(uint32_t n) {
    uint64_t p=((uint64_t)brk_+15)&~15ull;
    for(;;){
        int moved=0;
        for(unsigned i=0;i<fixed_count;i++)if(p<fixed_ranges[i].hi&&fixed_ranges[i].lo<p+n){
            fprintf(stderr,"[address-map] heap skips reserved %#x..%#x request=%u\n",fixed_ranges[i].lo,fixed_ranges[i].hi,n);
            p=((uint64_t)fixed_ranges[i].hi+4095)&~4095ull;moved=1;break;
        }
        if(!moved)break;
    }
    if(p+n>HEAP_HI){fprintf(stderr,"[gheap] out of guest memory after address reservations\n");abort();}
    brk_=(uint32_t)(p+n);return (uint32_t)p;
}

static uint32_t gmalloc_u(uint32_t size) {
    if (size == 0) size = 1;
    if (size > csize(NCLASS - 1) - HDR) {        // huge: dedicated pages, class = -1
        uint32_t need = ((size + HDR) + 0xFFF) & ~0xFFFu;
        // best fit among freed huge blocks no more than 2x the request
        uint32_t *link = &hugelist, *best_link = NULL, best = 0;
        for (uint32_t q = hugelist; q; link = (uint32_t *)(void *)(MEM + q + 8), q = G32(q + 8)) {
            free_block_check(q,0xFFFFFFFFu);
            uint32_t cap = G32(q + 12);
            if (cap >= need && cap <= 2 * need && (!best || cap < G32(best + 12))) { best = q; best_link = link; }
        }
        if (best) {
            *best_link = G32(best + 8);
            memset(MEM + best + HDR, 0, size);
            P32(best, size); P32(best + 4, 0xFFFFFFFFu);
            st_live += size; st_huge_freed -= G32(best + 12);
            return allocation_record(best+HDR,size,G32(best+12)-HDR,0xFFFFFFFFu);
        }
        uint32_t p = bump(need);
        st_bump_huge += need; st_live += size;
        P32(p, size); P32(p + 4, 0xFFFFFFFFu); P32(p + 12, need);
        return allocation_record(p+HDR,size,need-HDR,0xFFFFFFFFu);
    }
    int c = cls(size + HDR);
    uint32_t p = freelist[c];
    if (p) { free_block_check(p,(uint32_t)c);freelist[c] = G32(p + 8); }
    else { p = bump(csize(c)); st_bump_class += csize(c); }
    st_live += csize(c);
    memset(MEM + p + HDR, 0, size);
    P32(p, size); P32(p + 4, (uint32_t)c);
    return allocation_record(p+HDR,size,csize(c)-HDR,(uint32_t)c);
}

static void gfree_u(uint32_t q) {
    if (!q) return;
    Allocation *a=allocation_check(q);a->live=0;
    uint32_t p = q - HDR, c = G32(p + 4);
    if (c == 0xFFFFFFFFu) {                      // huge: onto the reuse list
        st_huge_freed += G32(p + 12); st_live -= G32(p);
        P32(p + 8, hugelist); hugelist = p;
        return;
    }
    st_live -= csize((int)c);
    P32(p + 8, freelist[c]);
    freelist[c] = p;
}

static uint32_t gsize_u(uint32_t q){return q?allocation_check(q)->size:0;}
uint32_t gsize(uint32_t q) { L;uint32_t n=gsize_u(q);UL;return n; }

static uint32_t grealloc_u(uint32_t q, uint32_t size) {
    if (!q) return gmalloc_u(size);
    uint32_t old = gsize_u(q);
    uint32_t c = G32(q - HDR + 4);
    if (c != 0xFFFFFFFFu && (uint64_t)size + HDR <= csize((int)c)) { P32(q-HDR,size);Allocation *a=allocation_find(q,0);a->size=size;allocation_guard(a);return q; }
    uint32_t n = gmalloc_u(size);
    memcpy(MEM + n, MEM + q, old < size ? old : size);
    gfree_u(q);
    return n;
}

static uint32_t gpages_u(uint32_t size) {
    brk_ = (brk_ + 0xFFF) & ~0xFFFu;
    uint32_t p = bump((size + 0xFFF) & ~0xFFFu);
    st_bump_pages += (size + 0xFFF) & ~0xFFFu;
    memset(MEM + p, 0, size);
    return p;
}

uint32_t gmalloc(uint32_t size) { L; uint32_t r = gmalloc_u(size); UL; return r; }
void gfree(uint32_t q) { L; gfree_u(q); UL; }
uint32_t grealloc(uint32_t q, uint32_t size) { L; uint32_t r = grealloc_u(q, size); UL; return r; }
uint32_t gpages(uint32_t size) { L; uint32_t r = gpages_u(size); UL; return r; }

void gheap_report(void) {
    L;
    fprintf(stderr, "[gheap] used %u MB of %u: class %llu MB, huge %llu MB (freed-not-reused %llu MB), pages %llu MB, live %llu MB\n",
            (brk_ - HEAP_LO) >> 20, (HEAP_HI - HEAP_LO) >> 20, (unsigned long long)(st_bump_class >> 20),
            (unsigned long long)(st_bump_huge >> 20), (unsigned long long)(st_huge_freed >> 20),
            (unsigned long long)(st_bump_pages >> 20), (unsigned long long)(st_live >> 20));
    UL;
}
