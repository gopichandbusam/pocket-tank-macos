#ifndef POCKET_TANK_MAC_SHELL_H
#define POCKET_TANK_MAC_SHELL_H
#include <stdbool.h>
enum { MAC_ACTION_FEED=1, MAC_ACTION_LIGHT=2, MAC_ACTION_MILESTONES=3, MAC_ACTION_SOUND=4 };
#ifdef __APPLE__
void mac_shell_close_help(void);
void mac_shell_set_controls_enabled(bool enabled);
int mac_shell_take_action(void);
bool mac_shell_input_blocked(void);
bool mac_shell_input_focused(void);
void mac_shell_theme_resize_tick(bool enabled, const char *directory, unsigned elapsed_ms);
void mac_shell_controls_tick(bool enabled, const char *directory, unsigned elapsed_ms);
void mac_shell_controls_delivered(int action, bool applied);
void mac_shell_controls_report(void *file);
void mac_shell_prepare(const char *smoke_dir);
const char *mac_shell_resource(const char *relative, const char *fallback);
bool mac_shell_attach(void *renderer);
bool mac_shell_quit_requested(void);
void mac_shell_request_quit(void);
bool mac_shell_save_failed(const char *save_path);
void mac_shell_finish(void);
bool mac_shell_floating(void);
long mac_shell_window_level(void);
void mac_shell_model_missing(void);
#else
static inline void mac_shell_close_help(void) {}
static inline void mac_shell_set_controls_enabled(bool e) { (void)e; }
static inline int mac_shell_take_action(void) { return 0; }
static inline bool mac_shell_input_blocked(void) { return false; }
static inline bool mac_shell_input_focused(void) { return true; }
static inline void mac_shell_theme_resize_tick(bool e, const char *d, unsigned m) { (void)e; (void)d; (void)m; }
static inline void mac_shell_controls_tick(bool e, const char *d, unsigned m) { (void)e; (void)d; (void)m; }
static inline void mac_shell_controls_delivered(int a, bool applied) { (void)a; (void)applied; }
static inline void mac_shell_controls_report(void *f) { (void)f; }
static inline void mac_shell_prepare(const char *d) { (void)d; }
static inline const char *mac_shell_resource(const char *r, const char *f) { (void)r; return f; }
static inline bool mac_shell_attach(void *r) { (void)r; return false; }
static inline bool mac_shell_quit_requested(void) { return false; }
static inline void mac_shell_request_quit(void) {}
static inline bool mac_shell_save_failed(const char *p) { (void)p; return false; }
static inline void mac_shell_finish(void) {}
static inline bool mac_shell_floating(void) { return false; }
static inline long mac_shell_window_level(void) { return 0; }
static inline void mac_shell_model_missing(void) {}
#endif
#endif
