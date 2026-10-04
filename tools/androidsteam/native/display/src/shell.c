#include "display.h"

static void destroy_request(struct wl_client *client, struct wl_resource *resource) { wl_resource_destroy(resource); }
static void label(struct wl_client *client, struct wl_resource *resource, const char *text) { }
static void parent(struct wl_client *client, struct wl_resource *resource, struct wl_resource *parent) { }
static void menu(struct wl_client *c, struct wl_resource *r, struct wl_resource *seat, uint32_t serial, int32_t x, int32_t y) { }
static void move(struct wl_client *c, struct wl_resource *r, struct wl_resource *seat, uint32_t serial) { }
static void resize(struct wl_client *c, struct wl_resource *r, struct wl_resource *seat, uint32_t serial, uint32_t edges) { }
static void size(struct wl_client *c, struct wl_resource *r, int32_t w, int32_t h) {
    if (w < 0 || h < 0) wl_resource_post_error(r, XDG_TOPLEVEL_ERROR_INVALID_SIZE, "Window size cannot be negative");
}
void deck_configure(struct deck_surface *surface) {
    if (!surface->xdg || !surface->toplevel) return;
    struct wl_array states; wl_array_init(&states);
    xdg_toplevel_send_configure(surface->toplevel, surface->display->width, surface->display->height, &states);
    surface->serial = wl_display_next_serial(surface->display->wayland);
    xdg_surface_send_configure(surface->xdg, surface->serial);
    wl_array_release(&states);
}
static void reconfigure(struct wl_client *client, struct wl_resource *resource) {
    struct deck_surface *surface = wl_resource_get_user_data(resource);
    if (surface) deck_configure(surface);
}
static void fullscreen(struct wl_client *client, struct wl_resource *resource, struct wl_resource *output) { reconfigure(client, resource); }
static void toplevel_destroyed(struct wl_resource *resource) {
    struct deck_surface *surface = wl_resource_get_user_data(resource);
    if (surface) surface->toplevel = NULL;
}
static const struct xdg_toplevel_interface toplevel_impl = {
    .destroy = destroy_request, .set_parent = parent, .set_title = label, .set_app_id = label,
    .show_window_menu = menu, .move = move, .resize = resize,
    .set_max_size = size, .set_min_size = size, .set_maximized = reconfigure,
    .unset_maximized = reconfigure, .set_fullscreen = fullscreen,
    .unset_fullscreen = reconfigure, .set_minimized = reconfigure
};
static void get_toplevel(struct wl_client *client, struct wl_resource *resource, uint32_t id) {
    struct deck_surface *surface = wl_resource_get_user_data(resource);
    if (!surface || surface->toplevel) {
        wl_resource_post_error(resource, XDG_SURFACE_ERROR_ALREADY_CONSTRUCTED, "Surface has no available toplevel role"); return;
    }
    surface->toplevel = wl_resource_create(client, &xdg_toplevel_interface, 1, id);
    if (surface->toplevel) wl_resource_set_implementation(surface->toplevel, &toplevel_impl, surface, toplevel_destroyed);
    else wl_client_post_no_memory(client);
}
static void popup(struct wl_client *c, struct wl_resource *r, uint32_t id, struct wl_resource *parent, struct wl_resource *positioner) {
    wl_resource_post_error(r, XDG_WM_BASE_ERROR_INVALID_POPUP_PARENT, "Nested popup surfaces are not supported by this display bridge yet");
}
static void geometry(struct wl_client *c, struct wl_resource *r, int32_t x, int32_t y, int32_t w, int32_t h) {
    if (w <= 0 || h <= 0) wl_resource_post_error(r, XDG_SURFACE_ERROR_INVALID_SIZE, "Window geometry must have positive dimensions");
}
static void acknowledge(struct wl_client *client, struct wl_resource *resource, uint32_t serial) {
    struct deck_surface *surface = wl_resource_get_user_data(resource);
    if (!surface || serial != surface->serial) { wl_resource_post_error(resource, XDG_SURFACE_ERROR_INVALID_SERIAL, "Unknown configure serial"); return; }
    surface->configured = true;
}
static void xdg_destroyed(struct wl_resource *resource) {
    struct deck_surface *surface = wl_resource_get_user_data(resource);
    if (surface) { surface->xdg = NULL; surface->configured = false; }
}
static const struct xdg_surface_interface xdg_impl = {
    .destroy = destroy_request, .get_toplevel = get_toplevel, .get_popup = popup,
    .set_window_geometry = geometry, .ack_configure = acknowledge
};
static void get_xdg(struct wl_client *client, struct wl_resource *resource, uint32_t id, struct wl_resource *wl_surface) {
    struct deck_surface *surface = wl_resource_get_user_data(wl_surface);
    if (surface->xdg || surface->cursor) { wl_resource_post_error(resource, XDG_WM_BASE_ERROR_ROLE, "Surface already has a shell role"); return; }
    surface->xdg = wl_resource_create(client, &xdg_surface_interface, 1, id);
    if (surface->xdg) wl_resource_set_implementation(surface->xdg, &xdg_impl, surface, xdg_destroyed);
    else wl_client_post_no_memory(client);
}
static void positioner(struct wl_client *client, struct wl_resource *resource, uint32_t id) {
    wl_resource_post_error(resource, XDG_WM_BASE_ERROR_INVALID_POSITIONER, "Popup positioning is not supported by this display bridge yet");
}
static void pong(struct wl_client *c, struct wl_resource *r, uint32_t serial) { }
static const struct xdg_wm_base_interface shell_impl = { .destroy = destroy_request, .create_positioner = positioner, .get_xdg_surface = get_xdg, .pong = pong };
static void bind_shell(struct wl_client *client, void *data, uint32_t version, uint32_t id) {
    struct wl_resource *resource = wl_resource_create(client, &xdg_wm_base_interface, 1, id);
    if (resource) wl_resource_set_implementation(resource, &shell_impl, data, NULL);
    else wl_client_post_no_memory(client);
}
static const struct wl_output_interface output_impl = { .release = destroy_request };
static void output_destroyed(struct wl_resource *resource) { wl_list_remove(wl_resource_get_link(resource)); }
static void bind_output(struct wl_client *client, void *data, uint32_t version, uint32_t id) {
    struct deck_display *display = data;
    struct wl_resource *resource = wl_resource_create(client, &wl_output_interface, version, id);
    if (!resource) { wl_client_post_no_memory(client); return; }
    wl_list_insert(display->outputs.prev, wl_resource_get_link(resource));
    wl_resource_set_implementation(resource, &output_impl, display, output_destroyed);
    wl_output_send_geometry(resource, 0, 0, 0, 0, WL_OUTPUT_SUBPIXEL_UNKNOWN, "Android", "Android Steam", WL_OUTPUT_TRANSFORM_NORMAL);
    wl_output_send_mode(resource, WL_OUTPUT_MODE_CURRENT | WL_OUTPUT_MODE_PREFERRED, display->width, display->height, display->refresh);
    if (version >= 2) { wl_output_send_scale(resource, 1); wl_output_send_done(resource); }
}
bool deck_register_shell(struct deck_display *display) {
    return wl_global_create(display->wayland, &xdg_wm_base_interface, 1, display, bind_shell) &&
        wl_global_create(display->wayland, &wl_output_interface, 3, display, bind_output);
}
