#include "display.h"
#include "input.h"
#include "keymap.h"
#include <errno.h>
#include <fcntl.h>
#include <linux/input-event-codes.h>
#include <math.h>
#include <stdlib.h>
#include <string.h>
#include <sys/eventfd.h>
#include <sys/mman.h>
#include <time.h>
#include <unistd.h>

#define QUEUE_SIZE 256
struct deck_input {
    struct deck_display *display;
    struct wl_list pointers, keyboards, touches;
    struct deck_surface *focus;
    struct wl_event_source *source;
    int wake_fd, keymap_fd;
    pthread_mutex_t mutex;
    struct deck_input_event queue[QUEUE_SIZE];
    unsigned count;
    bool keys[256], buttons[3], contacts[32];
    uint32_t locked;
    float x, y;
};
static uint32_t now_ms(void) {
    struct timespec now; clock_gettime(CLOCK_MONOTONIC, &now);
    return (uint32_t)(now.tv_sec * 1000 + now.tv_nsec / 1000000);
}
static uint32_t serial(struct deck_input *input) { return wl_display_next_serial(input->display->wayland); }
static bool focused(struct deck_input *input, struct wl_resource *resource) {
    return input->focus && wl_resource_get_client(resource) == wl_resource_get_client(input->focus->resource);
}
static void pointer_frame(struct wl_resource *resource) {
    if (wl_resource_get_version(resource) >= WL_POINTER_FRAME_SINCE_VERSION) wl_pointer_send_frame(resource);
}
static void modifiers(struct deck_input *input) {
    uint32_t depressed = ((input->keys[KEY_LEFTSHIFT] || input->keys[KEY_RIGHTSHIFT]) ? 1 : 0) |
        ((input->keys[KEY_LEFTCTRL] || input->keys[KEY_RIGHTCTRL]) ? 4 : 0) |
        ((input->keys[KEY_LEFTALT] || input->keys[KEY_RIGHTALT]) ? 8 : 0) |
        ((input->keys[KEY_LEFTMETA] || input->keys[KEY_RIGHTMETA]) ? 64 : 0);
    struct wl_resource *resource;
    wl_resource_for_each(resource, &input->keyboards) if (focused(input, resource))
        wl_keyboard_send_modifiers(resource, serial(input), depressed, 0, input->locked, 0);
}
static void key(struct deck_input *input, unsigned code, bool pressed) {
    if (code >= 256 || input->keys[code] == pressed) return;
    input->keys[code] = pressed;
    if (pressed && code == KEY_CAPSLOCK) input->locked ^= 2;
    if (pressed && code == KEY_NUMLOCK) input->locked ^= 16;
    struct wl_resource *resource;
    wl_resource_for_each(resource, &input->keyboards) if (focused(input, resource))
        wl_keyboard_send_key(resource, serial(input), now_ms(), code, pressed ? WL_KEYBOARD_KEY_STATE_PRESSED : WL_KEYBOARD_KEY_STATE_RELEASED);
    modifiers(input);
}
static void pointer(struct deck_input *input, float x, float y, unsigned button, bool pressed) {
    input->x = x; input->y = y;
    int index = button >= BTN_LEFT && button <= BTN_MIDDLE ? (int)(button - BTN_LEFT) : -1;
    bool changed = index >= 0 && input->buttons[index] != pressed;
    if (changed) input->buttons[index] = pressed;
    struct wl_resource *resource;
    wl_resource_for_each(resource, &input->pointers) if (focused(input, resource)) {
        wl_pointer_send_motion(resource, now_ms(), wl_fixed_from_double(x * input->display->width), wl_fixed_from_double(y * input->display->height));
        if (changed) wl_pointer_send_button(resource, serial(input), now_ms(), button,
            pressed ? WL_POINTER_BUTTON_STATE_PRESSED : WL_POINTER_BUTTON_STATE_RELEASED);
        pointer_frame(resource);
    }
}
static void reset(struct deck_input *input) {
    for (unsigned i = 0; i < 256; i++) if (input->keys[i]) key(input, i, false);
    for (unsigned i = 0; i < 3; i++) if (input->buttons[i]) pointer(input, input->x, input->y, BTN_LEFT + i, false);
    bool contacts = false;
    for (unsigned i = 0; i < 32; i++) contacts |= input->contacts[i];
    if (contacts) {
        struct wl_resource *resource;
        wl_resource_for_each(resource, &input->touches) if (focused(input, resource)) wl_touch_send_cancel(resource);
        memset(input->contacts, 0, sizeof(input->contacts));
    }
}
static void keyboard_enter(struct deck_input *input, struct wl_resource *resource) {
    struct wl_array held; wl_array_init(&held);
    for (unsigned i = 0; i < 256; i++) if (input->keys[i]) {
        uint32_t *code = wl_array_add(&held, sizeof(*code));
        if (!code) { wl_array_release(&held); wl_client_post_no_memory(wl_resource_get_client(resource)); return; }
        *code = i;
    }
    wl_keyboard_send_enter(resource, serial(input), input->focus->resource, &held);
    wl_array_release(&held);
    modifiers(input);
}
static void pointer_enter(struct deck_input *input, struct wl_resource *resource) {
    wl_pointer_send_enter(resource, serial(input), input->focus->resource,
        wl_fixed_from_double(input->x * input->display->width), wl_fixed_from_double(input->y * input->display->height));
    pointer_frame(resource);
}
void deck_input_focus(struct deck_surface *surface) {
    struct deck_input *input = surface->display->input;
    if (!input || !surface->toplevel || input->focus == surface) return;
    reset(input);
    struct wl_resource *resource;
    if (input->focus) {
        wl_resource_for_each(resource, &input->pointers) if (focused(input, resource)) {
            wl_pointer_send_leave(resource, serial(input), input->focus->resource); pointer_frame(resource);
        }
        wl_resource_for_each(resource, &input->keyboards) if (focused(input, resource))
            wl_keyboard_send_leave(resource, serial(input), input->focus->resource);
    }
    input->focus = surface;
    wl_resource_for_each(resource, &input->pointers) if (focused(input, resource)) pointer_enter(input, resource);
    wl_resource_for_each(resource, &input->keyboards) if (focused(input, resource)) keyboard_enter(input, resource);
}
void deck_input_surface_gone(struct deck_surface *surface) {
    struct deck_input *input = surface->display->input;
    if (input && input->focus == surface) { reset(input); input->focus = NULL; }
}
static void destroy(struct wl_client *client, struct wl_resource *resource) { wl_resource_destroy(resource); }
static void removed(struct wl_resource *resource) { wl_list_remove(wl_resource_get_link(resource)); }
static void cursor(struct wl_client *client, struct wl_resource *resource, uint32_t value,
        struct wl_resource *surface_resource, int32_t x, int32_t y) {
    if (!surface_resource) return;
    struct deck_surface *surface = wl_resource_get_user_data(surface_resource);
    if (surface->xdg) { wl_resource_post_error(resource, WL_POINTER_ERROR_ROLE, "A window cannot be a cursor"); return; }
    surface->cursor = true; // Android supplies the physical mouse cursor.
}
static const struct wl_pointer_interface pointer_impl = { .set_cursor = cursor, .release = destroy };
static const struct wl_keyboard_interface keyboard_impl = { .release = destroy };
static const struct wl_touch_interface touch_impl = { .release = destroy };
static struct wl_resource *device(struct wl_client *client, struct wl_resource *seat, uint32_t id,
        const struct wl_interface *interface, const void *implementation, struct wl_list *list) {
    struct wl_resource *resource = wl_resource_create(client, interface, wl_resource_get_version(seat), id);
    if (!resource) { wl_client_post_no_memory(client); return NULL; }
    wl_resource_set_implementation(resource, implementation, wl_resource_get_user_data(seat), removed);
    wl_list_insert(list->prev, wl_resource_get_link(resource));
    return resource;
}
static void get_pointer(struct wl_client *client, struct wl_resource *seat, uint32_t id) {
    struct deck_input *input = wl_resource_get_user_data(seat);
    struct wl_resource *resource = device(client, seat, id, &wl_pointer_interface, &pointer_impl, &input->pointers);
    if (resource && focused(input, resource)) pointer_enter(input, resource);
}
static void get_keyboard(struct wl_client *client, struct wl_resource *seat, uint32_t id) {
    struct deck_input *input = wl_resource_get_user_data(seat);
    struct wl_resource *resource = device(client, seat, id, &wl_keyboard_interface, &keyboard_impl, &input->keyboards);
    if (!resource) return;
    wl_keyboard_send_keymap(resource, WL_KEYBOARD_KEYMAP_FORMAT_XKB_V1, input->keymap_fd, sizeof(deck_keymap));
    if (wl_resource_get_version(resource) >= WL_KEYBOARD_REPEAT_INFO_SINCE_VERSION) wl_keyboard_send_repeat_info(resource, 25, 400);
    if (focused(input, resource)) keyboard_enter(input, resource);
}
static void get_touch(struct wl_client *client, struct wl_resource *seat, uint32_t id) {
    struct deck_input *input = wl_resource_get_user_data(seat);
    device(client, seat, id, &wl_touch_interface, &touch_impl, &input->touches);
}
static const struct wl_seat_interface seat_impl = { .get_pointer = get_pointer, .get_keyboard = get_keyboard, .get_touch = get_touch, .release = destroy };
static void bind_seat(struct wl_client *client, void *data, uint32_t version, uint32_t id) {
    struct wl_resource *resource = wl_resource_create(client, &wl_seat_interface, version, id);
    if (!resource) { wl_client_post_no_memory(client); return; }
    wl_resource_set_implementation(resource, &seat_impl, data, NULL);
    wl_seat_send_capabilities(resource, WL_SEAT_CAPABILITY_POINTER | WL_SEAT_CAPABILITY_KEYBOARD | WL_SEAT_CAPABILITY_TOUCH);
    if (version >= WL_SEAT_NAME_SINCE_VERSION) wl_seat_send_name(resource, "androiddeck");
}
static void touch(struct deck_input *input, struct deck_input_event event) {
    unsigned id = event.code;
    if (id >= 32 || !input->focus || event.action < 0 || event.action > 2) return;
    if ((event.action == 0) == input->contacts[id]) return;
    struct wl_resource *resource;
    wl_resource_for_each(resource, &input->touches) if (focused(input, resource)) {
        wl_fixed_t x = wl_fixed_from_double(event.x * input->display->width), y = wl_fixed_from_double(event.y * input->display->height);
        if (event.action == 0) wl_touch_send_down(resource, serial(input), now_ms(), input->focus->resource, id, x, y);
        else if (event.action == 1) wl_touch_send_up(resource, serial(input), now_ms(), id);
        else wl_touch_send_motion(resource, now_ms(), id, x, y);
        wl_touch_send_frame(resource);
    }
    if (event.action != 2) input->contacts[id] = event.action == 0;
}
static int dispatch_input(int fd, uint32_t mask, void *data) {
    struct deck_input *input = data;
    uint64_t value; while (read(fd, &value, sizeof(value)) < 0 && errno == EINTR) { }
    struct deck_input_event events[QUEUE_SIZE];
    pthread_mutex_lock(&input->mutex);
    unsigned count = input->count;
    memcpy(events, input->queue, count * sizeof(*events)); input->count = 0;
    pthread_mutex_unlock(&input->mutex);
    pthread_mutex_lock(&input->display->window_mutex);
    bool visible = input->display->window != NULL;
    pthread_mutex_unlock(&input->display->window_mutex);
    if (!visible) { reset(input); wl_display_flush_clients(input->display->wayland); return 0; }
    for (unsigned i = 0; i < count; i++) {
        struct deck_input_event event = events[i];
        switch (event.type) {
        case DECK_POINTER: pointer(input, event.x, event.y, event.code, event.action); break;
        case DECK_KEY: if (input->focus) key(input, event.code, event.action); break;
        case DECK_TOUCH: touch(input, event); break;
        case DECK_RESET: reset(input); break;
        case DECK_SCROLL: {
            struct wl_resource *resource;
            wl_resource_for_each(resource, &input->pointers) if (focused(input, resource)) {
                if (event.y) wl_pointer_send_axis(resource, now_ms(), WL_POINTER_AXIS_VERTICAL_SCROLL, wl_fixed_from_double(event.y * 10));
                if (event.x) wl_pointer_send_axis(resource, now_ms(), WL_POINTER_AXIS_HORIZONTAL_SCROLL, wl_fixed_from_double(event.x * 10));
                pointer_frame(resource);
            }
        } break;
        }
    }
    wl_display_flush_clients(input->display->wayland);
    return 0;
}
bool deck_input_enqueue(struct deck_display *display, struct deck_input_event event) {
    struct deck_input *input = display->input;
    if (!input || !isfinite(event.x) || !isfinite(event.y)) return false;
    pthread_mutex_lock(&input->mutex);
    bool accepted = input->count < QUEUE_SIZE;
    if (!accepted || event.type == DECK_RESET) { input->count = 1; input->queue[0] = (struct deck_input_event){ .type = DECK_RESET }; }
    else if (event.type == DECK_POINTER && event.code == 0 && input->count && input->queue[input->count - 1].type == DECK_POINTER && !input->queue[input->count - 1].code)
        input->queue[input->count - 1] = event;
    else input->queue[input->count++] = event;
    pthread_mutex_unlock(&input->mutex);
    const uint64_t value = 1;
    ssize_t count; do { count = write(input->wake_fd, &value, sizeof(value)); } while (count < 0 && errno == EINTR);
    return accepted && (count == sizeof(value) || errno == EAGAIN);
}
bool deck_input_start(struct deck_display *display) {
    struct deck_input *input = calloc(1, sizeof(*input));
    if (!input) return false;
    input->display = display; input->wake_fd = input->keymap_fd = -1;
    wl_list_init(&input->pointers); wl_list_init(&input->keyboards); wl_list_init(&input->touches);
    int error = pthread_mutex_init(&input->mutex, NULL);
    if (error) { free(input); errno = error; return false; }
    display->input = input;
    input->keymap_fd = memfd_create("androiddeck-keymap", MFD_CLOEXEC | MFD_ALLOW_SEALING);
    if (input->keymap_fd < 0) return false;
    size_t offset = 0;
    while (offset < sizeof(deck_keymap)) {
        ssize_t count = write(input->keymap_fd, deck_keymap + offset, sizeof(deck_keymap) - offset);
        if (count < 0 && errno == EINTR) continue;
        if (count <= 0) return false;
        offset += count;
    }
    if (fcntl(input->keymap_fd, F_ADD_SEALS, F_SEAL_WRITE | F_SEAL_GROW | F_SEAL_SHRINK | F_SEAL_SEAL) < 0) return false;
    input->wake_fd = eventfd(0, EFD_CLOEXEC | EFD_NONBLOCK);
    if (input->wake_fd < 0) return false;
    input->source = wl_event_loop_add_fd(wl_display_get_event_loop(display->wayland), input->wake_fd, WL_EVENT_READABLE, dispatch_input, input);
    return input->source && wl_global_create(display->wayland, &wl_seat_interface, 5, input, bind_seat);
}
void deck_input_stop(struct deck_display *display) {
    struct deck_input *input = display->input;
    if (!input) return;
    if (input->source) wl_event_source_remove(input->source);
    if (input->wake_fd >= 0) close(input->wake_fd);
    if (input->keymap_fd >= 0) close(input->keymap_fd);
    pthread_mutex_destroy(&input->mutex);
    free(input); display->input = NULL;
}
