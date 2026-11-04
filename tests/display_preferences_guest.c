// Use the production COM adapter handler and INI reader with real guest memory.
#include "FNVGuestMemory.h"
#include "../upstream/recomp/host/d3d9.c"
#include <assert.h>
#include <unistd.h>

uint8_t *MEM;
HostImport host_imports[MAX_IMPORTS];
int host_import_count;
_Thread_local uint32_t host_last_error;
extern const ShimTable file_shims;

// Only the file shim's handle storage is supplied by this fixture. Its path
// resolver, profile parser and file reads are the actual production module.
static void *objects[32];
static int types[32];
uint32_t handle_new(int type, void *object) {
    for (unsigned i = 1; i < 32; ++i) if (!objects[i]) {
        objects[i] = object; types[i] = type; return i;
    }
    abort();
}
void *handle_get(uint32_t h, int type) { return h < 32 && types[h] == type ? objects[h] : NULL; }
int handle_type(uint32_t h) { return h < 32 ? types[h] : 0; }
void handle_close(uint32_t h) {
    if (h < 32 && objects[h]) {
        if (types[h] == H_FILE) { close(*(int *)objects[h]); free(objects[h]); }
        objects[h] = NULL; types[h] = 0;
    }
}
void rt_trap(CPU *c, int n, uint32_t address) {
    (void)c;
    fprintf(stderr, "Unexpected guest trap %d at %#x\n", n, address);
    abort();
}

static uint32_t guest_stack, adapter, profile_buffer;
static uint32_t invoke(ShimFn fn, const uint32_t *arguments, unsigned count) {
    CPU c = {0};
    SETREG(&c, R_ESP, guest_stack);
    P32(guest_stack, 0x004da5de);
    for (unsigned i = 0; i < count; ++i) P32(guest_stack + 4 + 4 * i, arguments[i]);
    fn(&c);
    assert(REG(&c, R_ESP) == guest_stack + 4 + 4 * count);
    return REG(&c, R_EAX);
}
static uint32_t guest_string(const char *text) {
    uint32_t p = gmalloc((uint32_t)strlen(text) + 1);
    assert(p);
    strcpy((char *)MEM + p, text);
    return p;
}

const char *display_preferences_guest_init(const char *root) {
    assert(!setenv("FNV_ROOT", root, 1));
    MEM = fnv_reserve_guest();
    assert(MEM != MAP_FAILED);
    make_vtables();
    guest_stack = gmalloc(256);
    adapter = gmalloc(1100);
    profile_buffer = gmalloc(2048);
    uint32_t arguments[] = {0, 0, 0, adapter};
    assert(invoke(D3D_GetAdapterIdentifier, arguments, 4) == 0);
    assert(memchr(MEM + adapter + 512, 0, 512));
    const char *description = (char *)MEM + adapter + 512;
    assert(description[0]);
    return description;
}

const char *display_preferences_guest_profile(const char *section, const char *key) {
    uint32_t arguments[] = {
        guest_string(section), guest_string(key), guest_string("<missing>"),
        profile_buffer, 2048,
        guest_string("C:\\Games\\FalloutNV\\UserDocuments\\My Games\\FalloutNV\\FalloutPrefs.ini")
    };
    for (int i = 0; i < file_shims.count; ++i) {
        if (!strcmp(file_shims.list[i].name, "GetPrivateProfileStringA")) {
            uint32_t length = invoke(file_shims.list[i].fn, arguments, 6);
            assert(length < 2048 && MEM[profile_buffer + length] == 0);
            for (unsigned j = 0; j < 6; ++j) if (j != 3 && j != 4) gfree(arguments[j]);
            return (char *)MEM + profile_buffer;
        }
    }
    abort();
}
