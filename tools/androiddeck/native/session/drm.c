/*
 * SPDX-License-Identifier: GPL-3.0-only
 * Adapted from DroidDeck tools/linuxfs/preload/drm.c at
 * 255c64551ec7d5a810da622d918eb88ffdccb231; see THIRD_PARTY.md and LICENSE.
 *
 * GEM handle emulation for the KGSL device presented as a DRM render node.
 *
 * Compositors and Mesa validate or convert dma-bufs with PRIME ioctls on the render node; KGSL
 * has no GEM. Handles only serve as tokens to these callers, so a table of duplicated dma-buf
 * descriptors stands in for the kernel's, and every other device is left to libdrm.
 */
#define _GNU_SOURCE
#include <dlfcn.h>
#include <errno.h>
#include <fcntl.h>
#include <pthread.h>
#include <stdint.h>
#include <stdlib.h>
#include <sys/stat.h>
#include <unistd.h>

#define MAX_HANDLES 4096

static pthread_mutex_t lock = PTHREAD_MUTEX_INITIALIZER;
static int handle_fds[MAX_HANDLES];
static dev_t kgsl_dev;
static int kgsl_state; /* 0 unknown, 1 known, -1 absent */

static int is_kgsl(int fd) {
  struct stat st;
  pthread_mutex_lock(&lock);
  if (kgsl_state == 0) {
    kgsl_state = stat("/dev/kgsl-3d0", &st) == 0 ? 1 : -1;
    if (kgsl_state > 0) kgsl_dev = st.st_rdev;
  }
  pthread_mutex_unlock(&lock);
  return kgsl_state > 0 && fstat(fd, &st) == 0 && S_ISCHR(st.st_mode) && st.st_rdev == kgsl_dev;
}

static void *real(const char *name) {
  void *fn = dlsym(RTLD_NEXT, name);
  if (!fn) {
    errno = ENOSYS;
  }
  return fn;
}

int drmPrimeFDToHandle(int fd, int prime_fd, uint32_t *handle) {
  if (!is_kgsl(fd)) {
    int (*fn)(int, int, uint32_t *) = (int (*)(int, int, uint32_t *)) real("drmPrimeFDToHandle");
    return fn ? fn(fd, prime_fd, handle) : -ENOSYS;
  }
  int dup_fd = fcntl(prime_fd, F_DUPFD_CLOEXEC, 3);
  if (dup_fd < 0) {
    return -errno;
  }
  int ret = -ENOMEM;
  pthread_mutex_lock(&lock);
  for (uint32_t i = 1; i < MAX_HANDLES; i++) {
    if (handle_fds[i] == 0) {
      handle_fds[i] = dup_fd;
      *handle = i;
      ret = 0;
      break;
    }
  }
  pthread_mutex_unlock(&lock);
  if (ret) {
    close(dup_fd);
  }
  return ret;
}

int drmPrimeHandleToFD(int fd, uint32_t handle, uint32_t flags, int *prime_fd) {
  if (!is_kgsl(fd)) {
    int (*fn)(int, uint32_t, uint32_t, int *) = (int (*)(int, uint32_t, uint32_t, int *)) real("drmPrimeHandleToFD");
    return fn ? fn(fd, handle, flags, prime_fd) : -ENOSYS;
  }
  int ret = -EINVAL;
  pthread_mutex_lock(&lock);
  if (handle > 0 && handle < MAX_HANDLES && handle_fds[handle] > 0) {
    *prime_fd = fcntl(handle_fds[handle], F_DUPFD_CLOEXEC, 3);
    ret = *prime_fd < 0 ? -errno : 0;
  }
  pthread_mutex_unlock(&lock);
  return ret;
}

int drmCloseBufferHandle(int fd, uint32_t handle) {
  if (!is_kgsl(fd)) {
    int (*fn)(int, uint32_t) = (int (*)(int, uint32_t)) real("drmCloseBufferHandle");
    return fn ? fn(fd, handle) : -ENOSYS;
  }
  int ret = -EINVAL;
  pthread_mutex_lock(&lock);
  if (handle > 0 && handle < MAX_HANDLES && handle_fds[handle] > 0) {
    close(handle_fds[handle]);
    handle_fds[handle] = 0;
    ret = 0;
  }
  pthread_mutex_unlock(&lock);
  return ret;
}

/*
 * fork() carries over only the calling thread, so a lock another thread was holding at that
 * instant stays held in the child by a thread that is not there to release it. The calling thread
 * takes this normal mutex before fork; both parent and child unlock their own copy afterward.
 */
static void drm_lock_before_fork(void) { pthread_mutex_lock(&lock); }
static void drm_unlock_after_fork(void) { pthread_mutex_unlock(&lock); }

__attribute__((constructor)) static void install_drm_fork_handlers(void) {
  pthread_atfork(drm_lock_before_fork, drm_unlock_after_fork, drm_unlock_after_fork);
}
