#ifndef ANDROIDSTEAM_INPUT_H
#define ANDROIDSTEAM_INPUT_H
#include <stdbool.h>
struct deck_display;
struct deck_surface;
struct deck_input;
// Normalized positions are relative to the Android view displaying the frame.
enum deck_input_type { DECK_POINTER, DECK_SCROLL, DECK_KEY, DECK_TOUCH, DECK_RESET };
struct deck_input_event { int type, code, action; float x, y; };
bool deck_input_start(struct deck_display *display);
void deck_input_stop(struct deck_display *display);
bool deck_input_enqueue(struct deck_display *display, struct deck_input_event event);
void deck_input_focus(struct deck_surface *surface);
void deck_input_surface_gone(struct deck_surface *surface);
#endif
