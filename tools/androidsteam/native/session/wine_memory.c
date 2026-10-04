/* SPDX-License-Identifier: GPL-3.0-only */
#define _GNU_SOURCE
#include <dlfcn.h>
#include <errno.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <unistd.h>

static int (*host_mprotect)(void *, size_t, int);
__attribute__((constructor)) static void resolve(void) {
    host_mprotect = dlsym(RTLD_NEXT, "mprotect");
}

/* Wine relocates ARM64X PE images in a private file mapping. Android refuses
 * executable protection after that mapping is dirtied (execmod), but permits
 * anonymous JIT memory. Preserve only those private Steam image bytes in an
 * anonymous mapping. Shared, unreadable and unrelated mappings keep failing. */
static int private_steam_image(uintptr_t begin, uintptr_t end) {
    FILE *maps = fopen("/proc/self/maps", "re");
    if (!maps) return 0;
    char line[4096], mode[5];
    uintptr_t low, high, cursor = begin;
    while (cursor < end && fgets(line, sizeof(line), maps)) {
        if (sscanf(line, "%lx-%lx %4s", &low, &high, mode) != 3 || high <= cursor) continue;
        if (low > cursor || mode[0] != 'r' || mode[3] != 'p' ||
            !strstr(line, "/files/home/.local/share/Steam/")) break;
        cursor = high < end ? high : end;
    }
    fclose(maps);
    return cursor == end;
}

int mprotect(void *address, size_t length, int protection) {
    int result = host_mprotect(address, length, protection);
    if (!result || errno != EACCES || !(protection & PROT_EXEC) || !length) return result;
    int failure = errno;
    long page_size = sysconf(_SC_PAGESIZE);
    if (page_size <= 0) { errno = failure; return -1; }
    size_t page = (size_t)page_size;
    uintptr_t start = (uintptr_t)address;
    if (!page || start % page || length > SIZE_MAX - page + 1) { errno = failure; return -1; }
    size_t size = (length + page - 1) / page * page;
    if (size > UINTPTR_MAX - start || !private_steam_image(start, start + size)) { errno = failure; return -1; }
    void *copy = mmap(NULL, size, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    if (copy == MAP_FAILED) return -1;
    memcpy(copy, address, size);
    __builtin___clear_cache(copy, (char *)copy + size);
    if (host_mprotect(copy, size, protection)) {
        failure = errno;
        munmap(copy, size);
        errno = failure;
        return -1;
    }
    if (mremap(copy, size, size, MREMAP_MAYMOVE | MREMAP_FIXED, address) == MAP_FAILED) {
        failure = errno;
        munmap(copy, size);
        errno = failure;
        return -1;
    }
    return 0;
}
