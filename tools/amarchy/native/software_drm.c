/* SPDX-License-Identifier: GPL-3.0-only */
#define _GNU_SOURCE
#include <dlfcn.h>
#include <errno.h>
#include <fcntl.h>
#include <pthread.h>
#include <stdarg.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <stddef.h>
#include <sys/sysmacros.h>
#include <unistd.h>
#include <xf86drm.h>
#include <drm_mode.h>

/* Memory-backed DRM allocation for Mesa's existing kms_swrast renderer.
 * This implements buffer allocation/sharing, not a GPU or rendering engine. */
struct buffer { uint32_t handle; int fd; uint64_t size; struct buffer *next; };
static int device_fd = -1;
static dev_t device_dev;
static ino_t device_ino;
static struct buffer *buffers;
static uint32_t next_handle = 1;
static pthread_mutex_t mutex = PTHREAD_MUTEX_INITIALIZER;
static const char *render_node = "/dev/dri/renderD128";
static dev_t device_id(void) { return makedev(226, 128); }

/* PRoot expands Hyprland's instance path past sockaddr_un's 108-byte limit.
 * Keep that private IPC in the abstract namespace, keyed by its full guest path. */
static int instance_address(const struct sockaddr *address, socklen_t size, struct sockaddr_un *result, socklen_t *length) {
    if (!address || address->sa_family != AF_UNIX || size <= offsetof(struct sockaddr_un, sun_path)) return 0;
    const struct sockaddr_un *original = (const struct sockaddr_un *)address;
    size_t available = size - offsetof(struct sockaddr_un, sun_path);
    if (available > sizeof(original->sun_path)) available = sizeof(original->sun_path);
    if (available < 20 || strncmp(original->sun_path, "/run/user/1000/hypr/", 20)) return 0;
    uint64_t hash = 14695981039346656037ULL;
    for (size_t i = 0; i < available && original->sun_path[i]; i++) { hash ^= (unsigned char)original->sun_path[i]; hash *= 1099511628211ULL; }
    memset(result, 0, sizeof(*result)); result->sun_family = AF_UNIX;
    int bytes = snprintf(result->sun_path + 1, sizeof(result->sun_path) - 1, "amarchy-%016lx", (unsigned long)hash);
    *length = offsetof(struct sockaddr_un, sun_path) + 1 + bytes;
    return 1;
}
int bind(int fd, const struct sockaddr *address, socklen_t size) {
    int (*function)(int, const struct sockaddr *, socklen_t) = dlsym(RTLD_NEXT, "bind");
    struct sockaddr_un translated;
    if (instance_address(address, size, &translated, &size)) address = (const struct sockaddr *)&translated;
    return function(fd, address, size);
}
int connect(int fd, const struct sockaddr *address, socklen_t size) {
    int (*function)(int, const struct sockaddr *, socklen_t) = dlsym(RTLD_NEXT, "connect");
    struct sockaddr_un translated;
    if (instance_address(address, size, &translated, &size)) address = (const struct sockaddr *)&translated;
    return function(fd, address, size);
}

static int actual_stat(int fd, struct stat *info) {
    int (*function)(int, struct stat *) = dlsym(RTLD_NEXT, "fstat");
    return function(fd, info);
}
static int software_fd(int fd) {
    struct stat info;
    if (actual_stat(fd, &info)) return 0;
    int found = 0;
    pthread_mutex_lock(&mutex);
    found = device_fd >= 0 && device_dev == info.st_dev && device_ino == info.st_ino;
    pthread_mutex_unlock(&mutex);
    return found;
}
static int open_node(void) {
    pthread_mutex_lock(&mutex);
    if (device_fd < 0) {
        device_fd = memfd_create("amarchy-software-drm", MFD_CLOEXEC);
        struct stat info;
        if (device_fd >= 0 && actual_stat(device_fd, &info) == 0) { device_dev = info.st_dev; device_ino = info.st_ino; }
        else { if (device_fd >= 0) close(device_fd); device_fd = -1; }
    }
    int fd = device_fd >= 0 ? fcntl(device_fd, F_DUPFD_CLOEXEC, 3) : -1;
    pthread_mutex_unlock(&mutex);
    return fd;
}
int open(const char *path, int flags, ...) {
    if (!strcmp(path, render_node)) return open_node();
    // Android's app sandbox cannot publish unnamed Qt temporary files. Let Qt
    // use its named atomic-file path instead of linkat(AT_EMPTY_PATH).
    if ((flags & O_TMPFILE) == O_TMPFILE) { errno = EOPNOTSUPP; return -1; }
    mode_t mode = 0;
    if (flags & O_CREAT) { va_list arguments; va_start(arguments, flags); mode = va_arg(arguments, int); va_end(arguments); }
    int (*function)(const char *, int, ...) = dlsym(RTLD_NEXT, "open");
    return function(path, flags, mode);
}
int open64(const char *path, int flags, ...) {
    if (!strcmp(path, render_node)) return open_node();
    if ((flags & O_TMPFILE) == O_TMPFILE) { errno = EOPNOTSUPP; return -1; }
    mode_t mode = 0;
    if (flags & O_CREAT) { va_list arguments; va_start(arguments, flags); mode = va_arg(arguments, int); va_end(arguments); }
    int (*function)(const char *, int, ...) = dlsym(RTLD_NEXT, "open64");
    return function(path, flags, mode);
}
int fstat(int fd, struct stat *info) {
    int result = actual_stat(fd, info);
    if (!result && software_fd(fd)) { info->st_mode = S_IFCHR | 0600; info->st_rdev = device_id(); }
    return result;
}
int fstat64(int fd, struct stat64 *info) __attribute__((alias("fstat")));

static struct buffer *find_buffer(uint32_t handle) {
    for (struct buffer *buffer = buffers; buffer; buffer = buffer->next)
        if (buffer->handle == handle) return buffer;
    return NULL;
}
static int add_buffer(int fd, uint64_t size, uint32_t *handle) {
    struct buffer *buffer = calloc(1, sizeof(*buffer));
    if (!buffer) { errno = ENOMEM; return -1; }
    if (next_handle >= INT32_MAX) { free(buffer); errno = ENOSPC; return -1; }
    buffer->handle = next_handle++; buffer->fd = fd; buffer->size = size;
    buffer->next = buffers; buffers = buffer; *handle = buffer->handle;
    return 0;
}
static int release_buffer(uint32_t handle) {
    for (struct buffer **pointer = &buffers; *pointer; pointer = &(*pointer)->next) {
        if ((*pointer)->handle != handle) continue;
        struct buffer *buffer = *pointer; *pointer = buffer->next;
        close(buffer->fd); free(buffer); return 0;
    }
    errno = ENOENT; return -1;
}
int drmIoctl(int fd, unsigned long request, void *argument) {
    if (!software_fd(fd)) {
        int (*function)(int, unsigned long, void *) = dlsym(RTLD_NEXT, "drmIoctl");
        return function(fd, request, argument);
    }
    int result = 0;
    pthread_mutex_lock(&mutex);
    switch (request) {
    case DRM_IOCTL_GET_CAP: {
        struct drm_get_cap *cap = argument;
        cap->value = cap->capability == DRM_CAP_DUMB_BUFFER ? 1 :
            cap->capability == DRM_CAP_PRIME ? DRM_PRIME_CAP_IMPORT | DRM_PRIME_CAP_EXPORT :
            cap->capability == DRM_CAP_TIMESTAMP_MONOTONIC ? 1 : 0;
        break;
    }
    case DRM_IOCTL_MODE_CREATE_DUMB: {
        struct drm_mode_create_dumb *create = argument;
        uint64_t pitch = (((uint64_t)create->width * create->bpp + 7) / 8 + 63) & ~63ULL;
        uint64_t size = pitch * create->height;
        if (!size || size > 256 * 1024 * 1024 || pitch > UINT32_MAX) { errno = EINVAL; result = -1; break; }
        int memory = memfd_create("amarchy-frame", MFD_CLOEXEC);
        if (memory < 0) { result = -1; break; }
        if (ftruncate(memory, size) || add_buffer(memory, size, &create->handle)) { close(memory); result = -1; break; }
        create->pitch = pitch; create->size = size;
        break;
    }
    case DRM_IOCTL_MODE_MAP_DUMB: {
        struct drm_mode_map_dumb *map = argument;
        if (!find_buffer(map->handle)) { errno = ENOENT; result = -1; break; }
        map->offset = (uint64_t)map->handle << 32;
        break;
    }
    case DRM_IOCTL_MODE_DESTROY_DUMB:
        result = release_buffer(((struct drm_mode_destroy_dumb *)argument)->handle); break;
    case DRM_IOCTL_GEM_CLOSE:
        result = release_buffer(((struct drm_gem_close *)argument)->handle); break;
    case DRM_IOCTL_PRIME_HANDLE_TO_FD: {
        struct drm_prime_handle *prime = argument;
        struct buffer *buffer = find_buffer(prime->handle);
        if (!buffer) { errno = ENOENT; result = -1; break; }
        prime->fd = fcntl(buffer->fd, F_DUPFD_CLOEXEC, 3);
        if (prime->fd < 0) result = -1;
        break;
    }
    case DRM_IOCTL_PRIME_FD_TO_HANDLE: {
        struct drm_prime_handle *prime = argument;
        struct stat info;
        int imported = fcntl(prime->fd, F_DUPFD_CLOEXEC, 3);
        if (imported < 0) { result = -1; break; }
        if (actual_stat(imported, &info) || info.st_size <= 0 || add_buffer(imported, info.st_size, &prime->handle)) {
            close(imported); result = -1;
        }
        break;
    }
    case DRM_IOCTL_SET_CLIENT_CAP: break;
    default:
        if (getenv("AMARCHY_DRM_TRACE")) fprintf(stderr, "amarchy-drm: unsupported ioctl 0x%lx\n", request);
        errno = ENOTTY; result = -1;
    }
    pthread_mutex_unlock(&mutex);
    return result;
}
void *mmap(void *address, size_t size, int protection, int flags, int fd, off_t offset) {
    void *(*function)(void *, size_t, int, int, int, off_t) = dlsym(RTLD_NEXT, "mmap");
    if (!software_fd(fd)) return function(address, size, protection, flags, fd, offset);
    pthread_mutex_lock(&mutex);
    struct buffer *buffer = find_buffer((uint64_t)offset >> 32);
    int memory = buffer && size <= buffer->size ? fcntl(buffer->fd, F_DUPFD_CLOEXEC, 3) : -1;
    pthread_mutex_unlock(&mutex);
    if (memory < 0) { errno = EINVAL; return MAP_FAILED; }
    void *mapping = function(address, size, protection, flags, memory, 0);
    close(memory); return mapping;
}
void *mmap64(void *address, size_t size, int protection, int flags, int fd, off64_t offset) __attribute__((alias("mmap")));

static int describe(drmDevicePtr *output) {
    drmDevicePtr device = calloc(1, sizeof(*device));
    if (!device) return -ENOMEM;
    device->nodes = calloc(DRM_NODE_MAX, sizeof(char *));
    device->businfo.platform = calloc(1, sizeof(drmPlatformBusInfo));
    device->deviceinfo.platform = calloc(1, sizeof(drmPlatformDeviceInfo));
    if (!device->nodes || !device->businfo.platform || !device->deviceinfo.platform) {
        free(device->nodes); free(device->businfo.platform); free(device->deviceinfo.platform); free(device); return -ENOMEM;
    }
    device->nodes[DRM_NODE_RENDER] = strdup(render_node);
    device->available_nodes = 1 << DRM_NODE_RENDER; device->bustype = DRM_BUS_PLATFORM;
    strcpy(device->businfo.platform->fullname, "amarchy-software");
    *output = device; return 0;
}
int drmGetDevice2(int fd, uint32_t flags, drmDevicePtr *device) {
    if (software_fd(fd)) return describe(device);
    int (*function)(int, uint32_t, drmDevicePtr *) = dlsym(RTLD_NEXT, "drmGetDevice2");
    return function(fd, flags, device);
}
int drmGetDevice(int fd, drmDevicePtr *device) { return drmGetDevice2(fd, 0, device); }
int drmGetDeviceFromDevId(dev_t id, uint32_t flags, drmDevicePtr *device) {
    if (id == device_id()) return describe(device);
    int (*function)(dev_t, uint32_t, drmDevicePtr *) = dlsym(RTLD_NEXT, "drmGetDeviceFromDevId");
    return function(id, flags, device);
}
int drmGetDevices2(uint32_t flags, drmDevicePtr devices[], int count) {
    if (!devices) return 1;
    if (count <= 0) return 0;
    return describe(&devices[0]) ? -ENOMEM : 1;
}
int drmGetDevices(drmDevicePtr devices[], int count) { return drmGetDevices2(0, devices, count); }
void drmFreeDevice(drmDevicePtr *pointer) {
    drmDevicePtr device = *pointer;
    if (!device) return;
    if (device->bustype != DRM_BUS_PLATFORM || strcmp(device->businfo.platform->fullname, "amarchy-software")) {
        void (*function)(drmDevicePtr *) = dlsym(RTLD_NEXT, "drmFreeDevice"); function(pointer); return;
    }
    free(device->nodes[DRM_NODE_RENDER]); free(device->nodes);
    free(device->businfo.platform); free(device->deviceinfo.platform); free(device); *pointer = NULL;
}
void drmFreeDevices(drmDevicePtr devices[], int count) { for (int i = 0; i < count; i++) drmFreeDevice(&devices[i]); }
int drmGetNodeTypeFromFd(int fd) {
    if (software_fd(fd)) return DRM_NODE_RENDER;
    int (*function)(int) = dlsym(RTLD_NEXT, "drmGetNodeTypeFromFd"); return function(fd);
}
int drmIsMaster(int fd) { if (software_fd(fd)) return 0; int (*function)(int) = dlsym(RTLD_NEXT, "drmIsMaster"); return function(fd); }
char *drmGetRenderDeviceNameFromFd(int fd) { if (software_fd(fd)) return strdup(render_node); char *(*function)(int) = dlsym(RTLD_NEXT, "drmGetRenderDeviceNameFromFd"); return function(fd); }
char *drmGetDeviceNameFromFd2(int fd) { if (software_fd(fd)) return strdup(render_node); char *(*function)(int) = dlsym(RTLD_NEXT, "drmGetDeviceNameFromFd2"); return function(fd); }
char *drmGetPrimaryDeviceNameFromFd(int fd) { if (software_fd(fd)) return strdup(render_node); char *(*function)(int) = dlsym(RTLD_NEXT, "drmGetPrimaryDeviceNameFromFd"); return function(fd); }
drmVersionPtr drmGetVersion(int fd) {
    if (!software_fd(fd)) { drmVersionPtr (*function)(int) = dlsym(RTLD_NEXT, "drmGetVersion"); return function(fd); }
    drmVersionPtr version = calloc(1, sizeof(*version));
    if (!version) return NULL;
    version->version_major = 1; version->name = strdup("amarchy"); version->name_len = 7;
    version->date = strdup(""); version->desc = strdup("Memory-backed software display"); version->desc_len = strlen(version->desc);
    return version;
}
