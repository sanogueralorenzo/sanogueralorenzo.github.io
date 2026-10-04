// SPDX-License-Identifier: GPL-3.0-only
#define _GNU_SOURCE
#include <assert.h>
#include <errno.h>
#include <linux/futex.h>
#include <pthread.h>
#include <stdint.h>
#include <stdio.h>
#include <sys/mman.h>
#include <sys/syscall.h>
#include <sys/wait.h>
#include <unistd.h>

static struct robust_list_head *query(long pid) {
    struct robust_list_head *head = NULL;
    size_t size = 0;
    errno = EBUSY;
    assert(syscall(SYS_get_robust_list, pid, &head, &size) == 0);
    assert(errno == EBUSY && head && size == sizeof(*head));
    assert(head->futex_offset == -32 && !head->list_op_pending);
    return head;
}

static void *check_thread(void *unused) {
    (void)unused;
    assert(syscall(SYS_gettid) == gettid());
    struct robust_list_head *head = query(0);
    assert(head->list.next == &head->list);
    pthread_mutexattr_t attr;
    pthread_mutex_t mutex;
    assert(!pthread_mutexattr_init(&attr));
    assert(!pthread_mutexattr_setrobust(&attr, PTHREAD_MUTEX_ROBUST));
    assert(!pthread_mutex_init(&mutex, &attr));
    assert(!pthread_mutexattr_destroy(&attr));
    assert(!pthread_mutex_lock(&mutex));
    uintptr_t entry = (uintptr_t)head->list.next;
    assert(entry >= (uintptr_t)&mutex && entry < (uintptr_t)&mutex + sizeof(mutex));
    // Steam uses this backward link when inserting its own IPC mutex.
    assert(*(struct robust_list_head **)(entry - sizeof(void *)) == head);
    for (int i = 0; i < 8; i++) {
        assert(query(gettid()) == head);
        assert((uintptr_t)head->list.next == entry);
    }
    assert(!pthread_mutex_unlock(&mutex));
    assert(!pthread_mutex_destroy(&mutex));
    assert(head->list.next == &head->list);
    size_t length;
    assert(syscall(SYS_get_robust_list, 0, NULL, &length) == -1 && errno == EFAULT);
    assert(syscall(SYS_get_robust_list, -1, &head, &length) == -1);
    return NULL;
}

int main(void) {
    assert(syscall(SYS_getpid) == getpid());
    void *page = (void *)syscall(SYS_mmap, NULL, 4096, PROT_READ | PROT_WRITE,
        MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    assert(page != MAP_FAILED);
    *(volatile int *)page = 42;
    assert(syscall(SYS_munmap, page, 4096) == 0);
    check_thread(NULL);
    pthread_t threads[2];
    for (int i = 0; i < 2; i++) assert(!pthread_create(&threads[i], NULL, check_thread, NULL));
    for (int i = 0; i < 2; i++) assert(!pthread_join(threads[i], NULL));
    pid_t child = fork();
    assert(child >= 0);
    if (!child) { check_thread(NULL); _exit(0); }
    int status;
    assert(waitpid(child, &status, 0) == child && WIFEXITED(status) && !WEXITSTATUS(status));
    assert(syscall(SYS_write, STDOUT_FILENO, "Robust lists verified\n", 22) == 22);
    return 0;
}
