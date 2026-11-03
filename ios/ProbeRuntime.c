// Minimal process globals for the synthetic call sequence. The game uses host.c.
#include "host.h"
#include <stdio.h>
#include <stdlib.h>
uint8_t *MEM;
HostImport host_imports[MAX_IMPORTS];
int host_import_count;
void rt_trap(CPU *cpu, int reason, uint32_t address) {
    (void)cpu;
    fprintf(stderr, "probe trap %d at %#x\n", reason, address);
    abort();
}
