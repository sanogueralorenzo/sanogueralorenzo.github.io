#include "display.h"
#include <stdlib.h>
#include <time.h>
#include <unistd.h>
#include <stdio.h>

struct frame_callback { struct wl_list link; struct wl_resource *resource; };
static void destroy_request(struct wl_client *client, struct wl_resource *resource) { wl_resource_destroy(resource); }
static void buffer_gone(struct wl_listener *listener, void *data) {
    struct deck_surface *surface = wl_container_of(listener, surface, pending_destroy);
    surface->pending = NULL;
    wl_list_remove(&listener->link);
    wl_list_init(&listener->link);
}
static void attach(struct wl_client *client, struct wl_resource *resource, struct wl_resource *buffer, int32_t x, int32_t y) {
    struct deck_surface *surface = wl_resource_get_user_data(resource);
    if (surface->pending) wl_list_remove(&surface->pending_destroy.link);
    surface->pending = buffer;
    wl_list_init(&surface->pending_destroy.link);
    if (buffer) wl_resource_add_destroy_listener(buffer, &surface->pending_destroy);
}
static void damage(struct wl_client *c, struct wl_resource *r, int32_t x, int32_t y, int32_t w, int32_t h) { }
static void region(struct wl_client *c, struct wl_resource *r, struct wl_resource *region) { }
static void transform(struct wl_client *c, struct wl_resource *r, int32_t value) {
    if (value != WL_OUTPUT_TRANSFORM_NORMAL) wl_resource_post_error(r, WL_SURFACE_ERROR_INVALID_TRANSFORM, "Only normal buffer orientation is supported");
}
static void scale(struct wl_client *c, struct wl_resource *r, int32_t value) {
    if (value < 1) wl_resource_post_error(r, WL_SURFACE_ERROR_INVALID_SCALE, "Buffer scale must be positive");
}
static void frame_destroyed(struct wl_resource *resource) {
    struct frame_callback *frame = wl_resource_get_user_data(resource);
    wl_list_remove(&frame->link); free(frame);
}
static void frame(struct wl_client *client, struct wl_resource *resource, uint32_t id) {
    struct deck_surface *surface = wl_resource_get_user_data(resource);
    struct frame_callback *callback = calloc(1, sizeof(*callback));
    if (!callback) { wl_client_post_no_memory(client); return; }
    callback->resource = wl_resource_create(client, &wl_callback_interface, 1, id);
    if (!callback->resource) { free(callback); wl_client_post_no_memory(client); return; }
    wl_list_insert(surface->frames.prev, &callback->link);
    wl_resource_set_implementation(callback->resource, NULL, callback, frame_destroyed);
}
void deck_finish_frames(struct deck_surface *surface) {
    struct timespec now; clock_gettime(CLOCK_MONOTONIC, &now);
    struct frame_callback *callback, *next;
    wl_list_for_each_safe(callback, next, &surface->frames, link) {
        wl_callback_send_done(callback->resource, (uint32_t)(now.tv_sec * 1000 + now.tv_nsec / 1000000));
        wl_resource_destroy(callback->resource);
    }
}
static void commit(struct wl_client *client, struct wl_resource *resource) {
    struct deck_surface *surface = wl_resource_get_user_data(resource);
    struct deck_gpu_image *image = surface->pending ? deck_dmabuf_image(surface->pending) : NULL;
    if (!deck_sync_commit(surface, image != NULL)) return;
    if (surface->xdg && !surface->configured) {
        if (surface->pending) wl_resource_post_error(surface->xdg, XDG_SURFACE_ERROR_UNCONFIGURED_BUFFER, "Acknowledge the initial configure before attaching a buffer");
        else if (!surface->serial) deck_configure(surface);
        deck_feedback_commit(surface, 0);
        return;
    }
    if (surface->pending) {
        bool presented = false;
        char failure[256] = "Cannot present this Wayland buffer on the Android surface";
        if (image) {
            struct deck_display *display = surface->display;
            pthread_mutex_lock(&display->window_mutex);
            int fd = surface->acquire_fd; surface->acquire_fd = -1;
            uint32_t present_id = 0;
            if (!display->window) { if (fd >= 0) close(fd); presented = true; }
            else if (deck_gpu_present(display->gpu, image, fd, &present_id)) {
                presented = true;
                if (present_id) {
                    display->frames++;
                    display->frame_width = image->width; display->frame_height = image->height;
                }
            }
            else snprintf(failure, sizeof(failure), "%s", display->gpu->error);
            if (presented) deck_feedback_commit(surface, present_id);
            pthread_mutex_unlock(&display->window_mutex);
        } else {
            struct wl_shm_buffer *buffer = wl_shm_buffer_get(surface->pending);
            presented = buffer && deck_present(surface->display, buffer);
        }
        if (!presented) {
            wl_client_post_implementation_error(client, "%s", failure);
            return;
        }
        deck_sync_release(surface);
        wl_buffer_send_release(surface->pending);
        wl_list_remove(&surface->pending_destroy.link);
        wl_list_init(&surface->pending_destroy.link);
        surface->pending = NULL;
    } else deck_feedback_commit(surface, 0);
    pthread_mutex_lock(&surface->display->window_mutex);
    if (surface->display->window && (!surface->display->gpu || surface->display->gpu->window)) deck_finish_frames(surface);
    pthread_mutex_unlock(&surface->display->window_mutex);
}
static const struct wl_surface_interface surface_impl = {
    .destroy = destroy_request, .attach = attach, .damage = damage, .frame = frame,
    .set_opaque_region = region, .set_input_region = region, .commit = commit,
    .set_buffer_transform = transform, .set_buffer_scale = scale, .damage_buffer = damage
};
static void surface_destroyed(struct wl_resource *resource) {
    struct deck_surface *surface = wl_resource_get_user_data(resource);
    deck_sync_destroy(surface);
    deck_feedback_discard(surface);
    if (surface->pending) wl_list_remove(&surface->pending_destroy.link);
    if (surface->xdg) wl_resource_set_user_data(surface->xdg, NULL);
    if (surface->toplevel) wl_resource_set_user_data(surface->toplevel, NULL);
    struct frame_callback *callback, *next;
    wl_list_for_each_safe(callback, next, &surface->frames, link) wl_resource_destroy(callback->resource);
    wl_list_remove(&surface->link);
    free(surface);
}
static void create_surface(struct wl_client *client, struct wl_resource *resource, uint32_t id) {
    struct deck_display *display = wl_resource_get_user_data(resource);
    struct deck_surface *surface = calloc(1, sizeof(*surface));
    if (!surface) { wl_client_post_no_memory(client); return; }
    surface->resource = wl_resource_create(client, &wl_surface_interface, wl_resource_get_version(resource), id);
    if (!surface->resource) { free(surface); wl_client_post_no_memory(client); return; }
    surface->display = display;
    surface->acquire_fd = -1;
    surface->pending_destroy.notify = buffer_gone;
    wl_list_init(&surface->pending_destroy.link); wl_list_init(&surface->frames);
    wl_list_init(&surface->feedback);
    wl_list_insert(&display->surfaces, &surface->link);
    wl_resource_set_implementation(surface->resource, &surface_impl, surface, surface_destroyed);
}
static const struct wl_region_interface region_impl = { .destroy = destroy_request, .add = damage, .subtract = damage };
static void create_region(struct wl_client *client, struct wl_resource *resource, uint32_t id) {
    struct wl_resource *region = wl_resource_create(client, &wl_region_interface, 1, id);
    if (region) wl_resource_set_implementation(region, &region_impl, NULL, NULL);
    else wl_client_post_no_memory(client);
}
static const struct wl_compositor_interface compositor_impl = { .create_surface = create_surface, .create_region = create_region };
static void bind_compositor(struct wl_client *client, void *data, uint32_t version, uint32_t id) {
    struct wl_resource *resource = wl_resource_create(client, &wl_compositor_interface, version, id);
    if (resource) wl_resource_set_implementation(resource, &compositor_impl, data, NULL);
    else wl_client_post_no_memory(client);
}
bool deck_register_surfaces(struct deck_display *display) {
    return wl_global_create(display->wayland, &wl_compositor_interface, 4, display, bind_compositor) != NULL;
}
