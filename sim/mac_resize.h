#ifndef POCKET_TANK_MAC_RESIZE_H
#define POCKET_TANK_MAC_RESIZE_H

#include <stdbool.h>
#include <SDL2/SDL.h>

#ifdef __APPLE__
bool mac_resize_attach(void *renderer);
void mac_resize_update(void);
bool mac_resize_filter_event(SDL_Event *event);
void mac_resize_map_mouse(int window_x, int window_y, int *world_x, int *world_y);
void mac_resize_test_tick(bool enabled, const char *directory, unsigned elapsed_ms);
bool mac_resize_test_ok(void);
#else
static inline bool mac_resize_attach(void *renderer) { (void)renderer; return false; }
static inline void mac_resize_update(void) {}
static inline bool mac_resize_filter_event(SDL_Event *event) { (void)event; return true; }
static inline void mac_resize_map_mouse(int x, int y, int *world_x, int *world_y) {
    if (world_x) *world_x = x;
    if (world_y) *world_y = y;
}
static inline void mac_resize_test_tick(bool enabled, const char *directory, unsigned elapsed_ms) {
    (void)enabled; (void)directory; (void)elapsed_ms;
}
static inline bool mac_resize_test_ok(void) { return true; }
#endif

#endif
