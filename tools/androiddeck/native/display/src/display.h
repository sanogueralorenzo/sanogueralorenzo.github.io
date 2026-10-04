#ifndef ANDROIDDECK_DISPLAY_H
#define ANDROIDDECK_DISPLAY_H
#include <android/native_window.h>
#include <pthread.h>
#include <stdbool.h>
#include <stdint.h>
#include <sys/types.h>
#include <wayland-server.h>
#include "xdg-shell-server.h"
#include "gpu.h"

struct deck_display {
    struct wl_display *wayland;
    struct wl_event_source *stop_source;
    struct wl_list surfaces;
    pthread_t thread;
    int stop_fd;
    pthread_mutex_t window_mutex;
    ANativeWindow *window;
    struct deck_gpu *gpu;
    uint64_t modifiers[64];
    size_t modifier_count;
    int format_fd;
    dev_t main_device;
    int width, height, refresh;
    int frame_width, frame_height;
    uint64_t frames;
};
struct deck_surface {
    struct wl_list link;
    struct deck_display *display;
    struct wl_resource *resource, *pending, *xdg, *toplevel;
    struct wl_listener pending_destroy;
    struct wl_list frames;
    bool configured;
    uint32_t serial;
    struct wl_resource *sync, *release;
    int acquire_fd;
};

struct deck_display *deck_start(const char *socket, ANativeWindow *window, int refresh, struct deck_gpu *gpu);
void deck_stop(struct deck_display *display);
bool deck_attach(struct deck_display *display, ANativeWindow *window);
bool deck_present(struct deck_display *display, struct wl_shm_buffer *buffer);
bool deck_register_surfaces(struct deck_display *display);
bool deck_register_shell(struct deck_display *display);
bool deck_register_dmabuf(struct deck_display *display);
struct deck_gpu_image *deck_dmabuf_image(struct wl_resource *buffer);
bool deck_register_sync(struct deck_display *display);
bool deck_sync_commit(struct deck_surface *surface, bool dmabuf);
void deck_sync_release(struct deck_surface *surface);
void deck_sync_destroy(struct deck_surface *surface);
void deck_configure(struct deck_surface *surface);
#endif
