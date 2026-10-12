#include "display.h"
#include "linux-dmabuf-server.h"
#include <errno.h>
#include <fcntl.h>
#include <stdlib.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <sys/sysmacros.h>
#include <unistd.h>

#define ARGB8888 0x34325241u
#define XRGB8888 0x34325258u
#define INVALID_MODIFIER 0x00ffffffffffffffULL
struct format_entry { uint32_t format, padding; uint64_t modifier; };
struct params { int fd; uint32_t stride, offset; uint64_t modifier; bool used; };
struct buffer { int fd, width, height, stride; uint32_t offset, format; void *memory; size_t size; };
static void destroy_request(struct wl_client *client, struct wl_resource *resource) { wl_resource_destroy(resource); }
static const struct wl_buffer_interface buffer_impl = { .destroy = destroy_request };
static void buffer_destroyed(struct wl_resource *resource) {
    struct buffer *buffer = wl_resource_get_user_data(resource);
    munmap(buffer->memory, buffer->size); close(buffer->fd); free(buffer);
}
bool amarchy_present_buffer(struct amarchy_display *display, struct wl_resource *resource) {
    if (wl_resource_instance_of(resource, &wl_buffer_interface, &buffer_impl)) {
        struct buffer *buffer = wl_resource_get_user_data(resource);
        return amarchy_present(display, (uint8_t *)buffer->memory + buffer->offset,
            buffer->width, buffer->height, buffer->stride, buffer->format == XRGB8888);
    }
    struct wl_shm_buffer *buffer = wl_shm_buffer_get(resource);
    if (!buffer) return false;
    uint32_t format = wl_shm_buffer_get_format(buffer);
    if (format != WL_SHM_FORMAT_ARGB8888 && format != WL_SHM_FORMAT_XRGB8888) return false;
    wl_shm_buffer_begin_access(buffer);
    bool result = amarchy_present(display, wl_shm_buffer_get_data(buffer), wl_shm_buffer_get_width(buffer),
        wl_shm_buffer_get_height(buffer), wl_shm_buffer_get_stride(buffer), format == WL_SHM_FORMAT_XRGB8888);
    wl_shm_buffer_end_access(buffer);
    return result;
}
static bool unused(struct wl_resource *resource) {
    struct params *params = wl_resource_get_user_data(resource);
    if (!params->used) return true;
    wl_resource_post_error(resource, ZWP_LINUX_BUFFER_PARAMS_V1_ERROR_ALREADY_USED, "The frame parameters were already used"); return false;
}
static void params_destroyed(struct wl_resource *resource) {
    struct params *params = wl_resource_get_user_data(resource);
    if (params->fd >= 0) close(params->fd);
    free(params);
}
static void add(struct wl_client *client, struct wl_resource *resource, int32_t fd, uint32_t plane, uint32_t offset,
        uint32_t stride, uint32_t high, uint32_t low) {
    struct params *params = wl_resource_get_user_data(resource);
    if (!unused(resource)) { close(fd); return; }
    if (plane != 0) { close(fd); wl_resource_post_error(resource, ZWP_LINUX_BUFFER_PARAMS_V1_ERROR_PLANE_IDX, "The desktop output uses a single-plane frame"); return; }
    if (params->fd >= 0) { close(fd); wl_resource_post_error(resource, ZWP_LINUX_BUFFER_PARAMS_V1_ERROR_PLANE_SET, "The frame plane was already set"); return; }
    params->fd = fd; params->offset = offset; params->stride = stride;
    params->modifier = ((uint64_t)high << 32) | low;
}
static void create_buffer(struct wl_client *client, struct wl_resource *resource, uint32_t id,
        int32_t width, int32_t height, uint32_t format, uint32_t flags, bool immediate) {
    struct params *params = wl_resource_get_user_data(resource);
    if (!unused(resource)) return;
    params->used = true;
    if (params->fd < 0) { wl_resource_post_error(resource, ZWP_LINUX_BUFFER_PARAMS_V1_ERROR_INCOMPLETE, "The frame plane is missing"); return; }
    if (width <= 0 || width > 8192 || height <= 0 || height > 8192) {
        wl_resource_post_error(resource, ZWP_LINUX_BUFFER_PARAMS_V1_ERROR_INVALID_DIMENSIONS, "Invalid desktop frame dimensions"); return;
    }
    if (format != ARGB8888 && format != XRGB8888) {
        wl_resource_post_error(resource, ZWP_LINUX_BUFFER_PARAMS_V1_ERROR_INVALID_FORMAT, "The desktop output uses BGRA frames"); return;
    }
    struct stat info;
    uint64_t size = (uint64_t)params->offset + (uint64_t)params->stride * (height - 1) + (uint64_t)width * 4;
    if (params->stride < (uint32_t)width * 4 || size > 256 * 1024 * 1024 || fstat(params->fd, &info) ||
        info.st_size <= 0 || size > (uint64_t)info.st_size) {
        wl_resource_post_error(resource, ZWP_LINUX_BUFFER_PARAMS_V1_ERROR_OUT_OF_BOUNDS, "The frame exceeds its memory buffer"); return;
    }
    void *memory = !flags && (params->modifier == INVALID_MODIFIER || params->modifier == 0) ?
        mmap(NULL, size, PROT_READ, MAP_SHARED, params->fd, 0) : MAP_FAILED;
    if (memory == MAP_FAILED) {
        if (immediate) wl_resource_post_error(resource, ZWP_LINUX_BUFFER_PARAMS_V1_ERROR_INVALID_WL_BUFFER, "Cannot map the desktop frame");
        else zwp_linux_buffer_params_v1_send_failed(resource);
        return;
    }
    struct buffer *buffer = calloc(1, sizeof(*buffer));
    struct wl_resource *frame = buffer ? wl_resource_create(client, &wl_buffer_interface, 1, id) : NULL;
    if (!frame) { free(buffer); munmap(memory, size); wl_client_post_no_memory(client); return; }
    *buffer = (struct buffer){ .fd = params->fd, .width = width, .height = height, .stride = params->stride,
        .offset = params->offset, .format = format, .memory = memory, .size = size };
    params->fd = -1;
    wl_resource_set_implementation(frame, &buffer_impl, buffer, buffer_destroyed);
    if (!immediate) zwp_linux_buffer_params_v1_send_created(resource, frame);
}
static void create(struct wl_client *client, struct wl_resource *resource, int32_t width, int32_t height, uint32_t format, uint32_t flags) {
    create_buffer(client, resource, 0, width, height, format, flags, false);
}
static void create_immed(struct wl_client *client, struct wl_resource *resource, uint32_t id, int32_t width, int32_t height, uint32_t format, uint32_t flags) {
    create_buffer(client, resource, id, width, height, format, flags, true);
}
static const struct zwp_linux_buffer_params_v1_interface params_impl = {
    .destroy = destroy_request, .add = add, .create = create, .create_immed = create_immed
};
static void create_params(struct wl_client *client, struct wl_resource *resource, uint32_t id) {
    struct params *params = calloc(1, sizeof(*params));
    if (!params) { wl_client_post_no_memory(client); return; }
    params->fd = -1;
    struct wl_resource *child = wl_resource_create(client, &zwp_linux_buffer_params_v1_interface, wl_resource_get_version(resource), id);
    if (!child) { free(params); wl_client_post_no_memory(client); return; }
    wl_resource_set_implementation(child, &params_impl, params, params_destroyed);
}
static const struct zwp_linux_dmabuf_feedback_v1_interface feedback_impl = { .destroy = destroy_request };
static void feedback(struct wl_client *client, struct wl_resource *resource, uint32_t id) {
    struct amarchy_display *display = wl_resource_get_user_data(resource);
    struct wl_resource *child = wl_resource_create(client, &zwp_linux_dmabuf_feedback_v1_interface, wl_resource_get_version(resource), id);
    if (!child) { wl_client_post_no_memory(client); return; }
    wl_resource_set_implementation(child, &feedback_impl, NULL, NULL);
    dev_t device_id = makedev(226, 128);
    uint16_t indices[] = { 0, 1 };
    struct wl_array device = { .size = sizeof(device_id), .data = &device_id };
    struct wl_array formats = { .size = sizeof(indices), .data = indices };
    zwp_linux_dmabuf_feedback_v1_send_format_table(child, display->format_fd, 2 * sizeof(struct format_entry));
    zwp_linux_dmabuf_feedback_v1_send_main_device(child, &device);
    zwp_linux_dmabuf_feedback_v1_send_tranche_target_device(child, &device);
    zwp_linux_dmabuf_feedback_v1_send_tranche_flags(child, 0);
    zwp_linux_dmabuf_feedback_v1_send_tranche_formats(child, &formats);
    zwp_linux_dmabuf_feedback_v1_send_tranche_done(child); zwp_linux_dmabuf_feedback_v1_send_done(child);
}
static void surface_feedback(struct wl_client *client, struct wl_resource *resource, uint32_t id, struct wl_resource *surface) { feedback(client, resource, id); }
static const struct zwp_linux_dmabuf_v1_interface dmabuf_impl = {
    .destroy = destroy_request, .create_params = create_params, .get_default_feedback = feedback, .get_surface_feedback = surface_feedback
};
static void bind_dmabuf(struct wl_client *client, void *data, uint32_t version, uint32_t id) {
    struct wl_resource *resource = wl_resource_create(client, &zwp_linux_dmabuf_v1_interface, version, id);
    if (!resource) { wl_client_post_no_memory(client); return; }
    wl_resource_set_implementation(resource, &dmabuf_impl, data, NULL);
    if (version < 4) for (int i = 0; i < 2; i++) {
        uint32_t format = i ? XRGB8888 : ARGB8888;
        zwp_linux_dmabuf_v1_send_format(resource, format);
        if (version >= 3) zwp_linux_dmabuf_v1_send_modifier(resource, format, INVALID_MODIFIER >> 32, (uint32_t)INVALID_MODIFIER);
    }
}
bool amarchy_register_dmabuf(struct amarchy_display *display) {
    struct format_entry entries[] = {{ ARGB8888, 0, INVALID_MODIFIER }, { XRGB8888, 0, INVALID_MODIFIER }};
    display->format_fd = memfd_create("amarchy-formats", MFD_CLOEXEC | MFD_ALLOW_SEALING);
    if (display->format_fd < 0 || write(display->format_fd, entries, sizeof(entries)) != sizeof(entries)) return false;
    if (fcntl(display->format_fd, F_ADD_SEALS, F_SEAL_SEAL | F_SEAL_SHRINK | F_SEAL_GROW | F_SEAL_WRITE) < 0) return false;
    return wl_global_create(display->wayland, &zwp_linux_dmabuf_v1_interface, 4, display, bind_dmabuf) != NULL;
}
