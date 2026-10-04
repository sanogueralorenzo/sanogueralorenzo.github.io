#include "display.h"
#include "explicit-sync-server.h"
#include <linux/sync_file.h>
#include <sys/ioctl.h>
#include <unistd.h>

static void destroy_request(struct wl_client *c, struct wl_resource *r) { wl_resource_destroy(r); }
static void release_destroyed(struct wl_resource *r) {
    struct deck_surface *surface = wl_resource_get_user_data(r);
    if (surface) surface->release = NULL;
}
void deck_sync_release(struct deck_surface *surface) {
    if (surface->release) {
        zwp_linux_buffer_release_v1_send_immediate_release(surface->release);
        wl_resource_destroy(surface->release);
    }
}
static void sync_destroyed(struct wl_resource *r) {
    struct deck_surface *surface = wl_resource_get_user_data(r);
    if (!surface) return;
    surface->sync = NULL;
    if (surface->acquire_fd >= 0) close(surface->acquire_fd);
    surface->acquire_fd = -1;
}
void deck_sync_destroy(struct deck_surface *surface) {
    if (surface->sync) wl_resource_set_user_data(surface->sync, NULL);
    if (surface->acquire_fd >= 0) close(surface->acquire_fd);
    surface->acquire_fd = -1;
    deck_sync_release(surface);
}
static void acquire(struct wl_client *c, struct wl_resource *r, int32_t fd) {
    struct deck_surface *surface = wl_resource_get_user_data(r);
    uint32_t error;
    struct sync_file_info info = {0};
    if (!surface) error = ZWP_LINUX_SURFACE_SYNCHRONIZATION_V1_ERROR_NO_SURFACE;
    else if (surface->acquire_fd >= 0) error = ZWP_LINUX_SURFACE_SYNCHRONIZATION_V1_ERROR_DUPLICATE_FENCE;
    else if (ioctl(fd, SYNC_IOC_FILE_INFO, &info) < 0) error = ZWP_LINUX_SURFACE_SYNCHRONIZATION_V1_ERROR_INVALID_FENCE;
    else { surface->acquire_fd = fd; return; }
    close(fd);
    wl_resource_post_error(r, error, "The surface acquire fence is invalid, duplicated, or its surface was destroyed");
}
static void release(struct wl_client *c, struct wl_resource *r, uint32_t id) {
    struct deck_surface *surface = wl_resource_get_user_data(r);
    if (!surface) { wl_resource_post_error(r, ZWP_LINUX_SURFACE_SYNCHRONIZATION_V1_ERROR_NO_SURFACE, "The synchronized surface was destroyed"); return; }
    if (surface->release) { wl_resource_post_error(r, ZWP_LINUX_SURFACE_SYNCHRONIZATION_V1_ERROR_DUPLICATE_RELEASE, "A release was already requested for this commit"); return; }
    surface->release = wl_resource_create(c, &zwp_linux_buffer_release_v1_interface, 1, id);
    if (!surface->release) { wl_client_post_no_memory(c); return; }
    wl_resource_set_implementation(surface->release, NULL, surface, release_destroyed);
}
bool deck_sync_commit(struct deck_surface *surface, bool dmabuf) {
    if (!surface->sync) return true;
    uint32_t error;
    if ((surface->acquire_fd >= 0 || surface->release) && !surface->pending) error = ZWP_LINUX_SURFACE_SYNCHRONIZATION_V1_ERROR_NO_BUFFER;
    else if (surface->acquire_fd >= 0 && !dmabuf) error = ZWP_LINUX_SURFACE_SYNCHRONIZATION_V1_ERROR_UNSUPPORTED_BUFFER;
    else return true;
    wl_resource_post_error(surface->sync, error, "Explicit synchronization requires an attached GPU buffer");
    return false;
}
static const struct zwp_linux_surface_synchronization_v1_interface sync_impl = {
    .destroy = destroy_request, .set_acquire_fence = acquire, .get_release = release
};
static void get_sync(struct wl_client *c, struct wl_resource *r, uint32_t id, struct wl_resource *resource) {
    struct deck_surface *surface = wl_resource_get_user_data(resource);
    if (surface->sync) { wl_resource_post_error(r, ZWP_LINUX_EXPLICIT_SYNCHRONIZATION_V1_ERROR_SYNCHRONIZATION_EXISTS, "The surface already has explicit synchronization"); return; }
    surface->sync = wl_resource_create(c, &zwp_linux_surface_synchronization_v1_interface, wl_resource_get_version(r), id);
    if (!surface->sync) { wl_client_post_no_memory(c); return; }
    wl_resource_set_implementation(surface->sync, &sync_impl, surface, sync_destroyed);
}
static const struct zwp_linux_explicit_synchronization_v1_interface manager_impl = { .destroy = destroy_request, .get_synchronization = get_sync };
static void bind_sync(struct wl_client *c, void *data, uint32_t version, uint32_t id) {
    struct wl_resource *resource = wl_resource_create(c, &zwp_linux_explicit_synchronization_v1_interface, version, id);
    if (resource) wl_resource_set_implementation(resource, &manager_impl, data, NULL);
    else wl_client_post_no_memory(c);
}
bool deck_register_sync(struct deck_display *display) {
    return wl_global_create(display->wayland, &zwp_linux_explicit_synchronization_v1_interface, 2, display, bind_sync) != NULL;
}
