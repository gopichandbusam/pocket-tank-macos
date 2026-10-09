#import <Cocoa/Cocoa.h>
#import <SDL2/SDL.h>
#import <SDL2/SDL_syswm.h>
#include <stdatomic.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "tank.h"
#include "mac_resize.h"

static SDL_Window *resizeWindow;
static SDL_Renderer *resizeRenderer;
static NSWindow *nativeWindow;
static atomic_bool geometryDirty = ATOMIC_VAR_INIT(false);
static int lastWindowWidth;
static int lastWindowHeight;
static id<NSWindowDelegate> resizeForwardDelegate;

@interface PocketTankResizeDelegate : NSObject <NSWindowDelegate>
- (id)initWithForwardDelegate:(id)delegate;
@end
@implementation PocketTankResizeDelegate
- (id)initWithForwardDelegate:(id)delegate {
    self = [super init];
    if (self) resizeForwardDelegate = delegate;
    return self;
}
- (NSSize)windowWillResize:(NSWindow *)window toSize:(NSSize)frameSize {
    if ([resizeForwardDelegate respondsToSelector:@selector(windowWillResize:toSize:)])
        frameSize = [resizeForwardDelegate windowWillResize:window toSize:frameSize];
    NSRect proposedFrame = NSMakeRect(0, 0, frameSize.width, frameSize.height);
    NSSize proposedContent = [window contentRectForFrameRect:proposedFrame].size;
    NSSize currentContent = [[window contentView] frame].size;
    CGFloat aspect = (CGFloat)TANK_W / (CGFloat)TANK_H;
    CGFloat widthChange = fabs(proposedContent.width - currentContent.width);
    CGFloat heightChange = fabs(proposedContent.height - currentContent.height);
    if (widthChange >= heightChange * aspect) proposedContent.height = proposedContent.width / aspect;
    else proposedContent.width = proposedContent.height * aspect;
    NSRect fitted = [window frameRectForContentRect:NSMakeRect(0, 0, proposedContent.width, proposedContent.height)];
    return fitted.size;
}
- (BOOL)windowShouldClose:(NSWindow *)window {
    if ([resizeForwardDelegate respondsToSelector:@selector(windowShouldClose:)])
        return [resizeForwardDelegate windowShouldClose:window];
    return YES;
}
- (BOOL)respondsToSelector:(SEL)selector {
    return [super respondsToSelector:selector] || [resizeForwardDelegate respondsToSelector:selector];
}
- (id)forwardingTargetForSelector:(SEL)selector {
    if ([resizeForwardDelegate respondsToSelector:selector]) return resizeForwardDelegate;
    return [super forwardingTargetForSelector:selector];
}
- (NSMethodSignature *)methodSignatureForSelector:(SEL)selector {
    NSMethodSignature *signature = [super methodSignatureForSelector:selector];
    return signature ?: [(NSObject *)resizeForwardDelegate methodSignatureForSelector:selector];
}
- (void)forwardInvocation:(NSInvocation *)invocation {
    if ([resizeForwardDelegate respondsToSelector:[invocation selector]]) [invocation invokeWithTarget:resizeForwardDelegate];
    else [super forwardInvocation:invocation];
}
@end
static PocketTankResizeDelegate *resizeDelegate;

bool mac_resize_attach(void *rendererPointer) {
    resizeRenderer = (SDL_Renderer *)rendererPointer;
    if (!resizeRenderer) return false;
    resizeWindow = SDL_RenderGetWindow(resizeRenderer);
    if (!resizeWindow) return false;

    SDL_SysWMinfo info;
    SDL_VERSION(&info.version);
    if (!SDL_GetWindowWMInfo(resizeWindow, &info) || info.subsystem != SDL_SYSWM_COCOA) return false;
    nativeWindow = info.info.cocoa.window;
    resizeForwardDelegate = [nativeWindow delegate];
    resizeDelegate = [[PocketTankResizeDelegate alloc] initWithForwardDelegate:resizeForwardDelegate];
    [nativeWindow setDelegate:resizeDelegate];
    [nativeWindow setStyleMask:[nativeWindow styleMask] | NSWindowStyleMaskResizable];
    [nativeWindow setContentMinSize:NSMakeSize(280, 230)];
    [nativeWindow setContentAspectRatio:NSMakeSize(TANK_W, TANK_H)];

    SDL_SetWindowResizable(resizeWindow, SDL_TRUE);
    SDL_SetWindowMinimumSize(resizeWindow, 280, 230);
    if (SDL_RenderSetLogicalSize(resizeRenderer, TANK_W, TANK_H) != 0) return false;
    SDL_RenderSetIntegerScale(resizeRenderer, SDL_FALSE);
    SDL_GetWindowSize(resizeWindow, &lastWindowWidth, &lastWindowHeight);
    atomic_store_explicit(&geometryDirty, true, memory_order_release);
    return true;
}

/* Called by SDL's event filter, which may run off the main thread. This path
 * only rejects resize notifications and sets an atomic flag; all renderer and
 * AppKit access stays on the simulator's main thread. */
bool mac_resize_filter_event(SDL_Event *event) {
    if (!event || event->type != SDL_WINDOWEVENT) return true;
    if (event->window.event == SDL_WINDOWEVENT_SIZE_CHANGED ||
        event->window.event == SDL_WINDOWEVENT_RESIZED) {
        atomic_store_explicit(&geometryDirty, true, memory_order_release);
        return false;
    }
    return true;
}

void mac_resize_update(void) {
    if (!resizeWindow || !resizeRenderer) return;
    int width = 0, height = 0;
    SDL_GetWindowSize(resizeWindow, &width, &height);
    bool dirty = atomic_exchange_explicit(&geometryDirty, false, memory_order_acq_rel);
    if (dirty || width != lastWindowWidth || height != lastWindowHeight) {
        /* LVGL's SDL monitor treats RESIZED as a logical display-size change.
         * Reassert the fixed world size after native geometry has settled. */
        SDL_RenderSetLogicalSize(resizeRenderer, TANK_W, TANK_H);
        SDL_RenderSetIntegerScale(resizeRenderer, SDL_FALSE);
        lastWindowWidth = width;
        lastWindowHeight = height;
    }
}

void mac_resize_map_mouse(int windowX, int windowY, int *worldX, int *worldY) {
    float logicalX = (float)windowX;
    float logicalY = (float)windowY;
    if (resizeRenderer) SDL_RenderWindowToLogical(resizeRenderer, windowX, windowY, &logicalX, &logicalY);
    int x = (int)(logicalX + 0.5f);
    int y = (int)(logicalY + 0.5f);
    if (x < 0) x = 0;
    if (x >= TANK_W) x = TANK_W - 1;
    if (y < 0) y = 0;
    if (y >= TANK_H) y = TANK_H - 1;
    if (worldX) *worldX = x;
    if (worldY) *worldY = y;
}

typedef struct {
    bool initialized;
    bool failed;
    unsigned phase;
    unsigned due_ms;
    unsigned verify_ms;
    int original_width;
    int original_height;
    int target_width;
    int target_height;
    bool close_invoked;
    FILE *report;
} resize_test_state_t;
static resize_test_state_t resizeTest;

static void resize_test_open(const char *directory) {
    if (resizeTest.initialized) return;
    resizeTest.initialized = true;
    if (!directory || !*directory) return;
    char path[1024];
    snprintf(path, sizeof path, "%s/resize-report.txt", directory);
    resizeTest.report = fopen(path, "w");
    if (resizeTest.report) {
        fprintf(resizeTest.report, "Pocket Tank native resize smoke\nworld=%dx%d\n", TANK_W, TANK_H);
        fflush(resizeTest.report);
    }
}

static void resize_test_log(const char *line) {
    if (!resizeTest.report) return;
    fprintf(resizeTest.report, "%s\n", line);
    fflush(resizeTest.report);
}

static bool resize_test_metrics(const char *name, int expectedWidth, int expectedHeight) {
    int width = 0, height = 0, logicalWidth = 0, logicalHeight = 0;
    SDL_GetWindowSize(resizeWindow, &width, &height);
    SDL_RenderGetLogicalSize(resizeRenderer, &logicalWidth, &logicalHeight);
    int x0, y0, xq, yq, xc, yc, x1, y1;
    mac_resize_map_mouse(0, 0, &x0, &y0);
    mac_resize_map_mouse(width / 4, height / 4, &xq, &yq);
    mac_resize_map_mouse(width / 2, height / 2, &xc, &yc);
    mac_resize_map_mouse(width - 1, height - 1, &x1, &y1);
    bool sizeOk = abs(width - expectedWidth) <= 2 && (expectedHeight <= 0 || abs(height - expectedHeight) <= 2);
    bool aspectOk = abs(width * TANK_H - height * TANK_W) <= 2 * TANK_W;
    bool logicalOk = logicalWidth == TANK_W && logicalHeight == TANK_H;
    bool quarterOk = abs(xq - TANK_W / 4) <= 3 && abs(yq - TANK_H / 4) <= 3;
    bool centerOk = abs(xc - TANK_W / 2) <= 2 && abs(yc - TANK_H / 2) <= 2;
    bool cornersOk = x0 <= 2 && y0 <= 2 && x1 >= TANK_W - 3 && y1 >= TANK_H - 3;
    bool ok = sizeOk && aspectOk && logicalOk && quarterOk && centerOk && cornersOk;
    char line[512];
    snprintf(line, sizeof line,
             "%s window=%dx%d target=%dx%d logical=%dx%d quarter=%d,%d center=%d,%d corners=%d,%d..%d,%d aspect=%s checks=%s",
             name, width, height, expectedWidth, expectedHeight, logicalWidth, logicalHeight,
             xq, yq, xc, yc, x0, y0, x1, y1, aspectOk ? "PASS" : "FAIL", ok ? "PASS" : "FAIL");
    resize_test_log(line);
    if (!ok) resizeTest.failed = true;
    return ok;
}

void mac_resize_test_tick(bool enabled, const char *directory, unsigned elapsed_ms) {
    if (!enabled || !resizeWindow || !resizeRenderer) return;
    resize_test_open(directory);
    if (resizeTest.phase == 5) {
        if (!resizeTest.close_invoked && elapsed_ms >= 6500) {
            resizeTest.close_invoked = true;
            resize_test_log("native_close_invoked=1");
            if (resizeTest.report) { fclose(resizeTest.report); resizeTest.report = NULL; }
            [nativeWindow performClose:nil];
        }
        return;
    }
    if (resizeTest.phase == 0 && resizeTest.due_ms == 0) {
        SDL_GetWindowSize(resizeWindow, &resizeTest.original_width, &resizeTest.original_height);
        resizeTest.due_ms = 4000;
    }
    if (resizeTest.verify_ms && elapsed_ms >= resizeTest.verify_ms) {
        resize_test_metrics("resize", resizeTest.target_width, resizeTest.target_height);
        resizeTest.verify_ms = 0;
        resizeTest.phase++;
        resizeTest.due_ms = elapsed_ms + 250;
    }
    if (resizeTest.verify_ms || elapsed_ms < resizeTest.due_ms) return;
    switch (resizeTest.phase) {
    case 0: resizeTest.target_width = 560; resizeTest.target_height = 460; break;
    case 1: resizeTest.target_width = 840; resizeTest.target_height = 690; break;
    case 2: resizeTest.target_width = 336; resizeTest.target_height = 276; break;
    case 3: resizeTest.target_width = resizeTest.original_width; resizeTest.target_height = resizeTest.original_height; break;
    default:
        resize_test_log(resizeTest.failed ? "result=FAIL" : "result=PASS");
        resizeTest.phase = 5;
        return;
    }
    SDL_SetWindowSize(resizeWindow, resizeTest.target_width, resizeTest.target_height);
    SDL_PumpEvents();
    mac_resize_update();
    resizeTest.verify_ms = elapsed_ms + 300;
}

bool mac_resize_test_ok(void) {
    return resizeTest.phase == 5 && !resizeTest.failed;
}
