#include "display.h"
#include "presentation-time-server.h"
#include <stdlib.h>
#include <time.h>

struct feedback {
    struct wl_list link;
    struct wl_resource *resource;
    uint32_t present_id;
    uint64_t generation, submitted_at;
};
static uint64_t monotonic_time(void) {
    struct timespec now; clock_gettime(CLOCK_MONOTONIC, &now);
    return (uint64_t)now.tv_sec * 1000000000u + now.tv_nsec;
}
static void destroyed(struct wl_resource *resource) {
    struct feedback *feedback = wl_resource_get_user_data(resource);
    wl_list_remove(&feedback->link); free(feedback);
}
static void discard(struct feedback *feedback) {
    wp_presentation_feedback_send_discarded(feedback->resource);
    wl_resource_destroy(feedback->resource);
}
void deck_feedback_discard(struct deck_surface *surface) {
    struct feedback *feedback, *next;
    wl_list_for_each_safe(feedback, next, &surface->feedback, link) discard(feedback);
}
void deck_feedback_commit(struct deck_surface *surface, uint32_t present_id) {
    struct feedback *feedback, *next;
    wl_list_for_each_safe(feedback, next, &surface->feedback, link) {
        if (feedback->present_id) continue;
        if (!present_id) { discard(feedback); continue; }
        feedback->present_id = present_id;
        feedback->generation = surface->display->gpu->generation;
        feedback->submitted_at = monotonic_time();
        wl_event_source_timer_update(surface->display->feedback_source, 1);
    }
}
static void presented(struct deck_display *display, struct feedback *feedback, uint64_t timestamp) {
    struct wl_resource *output;
    wl_resource_for_each(output, &display->outputs) {
        if (wl_resource_get_client(output) == wl_resource_get_client(feedback->resource))
            wp_presentation_feedback_send_sync_output(feedback->resource, output);
    }
    const uint64_t seconds = timestamp / 1000000000u;
    // Android's timestamp is actual display completion. FIFO prevents tearing;
    // do not claim zero-copy, a hardware clock, or a known panel refresh counter.
    // Adaptive refresh has no reliable prediction here, so report refresh = 0.
    wp_presentation_feedback_send_presented(feedback->resource, seconds >> 32, (uint32_t)seconds,
        timestamp % 1000000000u, 0, 0, 0, WP_PRESENTATION_FEEDBACK_KIND_VSYNC);
    wl_resource_destroy(feedback->resource);
}
static int poll_timestamps(void *data) {
    struct deck_display *display = data;
    pthread_mutex_lock(&display->window_mutex);
    struct deck_gpu *gpu = display->gpu;
    VkPastPresentationTimingGOOGLE timings[32];
    uint32_t count = 32;
    VkResult result = gpu->swapchain ? gpu->vk.GetPastPresentationTimingGOOGLE(gpu->device, gpu->swapchain, &count, timings) : VK_ERROR_OUT_OF_DATE_KHR;
    const uint64_t now = monotonic_time();
    bool waiting = false;
    struct deck_surface *surface;
    wl_list_for_each(surface, &display->surfaces, link) {
        struct feedback *feedback, *next;
        wl_list_for_each_safe(feedback, next, &surface->feedback, link) {
            if (!feedback->present_id) continue;
            if (feedback->generation != gpu->generation || result == VK_ERROR_OUT_OF_DATE_KHR) { discard(feedback); continue; }
            uint64_t timestamp = 0;
            bool returned = false;
            if (result == VK_SUCCESS || result == VK_INCOMPLETE) {
                for (uint32_t i = 0; i < count; i++) if (timings[i].presentID == feedback->present_id) {
                    timestamp = timings[i].actualPresentTime; returned = true; break;
                }
            }
            if (timestamp) { presented(display, feedback, timestamp); continue; }
            if (result != VK_SUCCESS && result != VK_INCOMPLETE) {
                wl_client_post_implementation_error(wl_resource_get_client(feedback->resource),
                    "Android presentation timing query failed (%d). Stop the session and retry.", result);
                wl_resource_destroy(feedback->resource);
            } else if (returned || now - feedback->submitted_at > 1000000000u) {
                // Android can omit a frame's timing or return zero when it was
                // not displayed. Expire that feedback without killing the
                // client or substituting a fabricated presentation timestamp.
                discard(feedback);
            } else waiting = true;
        }
    }
    pthread_mutex_unlock(&display->window_mutex);
    if (waiting) wl_event_source_timer_update(display->feedback_source, 4);
    return 0;
}
static void destroy_request(struct wl_client *client, struct wl_resource *resource) { wl_resource_destroy(resource); }
static void request_feedback(struct wl_client *client, struct wl_resource *resource, struct wl_resource *wl_surface, uint32_t id) {
    struct deck_surface *surface = wl_resource_get_user_data(wl_surface);
    struct feedback *feedback = calloc(1, sizeof(*feedback));
    if (!feedback) { wl_client_post_no_memory(client); return; }
    feedback->resource = wl_resource_create(client, &wp_presentation_feedback_interface, wl_resource_get_version(resource), id);
    if (!feedback->resource) { free(feedback); wl_client_post_no_memory(client); return; }
    wl_list_insert(surface->feedback.prev, &feedback->link);
    wl_resource_set_implementation(feedback->resource, NULL, feedback, destroyed);
}
static const struct wp_presentation_interface presentation_impl = { .destroy = destroy_request, .feedback = request_feedback };
static void bind_presentation(struct wl_client *client, void *data, uint32_t version, uint32_t id) {
    struct wl_resource *resource = wl_resource_create(client, &wp_presentation_interface, version, id);
    if (!resource) { wl_client_post_no_memory(client); return; }
    wl_resource_set_implementation(resource, &presentation_impl, data, NULL);
    wp_presentation_send_clock_id(resource, CLOCK_MONOTONIC);
}
bool deck_register_feedback(struct deck_display *display) {
    display->feedback_source = wl_event_loop_add_timer(wl_display_get_event_loop(display->wayland), poll_timestamps, display);
    return display->feedback_source && wl_global_create(display->wayland, &wp_presentation_interface, 2, display, bind_presentation);
}
