/* SPDX-License-Identifier: GPL-3.0-only */
#define _GNU_SOURCE
#include <dlfcn.h>
#include <errno.h>
#include <fcntl.h>
#include <sys/mman.h>

/* Android rejects shared mappings of sealed keymaps received by older Wayland
 * clients. An immutable read-only buffer has identical contents privately mapped.
 * Keep writable and unsealed graphics/audio buffers shared. */
void *mmap(void *address, size_t length, int protection, int flags, int fd, off_t offset) {
    void *(*real_mmap)(void *, size_t, int, int, int, off_t) = dlsym(RTLD_NEXT, "mmap");
    if (!real_mmap) { errno = ENOSYS; return MAP_FAILED; }
    if (fd >= 0 && protection == PROT_READ && (flags & MAP_SHARED)) {
        int seals = fcntl(fd, F_GET_SEALS);
        if (seals >= 0 && (seals & F_SEAL_WRITE)) flags = (flags & ~MAP_SHARED) | MAP_PRIVATE;
    }
    return real_mmap(address, length, protection, flags, fd, offset);
}

void *mmap64(void *address, size_t length, int protection, int flags, int fd, off64_t offset)
    __attribute__((alias("mmap")));
