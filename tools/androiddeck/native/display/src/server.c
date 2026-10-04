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
    if (count == sizeof(value)) wl_display_terminate(display->wayland);
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
    display->wayland = wl_display_create();
    if (!display->wayland) goto failed;
    if (!gpu && wl_display_init_shm(display->wayland) < 0) goto failed;
    if (wl_display_add_socket(display->wayland, socket) < 0) goto failed;
    if (!deck_register_surfaces(display) || !deck_register_shell(display)) { errno = ENOMEM; goto failed; }
    if (gpu && (!deck_register_dmabuf(display) || !deck_register_sync(display))) goto failed;
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
    const uint64_t value = 1;
    ssize_t count;
    do { count = write(display->stop_fd, &value, sizeof(value)); } while (count < 0 && errno == EINTR);
    pthread_join(display->thread, NULL);
    wl_display_destroy_clients(display->wayland);
    wl_event_source_remove(display->stop_source);
    close(display->stop_fd);
    wl_display_destroy(display->wayland);
    if (display->format_fd >= 0) close(display->format_fd);
    if (display->gpu) { deck_gpu_close(display->gpu); free(display->gpu); }
    if (display->window) ANativeWindow_release(display->window);
    pthread_mutex_destroy(&display->window_mutex);
    free(display);
}
