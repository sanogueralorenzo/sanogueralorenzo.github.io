#include "display.h"
#include <errno.h>

bool deck_present(struct deck_display *display, struct wl_shm_buffer *buffer) {
    const int width = wl_shm_buffer_get_width(buffer);
    const int height = wl_shm_buffer_get_height(buffer);
    const int stride = wl_shm_buffer_get_stride(buffer);
    const uint32_t format = wl_shm_buffer_get_format(buffer);
    if (width <= 0 || width > 8192 || height <= 0 || height > 8192 || stride < width * 4 ||
        (format != WL_SHM_FORMAT_ARGB8888 && format != WL_SHM_FORMAT_XRGB8888)) return false;
    pthread_mutex_lock(&display->window_mutex);
    ANativeWindow *window = display->window;
    ANativeWindow_Buffer destination;
    bool posted = false;
    if (window && ANativeWindow_setBuffersGeometry(window, width, height, WINDOW_FORMAT_RGBA_8888) == 0 &&
        ANativeWindow_lock(window, &destination, NULL) == 0) {
        wl_shm_buffer_begin_access(buffer);
        const uint8_t *source = wl_shm_buffer_get_data(buffer);
        for (int y = 0; y < height; y++) {
            const uint32_t *row = (const uint32_t *)(source + (size_t)y * stride);
            uint32_t *out = (uint32_t *)destination.bits + (size_t)y * destination.stride;
            for (int x = 0; x < width; x++) {
                // Wayland ARGB is BGRA in little-endian memory; Android expects RGBA.
                const uint32_t pixel = row[x];
                out[x] = (pixel & 0xff00ff00u) | ((pixel & 0xffu) << 16) | ((pixel >> 16) & 0xffu);
                if (format == WL_SHM_FORMAT_XRGB8888) out[x] |= 0xff000000u;
            }
        }
        wl_shm_buffer_end_access(buffer);
        posted = ANativeWindow_unlockAndPost(window) == 0;
        if (posted) {
            display->frames++; display->frame_width = width; display->frame_height = height;
        }
    }
    pthread_mutex_unlock(&display->window_mutex);
    return posted;
}

void deck_attach(struct deck_display *display, ANativeWindow *window) {
    pthread_mutex_lock(&display->window_mutex);
    if (display->window) ANativeWindow_release(display->window);
    display->window = window; // Ownership of fromSurface's acquired reference transfers here.
    pthread_mutex_unlock(&display->window_mutex);
}
