#ifndef ANDROIDDECK_DISPLAY_H
#define ANDROIDDECK_DISPLAY_H
#include <android/native_window.h>
#include <pthread.h>
#include <stdbool.h>
#include <stdint.h>
#include <wayland-server.h>
#include "xdg-shell-server.h"

struct deck_display {
    struct wl_display *wayland;
    struct wl_event_source *stop_source;
    struct wl_list surfaces;
    pthread_t thread;
    int stop_fd;
    pthread_mutex_t window_mutex;
    ANativeWindow *window;
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
};

struct deck_display *deck_start(const char *socket, ANativeWindow *window, int refresh);
void deck_stop(struct deck_display *display);
void deck_attach(struct deck_display *display, ANativeWindow *window);
bool deck_present(struct deck_display *display, struct wl_shm_buffer *buffer);
bool deck_register_surfaces(struct deck_display *display);
bool deck_register_shell(struct deck_display *display);
void deck_configure(struct deck_surface *surface);
#endif
