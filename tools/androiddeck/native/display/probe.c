#define _GNU_SOURCE
#include <wayland-client.h>
#include "xdg-shell-client.h"
#include <sys/mman.h>
#include <unistd.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdbool.h>
#include <dlfcn.h>
#include <time.h>
#ifdef DECK_VULKAN_PROBE
#include "presentation-time-client.h"
static struct wp_presentation *presentation;
static clockid_t presentation_clock = -1;
static void clock_id(void *data, struct wp_presentation *presentation, uint32_t id) { presentation_clock = id; }
static const struct wp_presentation_listener presentation_listener = { clock_id };
#endif

static int check_driver(void) {
    void *driver = dlopen("/opt/androiddeck/graphics/linux/libvulkan_freedreno.so", RTLD_NOW | RTLD_LOCAL);
    if (!driver) { fprintf(stderr, "Turnip load failed: %s\n", dlerror()); return 4; }
    int (*negotiate)(uint32_t *) = dlsym(driver, "vk_icdNegotiateLoaderICDInterfaceVersion");
    uint32_t version = 7;
    int result = negotiate ? negotiate(&version) : -1;
    if (!result) printf("linux-turnip-ready: ICD interface %u\n", version);
    else fputs("Turnip has no usable Vulkan ICD interface\n", stderr);
    dlclose(driver);
    return result ? 4 : 0;
}

void probe_input_global(struct wl_registry *registry, unsigned id, const char *name, unsigned version);
void probe_input_run(struct wl_display *display);
static bool input_mode;
static struct wl_compositor *compositor;
static struct wl_shm *shm;
static struct xdg_wm_base *shell;
static bool configured, presented, released;
static void global(void *data, struct wl_registry *registry, uint32_t id, const char *name, uint32_t version) {
    if (input_mode) probe_input_global(registry, id, name, version);
    if (!strcmp(name, "wl_compositor")) compositor = wl_registry_bind(registry, id, &wl_compositor_interface, 4);
    if (!strcmp(name, "wl_shm")) shm = wl_registry_bind(registry, id, &wl_shm_interface, 1);
    if (!strcmp(name, "xdg_wm_base")) shell = wl_registry_bind(registry, id, &xdg_wm_base_interface, 1);
#ifdef DECK_VULKAN_PROBE
    if (!strcmp(name, "wp_presentation")) {
        presentation = wl_registry_bind(registry, id, &wp_presentation_interface, 1);
        wp_presentation_add_listener(presentation, &presentation_listener, NULL);
    }
#endif
}
static void removed(void *data, struct wl_registry *registry, uint32_t id) { }
static const struct wl_registry_listener registry_listener = { global, removed };
static void ping(void *data, struct xdg_wm_base *base, uint32_t serial) { xdg_wm_base_pong(base, serial); }
static const struct xdg_wm_base_listener shell_listener = { ping };
static void configure(void *data, struct xdg_surface *surface, uint32_t serial) {
    xdg_surface_ack_configure(surface, serial); configured = true;
}
static const struct xdg_surface_listener surface_listener = { configure };
static void frame_done(void *data, struct wl_callback *callback, uint32_t time) {
    presented = true; wl_callback_destroy(callback);
}
static const struct wl_callback_listener frame_listener = { frame_done };
static void release(void *data, struct wl_buffer *buffer) { released = true; }
static const struct wl_buffer_listener buffer_listener = { release };
#ifdef DECK_VULKAN_PROBE
int probe_vulkan(struct wl_display *display, struct wl_surface *surface, struct wp_presentation *presentation, clockid_t clock);
#endif
static void dispatch_until(struct wl_display *display, const bool *value) {
    while (!*value) if (wl_display_dispatch(display) < 0) { fputs("Wayland connection failed\n", stderr); exit(2); }
}
int main(int argc, char **argv) {
    alarm(15);
    input_mode = argc > 1 && !strcmp(argv[1], "input");
    if (argc > 1 && !strcmp(argv[1], "driver")) return check_driver();
    struct wl_display *display = wl_display_connect(NULL);
    if (!display) { perror("Wayland connect"); return 1; }
    struct wl_registry *registry = wl_display_get_registry(display);
    wl_registry_add_listener(registry, &registry_listener, NULL);
    if (wl_display_roundtrip(display) < 0 || !compositor || !shell) return 2;
#ifndef DECK_VULKAN_PROBE
    if (!shm) return 2;
#endif
    xdg_wm_base_add_listener(shell, &shell_listener, NULL);
    struct wl_surface *surface = wl_compositor_create_surface(compositor);
    struct xdg_surface *xdg = xdg_wm_base_get_xdg_surface(shell, surface);
    xdg_surface_add_listener(xdg, &surface_listener, NULL);
    struct xdg_toplevel *toplevel = xdg_surface_get_toplevel(xdg);
    wl_surface_commit(surface);
    dispatch_until(display, &configured);
#ifdef DECK_VULKAN_PROBE
    if (!presentation) { fputs("Presentation-time feedback is unavailable\n", stderr); return 4; }
    // Validate our own completion timestamps directly. Gamescope's nested
    // client feedback is upstream behavior; this mode verifies visible pixels.
    bool nested = argc > 1 && !strcmp(argv[1], "nested");
    int status = probe_vulkan(display, surface, nested ? NULL : presentation, presentation_clock);
    if (status == 0 && nested) { fflush(stdout); pause(); }
    wp_presentation_destroy(presentation);
#else
    const int width = 320, height = 200, bytes = width * height * 4;
    int fd = memfd_create("androiddeck-probe", MFD_CLOEXEC);
    if (fd < 0 || ftruncate(fd, bytes) < 0) return 3;
    uint32_t *pixels = mmap(NULL, bytes, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
    if (pixels == MAP_FAILED) return 3;
    for (int y = 0; y < height; y++) for (int x = 0; x < width; x++)
        pixels[y * width + x] = y < height / 2 ? (x < width / 2 ? 0xffff0000 : 0xff00ff00) : (x < width / 2 ? 0xff0000ff : 0xffffffff);
    struct wl_shm_pool *pool = wl_shm_create_pool(shm, fd, bytes);
    struct wl_buffer *buffer = wl_shm_pool_create_buffer(pool, 0, width, height, width * 4, WL_SHM_FORMAT_XRGB8888);
    wl_buffer_add_listener(buffer, &buffer_listener, NULL);
    for (int i = 0; i < 3; i++) {
        presented = released = false;
        struct wl_callback *callback = wl_surface_frame(surface);
        wl_callback_add_listener(callback, &frame_listener, NULL);
        wl_surface_attach(surface, buffer, 0, 0);
        wl_surface_damage_buffer(surface, 0, 0, width, height);
        wl_surface_commit(surface);
        dispatch_until(display, &presented);
        dispatch_until(display, &released);
    }
    printf("linux-wayland-ok: 3 frames, 320x200, pid=%ld\n", (long)getpid()); fflush(stdout);
    if (input_mode) probe_input_run(display);
    if (argc > 1 && !strcmp(argv[1], "hold")) pause();
    wl_buffer_destroy(buffer); wl_shm_pool_destroy(pool);
    munmap(pixels, bytes); close(fd);
#endif
    xdg_toplevel_destroy(toplevel); xdg_surface_destroy(xdg); wl_surface_destroy(surface);
    xdg_wm_base_destroy(shell);
    if (shm) wl_shm_destroy(shm);
    wl_compositor_destroy(compositor); wl_registry_destroy(registry);
    wl_display_flush(display); wl_display_disconnect(display);
#ifdef DECK_VULKAN_PROBE
    return status;
#else
    return 0;
#endif
}
