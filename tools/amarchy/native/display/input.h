#ifndef AMARCHY_INPUT_H
#define AMARCHY_INPUT_H
#include <stdbool.h>
struct amarchy_display;
struct amarchy_surface;
struct amarchy_input;
// Normalized positions are relative to the Android view displaying the frame.
enum amarchy_input_type { AMARCHY_POINTER, AMARCHY_SCROLL, AMARCHY_KEY, AMARCHY_TOUCH, AMARCHY_RESET };
struct amarchy_input_event { int type, code, action; float x, y; };
bool amarchy_input_start(struct amarchy_display *display);
void amarchy_input_stop(struct amarchy_display *display);
bool amarchy_input_enqueue(struct amarchy_display *display, struct amarchy_input_event event);
void amarchy_input_focus(struct amarchy_surface *surface);
void amarchy_input_surface_gone(struct amarchy_surface *surface);
#endif
