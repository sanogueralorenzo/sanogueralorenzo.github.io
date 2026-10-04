#define _GNU_SOURCE
#include <wayland-client.h>
#include <dlfcn.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <unistd.h>
static struct wl_seat *seat;
static struct wl_keyboard *keyboard;
static struct wl_pointer *pointer;
static struct wl_touch *touch;
static void *context, *map, *state;
static void *(*state_new)(void *);
static int (*update_mask)(void *, unsigned, unsigned, unsigned, unsigned, unsigned, unsigned);
static unsigned (*utf32)(void *, unsigned);
static void keymap(void *data, struct wl_keyboard *kb, unsigned format, int fd, unsigned size) {
    void *library = dlopen("libxkbcommon.so.0", RTLD_NOW);
    void *(*context_new)(int) = library ? dlsym(library, "xkb_context_new") : NULL;
    void *(*map_new)(void *, const char *, int, int) = library ? dlsym(library, "xkb_keymap_new_from_string") : NULL;
    state_new = library ? dlsym(library, "xkb_state_new") : NULL;
    update_mask = library ? dlsym(library, "xkb_state_update_mask") : NULL;
    utf32 = library ? dlsym(library, "xkb_state_key_get_utf32") : NULL;
    char *text = mmap(NULL, size, PROT_READ, MAP_PRIVATE, fd, 0); close(fd);
    if (format != 1 || !size || text == MAP_FAILED || text[size - 1] != 0 || !context_new || !map_new || !state_new || !update_mask || !utf32) exit(5);
    context = context_new(0); map = map_new(context, text, 1, 0); munmap(text, size);
    if (!context || !map || !(state = state_new(map))) exit(5);
    puts("input-keymap-ok"); fflush(stdout);
}
static void kb_enter(void *d, struct wl_keyboard *k, unsigned s, struct wl_surface *surface, struct wl_array *keys) { puts("input-keyboard-focus"); fflush(stdout); }
static void kb_leave(void *d, struct wl_keyboard *k, unsigned s, struct wl_surface *surface) { }
static void kb_key(void *d, struct wl_keyboard *k, unsigned s, unsigned time, unsigned code, unsigned pressed) {
    printf("input-key %u %u %u\n", code, pressed, state ? utf32(state, code + 8) : 0); fflush(stdout);
}
static void kb_mods(void *d, struct wl_keyboard *k, unsigned s, unsigned depressed, unsigned latched, unsigned locked, unsigned group) {
    if (state) update_mask(state, depressed, latched, locked, 0, 0, group);
    printf("input-modifiers %u %u\n", depressed, locked); fflush(stdout);
}
static void repeat(void *d, struct wl_keyboard *k, int rate, int delay) { }
static const struct wl_keyboard_listener keyboard_listener = { keymap, kb_enter, kb_leave, kb_key, kb_mods, repeat };
static void ptr_enter(void *d, struct wl_pointer *p, unsigned s, struct wl_surface *surface, wl_fixed_t x, wl_fixed_t y) { }
static void ptr_leave(void *d, struct wl_pointer *p, unsigned s, struct wl_surface *surface) { }
static void ptr_motion(void *d, struct wl_pointer *p, unsigned time, wl_fixed_t x, wl_fixed_t y) { printf("input-pointer %.0f %.0f\n", wl_fixed_to_double(x), wl_fixed_to_double(y)); fflush(stdout); }
static void ptr_button(void *d, struct wl_pointer *p, unsigned s, unsigned time, unsigned button, unsigned pressed) { printf("input-button %u %u\n", button, pressed); fflush(stdout); }
static void ptr_axis(void *d, struct wl_pointer *p, unsigned time, unsigned axis, wl_fixed_t value) { }
static void ptr_frame(void *d, struct wl_pointer *p) { }
static void ptr_source(void *d, struct wl_pointer *p, unsigned source) { }
static void ptr_stop(void *d, struct wl_pointer *p, unsigned time, unsigned axis) { }
static void ptr_discrete(void *d, struct wl_pointer *p, unsigned axis, int value) { }
static const struct wl_pointer_listener pointer_listener = { .enter = ptr_enter, .leave = ptr_leave, .motion = ptr_motion, .button = ptr_button, .axis = ptr_axis, .frame = ptr_frame, .axis_source = ptr_source, .axis_stop = ptr_stop, .axis_discrete = ptr_discrete };
static void touch_down(void *d, struct wl_touch *t, unsigned s, unsigned time, struct wl_surface *surface, int id, wl_fixed_t x, wl_fixed_t y) { printf("input-touch-down %d %.0f %.0f\n", id, wl_fixed_to_double(x), wl_fixed_to_double(y)); fflush(stdout); }
static void touch_up(void *d, struct wl_touch *t, unsigned s, unsigned time, int id) { printf("input-touch-up %d\n", id); fflush(stdout); }
static void touch_motion(void *d, struct wl_touch *t, unsigned time, int id, wl_fixed_t x, wl_fixed_t y) { printf("input-touch-motion %d %.0f %.0f\n", id, wl_fixed_to_double(x), wl_fixed_to_double(y)); fflush(stdout); }
static void touch_frame(void *d, struct wl_touch *t) { }
static void touch_cancel(void *d, struct wl_touch *t) { puts("input-touch-cancel"); fflush(stdout); }
static const struct wl_touch_listener touch_listener = { .down = touch_down, .up = touch_up, .motion = touch_motion, .frame = touch_frame, .cancel = touch_cancel };
static void capabilities(void *d, struct wl_seat *s, unsigned caps) {
    if (!keyboard && (caps & WL_SEAT_CAPABILITY_KEYBOARD)) { keyboard = wl_seat_get_keyboard(s); wl_keyboard_add_listener(keyboard, &keyboard_listener, NULL); }
    if (!pointer && (caps & WL_SEAT_CAPABILITY_POINTER)) { pointer = wl_seat_get_pointer(s); wl_pointer_add_listener(pointer, &pointer_listener, NULL); }
    if (!touch && (caps & WL_SEAT_CAPABILITY_TOUCH)) { touch = wl_seat_get_touch(s); wl_touch_add_listener(touch, &touch_listener, NULL); }
}
static void name(void *d, struct wl_seat *s, const char *name) { }
static const struct wl_seat_listener seat_listener = { capabilities, name };
void probe_input_global(struct wl_registry *registry, unsigned id, const char *name, unsigned version) {
    if (strcmp(name, "wl_seat")) return;
    seat = wl_registry_bind(registry, id, &wl_seat_interface, version < 5 ? version : 5);
    wl_seat_add_listener(seat, &seat_listener, NULL);
}
void probe_input_run(struct wl_display *display) {
    if (!seat) exit(5);
    puts("input-ready"); fflush(stdout);
    while (wl_display_dispatch(display) >= 0) { }
}
