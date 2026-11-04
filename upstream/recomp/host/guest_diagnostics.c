// Read-only, bounded samples inserted at explicitly selected generated entries.
#include <stdio.h>
#include "host.h"

void rt_diag_watch(CPU *c,uint32_t entry,const uint32_t *offsets,unsigned n) {
    static _Thread_local struct {uint32_t entry;uint64_t calls;} slots[32];
    unsigned slot=0;
    for(;slot<32 && slots[slot].entry && slots[slot].entry!=entry;slot++);
    if(slot==32 || !entry || n>16)return;
    slots[slot].entry=entry;uint64_t count=++slots[slot].calls;
    if(count>4 && (count&(count-1)))return; // four initial samples, then powers of two
    uint32_t sp=REG(c,R_ESP),object=REG(c,R_ECX),teb=REG(c,272);
    fprintf(stderr,"[probe-state] tid=%u entry=%#x sample=%llu caller=%#x object=%#x fields=",
        G32(teb+0x24),entry,(unsigned long long)count,sp<=0xfffffffbu?G32(sp):0,object);
    for(unsigned i=0;i<n;i++) {
        if(object && offsets[i]<=4096 && object<=0xfffffffbu-offsets[i])
            fprintf(stderr,"%#x:%#x%s",offsets[i],G32(object+offsets[i]),i+1==n?"":",");
        else fprintf(stderr,"%#x:unavailable%s",offsets[i],i+1==n?"":",");
    }
    uint32_t lo=G32(teb+8),hi=G32(teb+4),fp=REG(c,20);
    fprintf(stderr," frames=");
    if(hi>=lo && hi-lo<=64u*1024*1024)for(unsigned i=0;i<8 && fp>=lo && fp<=hi && hi-fp>=8;i++) {
        fprintf(stderr,"%#x,",G32(fp+4));uint32_t next=G32(fp);
        if(next<=fp)break;fp=next;
    }
    if(sp>=lo && sp<=hi && hi-sp>=20){
        fprintf(stderr," args=");
        for(unsigned i=0;i<4;i++)fprintf(stderr,"%#x%s",G32(sp+4+4*i),i==3?"":",");
    }
    fprintf(stderr,"\n");
}
