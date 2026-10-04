/* SPDX-License-Identifier: GPL-3.0-only
 * Adapted from DroidDeck tools/linuxfs/preload/robust.c at
 * 255c64551ec7d5a810da622d918eb88ffdccb231; see THIRD_PARTY.md.
 *
 * Android blocks glibc's set_robust_list. Steam needs the current thread's
 * actual glibc list, rather than the stale head returned by the kernel.
 * A private robust mutex reveals that head without private libc offsets.
 */
#define _GNU_SOURCE
#include <dlfcn.h>
#include <errno.h>
#include <linux/futex.h>
#include <pthread.h>
#include <stdint.h>
#include <sys/syscall.h>
#include <sys/uio.h>
#include <unistd.h>

__attribute__((visibility("hidden"))) long (*deck_real_syscall)(long, ...);

__attribute__((constructor)) static void resolve_syscall(void) {
    deck_real_syscall = dlsym(RTLD_NEXT, "syscall");
}

__attribute__((visibility("hidden"))) long deck_missing_syscall(void) {
    errno = ENOSYS;
    return -1;
}

static struct robust_list_head *thread_head(void) {
    pthread_mutexattr_t attr;
    pthread_mutex_t mutex;
    struct robust_list_head *head = NULL;
    if (pthread_mutexattr_init(&attr)) return NULL;
    int error = pthread_mutexattr_setrobust(&attr, PTHREAD_MUTEX_ROBUST);
    if (!error) error = pthread_mutex_init(&mutex, &attr);
    pthread_mutexattr_destroy(&attr);
    if (error) return NULL;
    if (pthread_mutex_lock(&mutex)) { pthread_mutex_destroy(&mutex); return NULL; }
    uintptr_t lo = (uintptr_t)&mutex, hi = lo + sizeof(mutex);
    for (uintptr_t p = lo; p + sizeof(void *) <= hi && !head; p += sizeof(void *)) {
        struct robust_list_head *candidate = *(struct robust_list_head **)p;
        struct robust_list_head copy;
        struct iovec local = {&copy, sizeof(copy)}, remote = {candidate, sizeof(copy)};
        if ((uintptr_t)candidate & (sizeof(void *) - 1)) continue;
        // Failed reads reject lock words and tids without dereferencing them.
        if (process_vm_readv(getpid(), &local, 1, &remote, 1, 0) != sizeof(copy)) continue;
        uintptr_t entry = (uintptr_t)copy.list.next;
        if (entry >= lo && entry < hi && copy.futex_offset < 0 && copy.futex_offset > -256)
            head = candidate;
    }
    pthread_mutex_unlock(&mutex);
    pthread_mutex_destroy(&mutex);
    return head;
}

__attribute__((visibility("hidden"))) long deck_get_robust_list(
        long number, long pid, struct robust_list_head **output, size_t *length) {
    if (pid != 0 && pid != gettid())
        return deck_real_syscall ? deck_real_syscall(number, pid, output, length) : deck_missing_syscall();
    int saved_errno = errno;
    struct robust_list_head *head = thread_head();
    if (!head) return deck_missing_syscall();
    size_t size = sizeof(*head);
    struct iovec local[] = {{&head, sizeof(head)}, {&size, sizeof(size)}};
    struct iovec remote[] = {{output, sizeof(head)}, {length, sizeof(size)}};
    if (process_vm_writev(getpid(), local, 2, remote, 2, 0) != sizeof(head) + sizeof(size)) {
        errno = EFAULT;
        return -1;
    }
    errno = saved_errno;
    return 0;
}
