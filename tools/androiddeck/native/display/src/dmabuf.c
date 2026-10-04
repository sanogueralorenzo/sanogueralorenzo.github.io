#include "display.h"
#include "linux-dmabuf-server.h"
#include <errno.h>
#include <fcntl.h>
#include <stdlib.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <unistd.h>

#define ARGB8888 0x34325241u
#define XRGB8888 0x34325258u
struct format_entry { uint32_t format, padding; uint64_t modifier; };
struct params {
    struct deck_display *display;
    int fd;
    uint32_t stride, offset;
    uint64_t modifier;
    bool used;
};
struct buffer { struct deck_gpu_image *image; struct deck_display *display; int fd; };
static void destroy_request(struct wl_client *c, struct wl_resource *r) { wl_resource_destroy(r); }
static const struct wl_buffer_interface buffer_impl = { .destroy = destroy_request };
static void buffer_destroyed(struct wl_resource *r) {
    struct buffer *buffer = wl_resource_get_user_data(r);
    pthread_mutex_lock(&buffer->display->window_mutex);
    buffer->image->gpu->vk.DeviceWaitIdle(buffer->image->gpu->device);
    deck_gpu_image_destroy(buffer->image);
    pthread_mutex_unlock(&buffer->display->window_mutex);
    close(buffer->fd); free(buffer);
}
struct deck_gpu_image *deck_dmabuf_image(struct wl_resource *r) {
    if (!wl_resource_instance_of(r, &wl_buffer_interface, &buffer_impl)) return NULL;
    return ((struct buffer *)wl_resource_get_user_data(r))->image;
}
static bool unused(struct wl_resource *r) {
    struct params *params = wl_resource_get_user_data(r);
    if (!params->used) return true;
    wl_resource_post_error(r, ZWP_LINUX_BUFFER_PARAMS_V1_ERROR_ALREADY_USED, "Buffer parameters were already consumed");
    return false;
}
static void params_destroyed(struct wl_resource *r) {
    struct params *params = wl_resource_get_user_data(r);
    if (params->fd >= 0) close(params->fd);
    free(params);
}
static void add(struct wl_client *c, struct wl_resource *r, int32_t fd, uint32_t plane,
        uint32_t offset, uint32_t stride, uint32_t high, uint32_t low) {
    struct params *params = wl_resource_get_user_data(r);
    if (!unused(r)) { close(fd); return; }
    if (plane != 0) { close(fd); wl_resource_post_error(r, ZWP_LINUX_BUFFER_PARAMS_V1_ERROR_PLANE_IDX, "Only single-plane frames are supported"); return; }
    if (params->fd >= 0) { close(fd); wl_resource_post_error(r, ZWP_LINUX_BUFFER_PARAMS_V1_ERROR_PLANE_SET, "Frame plane was already set"); return; }
    params->fd = fd; params->offset = offset; params->stride = stride;
    params->modifier = ((uint64_t)high << 32) | low;
}
static void create_buffer(struct wl_client *c, struct wl_resource *r, uint32_t id,
        int32_t width, int32_t height, uint32_t format, uint32_t flags, bool immediate) {
    struct params *params = wl_resource_get_user_data(r);
    if (!unused(r)) return;
    params->used = true;
    if (params->fd < 0) { wl_resource_post_error(r, ZWP_LINUX_BUFFER_PARAMS_V1_ERROR_INCOMPLETE, "Frame plane is missing"); return; }
    if (width <= 0 || width > 8192 || height <= 0 || height > 8192) {
        wl_resource_post_error(r, ZWP_LINUX_BUFFER_PARAMS_V1_ERROR_INVALID_DIMENSIONS, "Frame dimensions must be between 1 and 8192"); return;
    }
    if (format != ARGB8888 && format != XRGB8888) {
        wl_resource_post_error(r, ZWP_LINUX_BUFFER_PARAMS_V1_ERROR_INVALID_FORMAT, "Only 8-bit BGRA frames are supported"); return;
    }
    uint64_t end = (uint64_t)params->offset + (uint64_t)params->stride * (height - 1) + (uint64_t)width * 4;
    struct stat info;
    if (params->stride < (uint32_t)width * 4 || end > UINT32_MAX ||
        (fstat(params->fd, &info) == 0 && info.st_size > 0 && end > (uint64_t)info.st_size)) {
        wl_resource_post_error(r, ZWP_LINUX_BUFFER_PARAMS_V1_ERROR_OUT_OF_BOUNDS, "Frame stride or offset exceeds its storage"); return;
    }
    bool modifier = false;
    for (size_t i = 0; i < params->display->modifier_count; i++) if (params->modifier == params->display->modifiers[i]) modifier = true;
    struct deck_gpu_image *image = NULL;
    if (!flags && modifier) {
        pthread_mutex_lock(&params->display->window_mutex);
        image = deck_gpu_import(params->display->gpu, params->fd, params->modifier, width, height, params->stride, params->offset);
        pthread_mutex_unlock(&params->display->window_mutex);
    }
    if (!image) {
        if (immediate) wl_resource_post_error(r, ZWP_LINUX_BUFFER_PARAMS_V1_ERROR_INVALID_WL_BUFFER, "The Adreno driver cannot import this frame");
        else zwp_linux_buffer_params_v1_send_failed(r);
        return;
    }
    struct buffer *buffer = calloc(1, sizeof(*buffer));
    struct wl_resource *resource = buffer ? wl_resource_create(c, &wl_buffer_interface, 1, id) : NULL;
    if (!resource) { free(buffer); deck_gpu_image_destroy(image); wl_client_post_no_memory(c); return; }
    buffer->image = image; buffer->display = params->display; buffer->fd = params->fd; params->fd = -1;
    wl_resource_set_implementation(resource, &buffer_impl, buffer, buffer_destroyed);
    if (!immediate) zwp_linux_buffer_params_v1_send_created(r, resource);
}
static void create(struct wl_client *c, struct wl_resource *r, int32_t w, int32_t h, uint32_t format, uint32_t flags) {
    create_buffer(c, r, 0, w, h, format, flags, false);
}
static void create_immed(struct wl_client *c, struct wl_resource *r, uint32_t id, int32_t w, int32_t h, uint32_t format, uint32_t flags) {
    create_buffer(c, r, id, w, h, format, flags, true);
}
static const struct zwp_linux_buffer_params_v1_interface params_impl = {
    .destroy = destroy_request, .add = add, .create = create, .create_immed = create_immed
};
static void create_params(struct wl_client *c, struct wl_resource *r, uint32_t id) {
    struct params *params = calloc(1, sizeof(*params));
    if (!params) { wl_client_post_no_memory(c); return; }
    params->fd = -1; params->display = wl_resource_get_user_data(r);
    struct wl_resource *resource = wl_resource_create(c, &zwp_linux_buffer_params_v1_interface, wl_resource_get_version(r), id);
    if (!resource) { free(params); wl_client_post_no_memory(c); return; }
    wl_resource_set_implementation(resource, &params_impl, params, params_destroyed);
}
static const struct zwp_linux_dmabuf_feedback_v1_interface feedback_impl = { .destroy = destroy_request };
static void feedback(struct wl_client *c, struct wl_resource *r, uint32_t id) {
    struct deck_display *display = wl_resource_get_user_data(r);
    struct wl_resource *resource = wl_resource_create(c, &zwp_linux_dmabuf_feedback_v1_interface, wl_resource_get_version(r), id);
    if (!resource) { wl_client_post_no_memory(c); return; }
    wl_resource_set_implementation(resource, &feedback_impl, NULL, NULL);
    uint16_t indices[128];
    size_t count = display->modifier_count * 2;
    for (size_t i = 0; i < count; i++) indices[i] = (uint16_t)i;
    struct wl_array device = { .size = sizeof(display->main_device), .data = &display->main_device };
    struct wl_array formats = { .size = count * sizeof(*indices), .data = indices };
    zwp_linux_dmabuf_feedback_v1_send_format_table(resource, display->format_fd, (uint32_t)(count * sizeof(struct format_entry)));
    zwp_linux_dmabuf_feedback_v1_send_main_device(resource, &device);
    zwp_linux_dmabuf_feedback_v1_send_tranche_target_device(resource, &device);
    zwp_linux_dmabuf_feedback_v1_send_tranche_flags(resource, 0);
    zwp_linux_dmabuf_feedback_v1_send_tranche_formats(resource, &formats);
    zwp_linux_dmabuf_feedback_v1_send_tranche_done(resource);
    zwp_linux_dmabuf_feedback_v1_send_done(resource);
}
static void surface_feedback(struct wl_client *c, struct wl_resource *r, uint32_t id, struct wl_resource *surface) { feedback(c, r, id); }
static const struct zwp_linux_dmabuf_v1_interface dmabuf_impl = {
    .destroy = destroy_request, .create_params = create_params, .get_default_feedback = feedback, .get_surface_feedback = surface_feedback
};
static void bind_dmabuf(struct wl_client *c, void *data, uint32_t version, uint32_t id) {
    struct deck_display *display = data;
    struct wl_resource *resource = wl_resource_create(c, &zwp_linux_dmabuf_v1_interface, version, id);
    if (!resource) { wl_client_post_no_memory(c); return; }
    wl_resource_set_implementation(resource, &dmabuf_impl, display, NULL);
    if (version >= 4) return;
    // Mesa's Vulkan WSI can negotiate v3; v4 clients receive the immutable table.
    const uint32_t formats[] = { ARGB8888, XRGB8888 };
    for (size_t f = 0; f < 2; f++) {
        zwp_linux_dmabuf_v1_send_format(resource, formats[f]);
        if (version >= 3) for (size_t i = 0; i < display->modifier_count; i++) {
            uint64_t modifier = display->modifiers[i];
            zwp_linux_dmabuf_v1_send_modifier(resource, formats[f], modifier >> 32, (uint32_t)modifier);
        }
    }
}
bool deck_register_dmabuf(struct deck_display *display) {
    display->modifier_count = deck_gpu_modifiers(display->gpu, display->modifiers, 64);
    if (!display->modifier_count) { deck_gpu_error(display->gpu, "Adreno frame sharing formats", VK_ERROR_FORMAT_NOT_SUPPORTED); return false; }
    struct format_entry entries[128];
    size_t count = 0;
    const uint32_t formats[] = { ARGB8888, XRGB8888 };
    for (size_t f = 0; f < 2; f++) for (size_t i = 0; i < display->modifier_count; i++)
        entries[count++] = (struct format_entry){ .format = formats[f], .modifier = display->modifiers[i] };
    display->format_fd = memfd_create("androiddeck-formats", MFD_CLOEXEC | MFD_ALLOW_SEALING);
    if (display->format_fd < 0) return false;
    const size_t size = count * sizeof(*entries);
    size_t written = 0;
    while (written < size) {
        ssize_t bytes = write(display->format_fd, (char *)entries + written, size - written);
        if (bytes < 0 && errno == EINTR) continue;
        if (bytes <= 0) return false;
        written += bytes;
    }
    if (fcntl(display->format_fd, F_ADD_SEALS, F_SEAL_SEAL | F_SEAL_SHRINK | F_SEAL_GROW | F_SEAL_WRITE) < 0) return false;
    // KGSL may expose no DRM node. As in the reference compositor, advertise
    // an existing node or zero, rather than inventing a render device.
    const char *nodes[] = { "/dev/dri/renderD128", "/dev/dri/renderD129", "/dev/dri/card0" };
    struct stat info;
    for (size_t i = 0; i < 3; i++) if (stat(nodes[i], &info) == 0 && S_ISCHR(info.st_mode)) { display->main_device = info.st_rdev; break; }
    return wl_global_create(display->wayland, &zwp_linux_dmabuf_v1_interface, 4, display, bind_dmabuf) != NULL;
}
