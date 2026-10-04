/* SPDX-License-Identifier: GPL-3.0-only */
#define _GNU_SOURCE
#include <assert.h>
#include <errno.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/syscall.h>
#include <unistd.h>

static int file_with_pages(char *path, size_t size) {
    int fd = mkstemp(path);
    assert(fd >= 0);
    assert(unlink(path) == 0);
    unsigned char *bytes = malloc(size);
    assert(bytes);
    memset(bytes, 0x17, size);
    assert(write(fd, bytes, size) == (ssize_t)size);
    free(bytes);
    return fd;
}

int main(void) {
    size_t page = (size_t)sysconf(_SC_PAGESIZE), size = page * 3;
    char path[] = "/root/.local/share/Steam/.memory-probe-XXXXXX";
    int fd = file_with_pages(path, size);
    unsigned char *image = mmap(NULL, size, PROT_READ | PROT_WRITE, MAP_PRIVATE, fd, 0);
    assert(image != MAP_FAILED);
    const uint32_t code[] = {0x52800540, 0xd65f03c0}; /* mov w0,#42; ret */
    memcpy(image + page, code, sizeof(code));
    assert(syscall(SYS_mprotect, image + page, page, PROT_READ | PROT_EXEC) == -1 && errno == EACCES);
    assert(mprotect(image + page, page, PROT_READ | PROT_EXEC) == 0);
    assert(((int (*)(void))(image + page))() == 42);
    assert(image[0] == 0x17 && image[page - 1] == 0x17 && image[page * 2] == 0x17);
    image[0] = 0x31;
    image[page * 2] = 0x32;
    unsigned char disk;
    assert(pread(fd, &disk, 1, page) == 1 && disk == 0x17);
    assert(mprotect(image + 1, page, PROT_READ | PROT_EXEC) == -1 && errno == EINVAL);
    assert(mprotect(image, page, PROT_NONE) == 0);
    assert(mprotect(image, page, PROT_READ | PROT_EXEC) == -1 && errno == EACCES);
    assert(munmap(image, size) == 0);
    unsigned char *shared = mmap(NULL, page, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
    assert(shared != MAP_FAILED);
    shared[0] = 0x33;
    int shared_result = syscall(SYS_mprotect, shared, page, PROT_READ | PROT_EXEC);
    int shared_errno = errno;
    assert(mprotect(shared, page, PROT_READ | PROT_WRITE) == 0);
    assert(mprotect(shared, page, PROT_READ | PROT_EXEC) == shared_result);
    if (shared_result == -1) assert(errno == shared_errno);
    assert(mprotect(shared, page, PROT_READ | PROT_WRITE) == 0);
    shared[0] = 0x35;
    assert(pread(fd, &disk, 1, 0) == 1 && disk == 0x35);
    assert(shared[0] == 0x35);
    assert(munmap(shared, page) == 0);
    close(fd);
    char unrelated[] = "/tmp/memory-probe-XXXXXX";
    fd = file_with_pages(unrelated, page);
    image = mmap(NULL, page, PROT_READ | PROT_WRITE, MAP_PRIVATE, fd, 0);
    assert(image != MAP_FAILED);
    image[0] = 0x34;
    assert(mprotect(image, page, PROT_READ | PROT_EXEC) == -1 && errno == EACCES);
    assert(image[0] == 0x34);
    assert(munmap(image, page) == 0);
    close(fd);
    puts("Private Steam image execution and mapping boundaries verified");
    return 0;
}
