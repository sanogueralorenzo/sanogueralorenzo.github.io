#include "display.h"
#include <stdlib.h>
#include <sys/eventfd.h>
#include <unistd.h>
#include <errno.h>

static int stop_event(int fd, uint32_t mask, void *data) {
    struct deck_display *display = data;
    uint64_t value;
    ssize_t count;
    do { count = read(fd, &value, sizeof(value)); } while (count < 0 && errno == EINTR);
    if (count != sizeof(value)) return 0;
    if (atomic_load(&display->stopping)) wl_display_terminate(display->wayland);
    else {
        // Reattachment wakes clients whose frame callbacks were held while hidden.
        pthread_mutex_lock(&display->window_mutex);
        if (display->window) {
            struct deck_surface *surface;
            wl_list_for_each(surface, &display->surfaces, link) deck_finish_frames(surface);
        }
        pthread_mutex_unlock(&display->window_mutex);
        wl_display_flush_clients(display->wayland);
    }
    return 0;
}
static void *dispatch(void *data) {
    wl_display_run(((struct deck_display *)data)->wayland);
    return NULL;
}
struct deck_display *deck_start(const char *socket, ANativeWindow *window, int refresh, struct deck_gpu *gpu) {
    struct deck_display *display = calloc(1, sizeof(*display));
    if (!display) { ANativeWindow_release(window); return NULL; }
    display->stop_fd = -1;
    atomic_init(&display->stopping, false);
    display->format_fd = -1;
    int error = pthread_mutex_init(&display->window_mutex, NULL);
    if (error) { ANativeWindow_release(window); free(display); errno = error; return NULL; }
    display->window = window;
    display->gpu = gpu;
    if (gpu && !deck_gpu_attach(gpu, window)) { errno = ENODEV; goto failed; }
    display->width = ANativeWindow_getWidth(window);
    display->height = ANativeWindow_getHeight(window);
    display->refresh = refresh;
    wl_list_init(&display->surfaces);
    wl_list_init(&display->outputs);
    display->wayland = wl_display_create();
    if (!display->wayland) goto failed;
    // SDL allocates cursor images through wl_shm even with a Vulkan window.
    // GPU display commits still require dma-bufs in deck_present.
    if (wl_display_init_shm(display->wayland) < 0) goto failed;
    if (wl_display_add_socket(display->wayland, socket) < 0) goto failed;
    if (!deck_register_surfaces(display) || !deck_register_shell(display)) { errno = ENOMEM; goto failed; }
    if (gpu && (!deck_register_dmabuf(display) || !deck_register_sync(display) || !deck_register_feedback(display))) goto failed;
    display->stop_fd = eventfd(0, EFD_CLOEXEC | EFD_NONBLOCK);
    if (display->stop_fd < 0) goto failed;
    display->stop_source = wl_event_loop_add_fd(wl_display_get_event_loop(display->wayland), display->stop_fd, WL_EVENT_READABLE, stop_event, display);
    if (!display->stop_source) goto failed;
    error = pthread_create(&display->thread, NULL, dispatch, display);
    if (error) { errno = error; goto failed; }
    return display;
failed:
    error = errno;
    if (display->stop_source) wl_event_source_remove(display->stop_source);
    if (display->feedback_source) wl_event_source_remove(display->feedback_source);
    if (display->stop_fd >= 0) close(display->stop_fd);
    if (display->wayland) wl_display_destroy(display->wayland);
    if (display->format_fd >= 0) close(display->format_fd);
    if (gpu) deck_gpu_detach(gpu);
    ANativeWindow_release(display->window);
    pthread_mutex_destroy(&display->window_mutex);
    free(display);
    errno = error;
    return NULL;
}
void deck_stop(struct deck_display *display) {
    atomic_store(&display->stopping, true);
    const uint64_t value = 1;
    ssize_t count;
    do { count = write(display->stop_fd, &value, sizeof(value)); } while (count < 0 && errno == EINTR);
    pthread_join(display->thread, NULL);
    wl_display_destroy_clients(display->wayland);
    if (display->feedback_source) wl_event_source_remove(display->feedback_source);
    wl_event_source_remove(display->stop_source);
    close(display->stop_fd);
    wl_display_destroy(display->wayland);
    if (display->format_fd >= 0) close(display->format_fd);
    if (display->gpu) { deck_gpu_close(display->gpu); free(display->gpu); }
    if (display->window) ANativeWindow_release(display->window);
    pthread_mutex_destroy(&display->window_mutex);
    free(display);
}
