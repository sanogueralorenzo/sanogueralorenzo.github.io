#ifndef AMARCHY_DISPLAY_H
#define AMARCHY_DISPLAY_H
#include <android/native_window.h>
#include <pthread.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdatomic.h>
#include <wayland-server.h>
#include "xdg-shell-server.h"
#include "input.h"

struct amarchy_display {
    struct wl_display *wayland;
    struct wl_event_source *stop_source;
    struct wl_list surfaces, outputs;
    pthread_t thread;
    int stop_fd, format_fd;
    atomic_bool stopping;
    pthread_mutex_t window_mutex;
    ANativeWindow *window;
    struct amarchy_input *input;
    int width, height, refresh;
    int frame_width, frame_height;
    uint64_t frames;
    uint32_t *last_frame;
    int last_width, last_height;
    size_t last_bytes;
};
struct amarchy_surface {
    struct wl_list link;
    struct amarchy_display *display;
    struct wl_resource *resource, *pending, *xdg, *toplevel;
    struct wl_listener pending_destroy;
    struct wl_list frames;
    bool configured, cursor;
    uint32_t serial;
};
struct amarchy_display *amarchy_start(const char *socket, ANativeWindow *window, int refresh);
void amarchy_stop(struct amarchy_display *display);
bool amarchy_attach(struct amarchy_display *display, ANativeWindow *window);
bool amarchy_present(struct amarchy_display *display, const uint8_t *pixels, int width, int height, int stride, bool opaque);
bool amarchy_present_buffer(struct amarchy_display *display, struct wl_resource *buffer);
bool amarchy_register_surfaces(struct amarchy_display *display);
bool amarchy_register_shell(struct amarchy_display *display);
bool amarchy_register_dmabuf(struct amarchy_display *display);
void amarchy_configure(struct amarchy_surface *surface);
void amarchy_finish_frames(struct amarchy_surface *surface);
#endif
