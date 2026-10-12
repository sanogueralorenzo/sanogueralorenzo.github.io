#include "display.h"
#include <errno.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

static bool post_frame(struct amarchy_display *display) {
    ANativeWindow *window = display->window;
    if (!window || !display->last_frame) return true;
    int width = display->last_width, height = display->last_height;
    ANativeWindow_Buffer destination;
    bool posted = false;
    if (ANativeWindow_setBuffersGeometry(window, width, height, WINDOW_FORMAT_RGBA_8888) == 0 &&
        ANativeWindow_lock(window, &destination, NULL) == 0) {
        for (int y = 0; y < height; y++) {
            uint32_t *out = (uint32_t *)destination.bits + (size_t)y * destination.stride;
            memcpy(out, display->last_frame + (size_t)y * width, width * sizeof(uint32_t));
        }
        posted = ANativeWindow_unlockAndPost(window) == 0;
    }
    return posted;
}
bool amarchy_present(struct amarchy_display *display, const uint8_t *source, int width, int height, int stride, bool opaque) {
    size_t bytes = (size_t)width * height * sizeof(uint32_t);
    if (width <= 0 || width > 8192 || height <= 0 || height > 8192 || stride < width * 4 || bytes > 256 * 1024 * 1024) return false;
    pthread_mutex_lock(&display->window_mutex);
    if (display->last_bytes != bytes) {
        uint32_t *frame = realloc(display->last_frame, bytes);
        if (!frame) { pthread_mutex_unlock(&display->window_mutex); return false; }
        display->last_frame = frame; display->last_bytes = bytes;
    }
    display->last_width = width; display->last_height = height;
    for (int y = 0; y < height; y++) {
        const uint32_t *row = (const uint32_t *)(source + (size_t)y * stride);
        uint32_t *out = display->last_frame + (size_t)y * width;
        for (int x = 0; x < width; x++) {
            uint32_t pixel = row[x];
            out[x] = (pixel & 0xff00ff00u) | ((pixel & 0xffu) << 16) | ((pixel >> 16) & 0xffu);
            if (opaque) out[x] |= 0xff000000u;
        }
    }
    bool posted = post_frame(display);
    if (posted && display->window) { display->frames++; display->frame_width = width; display->frame_height = height; }
    pthread_mutex_unlock(&display->window_mutex);
    return posted;
}
bool amarchy_attach(struct amarchy_display *display, ANativeWindow *window) {
    if (!window) amarchy_input_enqueue(display, (struct amarchy_input_event){ .type = AMARCHY_RESET });
    pthread_mutex_lock(&display->window_mutex);
    if (display->window) ANativeWindow_release(display->window);
    display->window = window;
    bool posted = post_frame(display);
    pthread_mutex_unlock(&display->window_mutex);
    if (!posted) return false;
    if (window) {
        const uint64_t value = 1;
        ssize_t count;
        do { count = write(display->stop_fd, &value, sizeof(value)); } while (count < 0 && errno == EINTR);
        return count == sizeof(value);
    }
    return true;
}
