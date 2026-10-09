#import <Cocoa/Cocoa.h>
#include <SDL.h>
#include <SDL_syswm.h>
#include <stdatomic.h>
#include <stdio.h>
#include <math.h>
#include "mac_shell.h"
#include "mac_resize.h"

static NSWindow *tankWindow;
static NSMenuItem *floatItem;
static atomic_bool quitRequested;
static bool smokeMode;
static NSAutoreleasePool *appPool;
static NSButton *infoButton, *floatingCheckbox;
static NSButton *actionButtons[4];
static NSPanel *helpPanel;
static NSScrollView *helpScroll;
static NSButton *opaqueButton, *closeHelpButton;
static bool themeSystem, testLight, testDark, testResize, testCloseReopen;
static int themeStage;
static NSSlider *transparencySlider;
static NSTextField *transparencyLabel;
static unsigned blockedUntil;
static int actions[32], actionRead, actionWrite;
static unsigned deliveredMask;
static bool testHelp, testBlocked, testFloat, testAlpha, testCapture;
static int testStage;
static bool escapeHeld, testEscape;

@interface PocketTankHelpView : NSView
@end
@implementation PocketTankHelpView
- (BOOL)isFlipped { return YES; }
- (void)drawRect:(NSRect)dirtyRect { [[NSColor windowBackgroundColor] setFill]; NSRectFill(dirtyRect); }
- (void)viewDidChangeEffectiveAppearance { [super viewDidChangeEffectiveAppearance]; [self setNeedsDisplay:YES]; }
@end
static NSTextField *label(NSString *text, NSRect rect, CGFloat size) {
    NSTextField *field = [NSTextField labelWithString:text];
    [field setTextColor:[NSColor labelColor]]; [field setFrame:rect]; [field setFont:[NSFont systemFontOfSize:size]];
    return field;
}

@interface PocketTankController : NSObject <NSApplicationDelegate, NSWindowDelegate>
- (void)quit:(id)sender;
- (void)showTank:(id)sender;
- (void)hideTank:(id)sender;
- (void)toggleFloating:(id)sender;
- (void)showHelp:(id)sender;
- (void)closeHelp:(id)sender;
- (void)careAction:(id)sender;
- (void)setTransparency:(id)sender;
- (void)resetTransparency:(id)sender;
@end
@implementation PocketTankController
- (void)quit:(id)sender { (void)sender; fprintf(stderr, "Pocket Tank quit request: native menu\n"); mac_shell_request_quit(); }
- (NSApplicationTerminateReply)applicationShouldTerminate:(NSApplication *)sender {
    (void)sender; fprintf(stderr, "Pocket Tank quit request: native termination\n"); mac_shell_request_quit(); return NSTerminateCancel;
}
- (BOOL)applicationShouldHandleReopen:(NSApplication *)sender hasVisibleWindows:(BOOL)visible {
    (void)sender; (void)visible; [self showTank:nil]; return YES;
}
- (void)showTank:(id)sender { (void)sender; [NSApp unhide:nil]; [tankWindow makeKeyAndOrderFront:nil]; [NSApp activateIgnoringOtherApps:YES]; }
- (void)hideTank:(id)sender { (void)sender; [NSApp hide:nil]; }
- (void)toggleFloating:(id)sender {
    (void)sender;
    [tankWindow setLevel:mac_shell_floating() ? NSNormalWindowLevel : NSFloatingWindowLevel];
    [floatItem setState:mac_shell_floating() ? NSControlStateValueOn : NSControlStateValueOff];
    [floatingCheckbox setState:mac_shell_floating() ? NSControlStateValueOn : NSControlStateValueOff];
}
- (void)showHelp:(id)sender {
    (void)sender;
    if ([helpPanel isVisible]) [self closeHelp:nil];
    else {
        [NSApp unhide:nil];
        NSRect tankFrame=[tankWindow frame]; NSRect visible=[[tankWindow screen] visibleFrame]; NSRect frame=[helpPanel frame];
        frame.origin.x=MIN(NSMaxX(tankFrame)+12,NSMaxX(visible)-NSWidth(frame));
        frame.origin.x=MAX(NSMinX(visible),frame.origin.x);
        frame.origin.y=MAX(NSMinY(visible),MIN(NSMaxY(tankFrame)-NSHeight(frame),NSMaxY(visible)-NSHeight(frame)));
        [helpPanel setFrame:frame display:NO]; [helpPanel setLevel:[tankWindow level]];
        [helpPanel makeKeyAndOrderFront:nil];
    }
    blockedUntil=SDL_GetTicks()+250;
}
- (void)closeHelp:(id)sender { (void)sender; [helpPanel orderOut:nil]; blockedUntil=SDL_GetTicks()+250; }
- (BOOL)windowShouldClose:(NSWindow *)window { if(window==helpPanel) { [self closeHelp:nil]; return NO; } return YES; }
- (void)careAction:(id)sender {
    if (actionWrite-actionRead < 32) actions[actionWrite++ % 32] = (int)[sender tag];
    blockedUntil = SDL_GetTicks() + 250;
}
- (void)setTransparency:(id)sender {
    (void)sender;
    double value = round([transparencySlider doubleValue]);
    [transparencySlider setDoubleValue:value];
    [tankWindow setAlphaValue:1.0-value/100.0];
    [transparencyLabel setStringValue:[NSString stringWithFormat:@"Transparency: %.0f%%", value]];
    if (!smokeMode) [[NSUserDefaults standardUserDefaults] setDouble:value forKey:@"PocketTankTransparency"];
}
- (void)resetTransparency:(id)sender {
    (void)sender; [transparencySlider setDoubleValue:0]; [self setTransparency:nil];
}
@end
static PocketTankController *controller;

static int filterEvents(void *userdata, SDL_Event *event) {
    (void)userdata;
    if (event->type == SDL_QUIT || (event->type == SDL_WINDOWEVENT && event->window.event == SDL_WINDOWEVENT_CLOSE)) {
        fprintf(stderr, "Pocket Tank quit request: SDL event %u\n", event->type);
        mac_shell_request_quit(); return 0;
    }
    if (event->type == SDL_KEYUP && event->key.keysym.sym == SDLK_ESCAPE && escapeHeld) { escapeHeld=false; blockedUntil=SDL_GetTicks()+250; return 0; }
    if (event->type == SDL_KEYDOWN && event->key.keysym.sym == SDLK_ESCAPE && ([helpPanel isVisible] || escapeHeld)) {
        escapeHeld=true; [helpPanel orderOut:nil]; blockedUntil = SDL_GetTicks()+250; return 0;
    }
    if (!mac_resize_filter_event(event)) return 0;
    return 1;
}
void mac_shell_prepare(const char *smoke_dir) {
    appPool = [[NSAutoreleasePool alloc] init];
    smokeMode = smoke_dir != NULL;
    if (!getenv("POCKET_TANK_SAVE")) {
        NSString *directory = smoke_dir ? [NSString stringWithUTF8String:smoke_dir] :
            [[NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES) firstObject] stringByAppendingPathComponent:@"Pocket Tank"];
        [[NSFileManager defaultManager] createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:nil];
        setenv("POCKET_TANK_SAVE", [[directory stringByAppendingPathComponent:@"tank.sav"] fileSystemRepresentation], 1);
    }
}
const char *mac_shell_resource(const char *relative, const char *fallback) {
    NSString *path = [[[NSBundle mainBundle] resourcePath] stringByAppendingPathComponent:[NSString stringWithUTF8String:relative]];
    /* A damaged app must not silently mix bundled and working-directory
     * resources. Relative paths remain useful for the standalone simulator. */
    if ([[[[NSBundle mainBundle] bundlePath] pathExtension] isEqualToString:@"app"] ||
        [[NSFileManager defaultManager] fileExistsAtPath:path]) return [path fileSystemRepresentation];
    return fallback;
}
bool mac_shell_attach(void *renderer) {
    SDL_Window *window = SDL_RenderGetWindow((SDL_Renderer *)renderer);
    if (!window) return false;
    SDL_SysWMinfo info; SDL_VERSION(&info.version);
    if (!SDL_GetWindowWMInfo(window, &info) || info.subsystem != SDL_SYSWM_COCOA) return false;
    tankWindow = info.info.cocoa.window;
    [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
    [tankWindow setTitle:@"Pocket Tank"];
    [tankWindow setStyleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskMiniaturizable];
    [tankWindow setLevel:NSFloatingWindowLevel];
    [tankWindow setHidesOnDeactivate:NO];
    [tankWindow setCollectionBehavior:NSWindowCollectionBehaviorCanJoinAllSpaces | NSWindowCollectionBehaviorFullScreenAuxiliary];
    if (!smokeMode) [tankWindow setFrameUsingName:@"PocketTankWindow"];
    NSRect frame = [tankWindow frame];
    NSScreen *target = nil;
    for (NSScreen *screen in [NSScreen screens]) if (NSIntersectsRect(frame, [screen visibleFrame])) { target = screen; break; }
    if (!target) { target = [NSScreen mainScreen]; [tankWindow center]; frame = [tankWindow frame]; }
    NSRect visible = [target visibleFrame];
    frame.origin.x = MAX(NSMinX(visible), MIN(frame.origin.x, NSMaxX(visible) - frame.size.width));
    frame.origin.y = MAX(NSMinY(visible), MIN(frame.origin.y, NSMaxY(visible) - frame.size.height));
    [tankWindow setFrame:frame display:YES];
    controller = [[PocketTankController alloc] init];
    [NSApp setDelegate:controller];
    NSMenu *bar = [[NSMenu alloc] initWithTitle:@""];
    NSMenuItem *appItem = [[NSMenuItem alloc] initWithTitle:@"Pocket Tank" action:nil keyEquivalent:@""];
    NSMenu *appMenu = [[NSMenu alloc] initWithTitle:@"Pocket Tank"];
    NSMenuItem *hide = [appMenu addItemWithTitle:@"Hide Pocket Tank" action:@selector(hideTank:) keyEquivalent:@"h"]; [hide setTarget:controller];
    [appMenu addItem:[NSMenuItem separatorItem]];
    NSMenuItem *quit = [appMenu addItemWithTitle:@"Quit Pocket Tank" action:@selector(quit:) keyEquivalent:@"q"]; [quit setTarget:controller];
    [appItem setSubmenu:appMenu]; [bar addItem:appItem];
    NSMenuItem *windowItem = [[NSMenuItem alloc] initWithTitle:@"Window" action:nil keyEquivalent:@""];
    NSMenu *windowMenu = [[NSMenu alloc] initWithTitle:@"Window"];
    NSMenuItem *show = [windowMenu addItemWithTitle:@"Show Tank" action:@selector(showTank:) keyEquivalent:@"1"]; [show setTarget:controller];
    NSMenuItem *closeInstructions=[windowMenu addItemWithTitle:@"Close Instructions" action:@selector(closeHelp:) keyEquivalent:@"w"]; [closeInstructions setTarget:controller];
    floatItem = [windowMenu addItemWithTitle:@"Float Above Other Windows" action:@selector(toggleFloating:) keyEquivalent:@""]; [floatItem setTarget:controller]; [floatItem setState:NSControlStateValueOn];
    [windowItem setSubmenu:windowMenu]; [bar addItem:windowItem]; [NSApp setMainMenu:bar];
    NSMenuItem *helpItem = [[NSMenuItem alloc] initWithTitle:@"Help" action:nil keyEquivalent:@""];
    NSMenu *helpMenu = [[NSMenu alloc] initWithTitle:@"Help"];
    NSMenuItem *instructions = [helpMenu addItemWithTitle:@"Instructions" action:@selector(showHelp:) keyEquivalent:@"?"]; [instructions setTarget:controller];
    [helpItem setSubmenu:helpMenu]; [bar addItem:helpItem];
    NSView *glass = [tankWindow contentView];
    infoButton = [NSButton buttonWithTitle:@"ⓘ" target:controller action:@selector(showHelp:)];
    [infoButton setFrame:NSMakeRect(NSWidth([glass bounds])-38, NSHeight([glass bounds])-38, 30, 30)];
    [infoButton setAutoresizingMask:NSViewMinXMargin | NSViewMinYMargin];
    [infoButton setBezelStyle:NSBezelStyleCircular]; [infoButton setFont:[NSFont systemFontOfSize:21 weight:NSFontWeightMedium]];
    [infoButton setToolTip:@"Instructions and controls"]; [infoButton setAccessibilityLabel:@"Instructions and controls"];
    [glass addSubview:infoButton positioned:NSWindowAbove relativeTo:nil];
    helpPanel=[[NSPanel alloc] initWithContentRect:NSMakeRect(0,0,410,650) styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskResizable backing:NSBackingStoreBuffered defer:NO];
    [helpPanel setTitle:@"Instructions"]; [helpPanel setReleasedWhenClosed:NO]; [helpPanel setDelegate:controller];
    [helpPanel setContentMinSize:NSMakeSize(380,500)]; [helpPanel setHidesOnDeactivate:NO];
    [helpPanel setAlphaValue:1.0];
    PocketTankHelpView *helpView=[[PocketTankHelpView alloc] initWithFrame:NSMakeRect(0,0,410,650)];
    [helpPanel setContentView:helpView];
    NSTextField *heading=label(@"Your pocket aquarium",NSZeroRect,18);
    helpScroll=[[NSScrollView alloc] initWithFrame:NSZeroRect]; [helpScroll setHasVerticalScroller:YES]; [helpScroll setBorderType:NSBezelBorder];
    NSTextView *text=[[NSTextView alloc] initWithFrame:NSMakeRect(0,0,370,900)];
    [text setEditable:NO]; [text setSelectable:YES]; [text setFont:[NSFont systemFontOfSize:13]];
    [text setTextColor:[NSColor labelColor]]; [text setBackgroundColor:[NSColor textBackgroundColor]];
    [text setTextContainerInset:NSMakeSize(10,10)];
    [text setString:@"CARE FOR YOUR FISH\n\nTap the water surface or press Feed to drop food. Click a fish to see its stats; click MORE on its card for milestones, settings, and upgrades. Click empty water to dismiss the card. Let hunger guide feeding.\n\nHold your finger (mouse) on the glass for 3 seconds: trusting fish may swim over. Drag across algae to wipe the glass. Swipe sideways through tall plants to trim them. The sponge and scissors tools let you focus on cleaning or pruning; click DONE to put a tool away. Drag down from near the top to feed.\n\nDouble-click the glass to switch the light in manual mode. Three quick clicks can startle your fish. Use the tank settings to choose automatic feeding, automatic lights-out, brightness, sound, and other care options. The tank keeps its progress when you quit and accounts for time away.\n\nNew fish arrive as your tank develops. Complete the welcome screens and choose your fish’s names and colors first; care buttons become available afterward. Click a fish’s name on the milestones page to rename it or sell it; at least two fish stay in the tank. Milestones show each fish’s progress; earned sand dollars unlock decorations in the shop.\n\nQUICK CONTROLS\n\nFeed drops food at the center. Light switches day/night. Milestones opens or closes progress. Sound cycles off, quiet, and normal.\n\nWINDOW\n\nDrag the title bar to move the tank. Float above other windows keeps it visible while you work. Transparency fades the whole tank from 0% to 80%; this instruction panel stays readable. Opaque restores full visibility. Transparency is remembered between launches.\n\nHide with ⌘H; show from the Dock or Window → Show Tank (⌘1). Open this panel from ⓘ or Help → Instructions (⌘?). Drag this panel’s title bar to move it, or resize its edges to make more room for the guide. The panel follows your Mac’s light or dark theme. Close with the red window button, Close, ⌘W, or Escape; your fish keep swimming. Quit with ⌘Q to save.\n\nKEYBOARD (when instructions are closed)\n\nF — feed at the mouse position\nN — toggle light\nA — restore automatic light\nH — handle the tank / keep it awake\nL — switch local AI and rule brain\nM — open or close milestones\nV — cycle sound volume\nU — show or hide tank overlays\n4 — open the decoration shop\nS — reopen the welcome/naming setup\nX — open reset confirmation\nQ or Escape — save and quit\n\nThe fish brain runs locally; it needs no account or network connection."];
    [text setMinSize:NSMakeSize(0,0)]; [text setMaxSize:NSMakeSize(CGFLOAT_MAX,CGFLOAT_MAX)];
    [text setVerticallyResizable:YES]; [text setHorizontallyResizable:NO]; [text setAutoresizingMask:NSViewWidthSizable];
    [[text textContainer] setContainerSize:NSMakeSize(350,CGFLOAT_MAX)]; [[text textContainer] setWidthTracksTextView:YES];
    [helpScroll setDocumentView:text];
    NSStackView *careRow=[[NSStackView alloc] initWithFrame:NSZeroRect]; [careRow setOrientation:NSUserInterfaceLayoutOrientationHorizontal]; [careRow setDistribution:NSStackViewDistributionFillEqually]; [careRow setSpacing:6];
    NSArray *titles=@[@"Feed",@"Light",@"Milestones",@"Sound"];
    for(int i=0;i<4;i++) { actionButtons[i]=[NSButton buttonWithTitle:titles[i] target:controller action:@selector(careAction:)]; [actionButtons[i] setBezelStyle:NSBezelStyleRounded]; [actionButtons[i] setTag:i+1]; [careRow addArrangedSubview:actionButtons[i]]; }
    floatingCheckbox=[NSButton checkboxWithTitle:@"Float above other windows" target:controller action:@selector(toggleFloating:)]; [floatingCheckbox setState:NSControlStateValueOn];
    transparencyLabel=label(@"Transparency: 0%",NSZeroRect,13);
    transparencySlider=[NSSlider sliderWithValue:0 minValue:0 maxValue:80 target:controller action:@selector(setTransparency:)]; [transparencySlider setContinuous:YES]; [transparencySlider setAccessibilityLabel:@"Tank transparency, zero to eighty percent"];
    opaqueButton=[NSButton buttonWithTitle:@"Opaque" target:controller action:@selector(resetTransparency:)]; [opaqueButton setBezelStyle:NSBezelStyleRounded];
    NSStackView *opacityRow=[[NSStackView alloc] initWithFrame:NSZeroRect]; [opacityRow setOrientation:NSUserInterfaceLayoutOrientationHorizontal]; [opacityRow setDistribution:NSStackViewDistributionFill]; [opacityRow setSpacing:10]; [opacityRow addArrangedSubview:transparencySlider]; [opacityRow addArrangedSubview:opaqueButton];
    [opaqueButton setContentHuggingPriority:NSLayoutPriorityRequired forOrientation:NSLayoutConstraintOrientationHorizontal];
    NSTextField *footer=label(@"Changes apply immediately. ⌘Q saves and quits.",NSZeroRect,11);
    closeHelpButton=[NSButton buttonWithTitle:@"Close" target:controller action:@selector(closeHelp:)]; [closeHelpButton setBezelStyle:NSBezelStyleRounded];
    NSArray *rows=@[heading,helpScroll,careRow,floatingCheckbox,transparencyLabel,opacityRow,footer,closeHelpButton];
    for(NSView *row in rows) { [row setTranslatesAutoresizingMaskIntoConstraints:NO]; [helpView addSubview:row]; }
    NSMutableArray *constraints=[NSMutableArray array];
    [constraints addObject:[heading.topAnchor constraintEqualToAnchor:helpView.topAnchor constant:18]];
    [constraints addObject:[heading.heightAnchor constraintEqualToConstant:24]];
    for(NSView *row in rows) {
        [constraints addObject:[row.leadingAnchor constraintEqualToAnchor:helpView.leadingAnchor constant:18]];
        if(row!=closeHelpButton) [constraints addObject:[row.trailingAnchor constraintEqualToAnchor:helpView.trailingAnchor constant:-18]];
    }
    [constraints addObject:[helpScroll.topAnchor constraintEqualToAnchor:heading.bottomAnchor constant:12]];
    [constraints addObject:[helpScroll.heightAnchor constraintGreaterThanOrEqualToConstant:110]];
    [constraints addObject:[careRow.topAnchor constraintEqualToAnchor:helpScroll.bottomAnchor constant:12]];
    [constraints addObject:[careRow.heightAnchor constraintEqualToConstant:30]];
    [constraints addObject:[floatingCheckbox.topAnchor constraintEqualToAnchor:careRow.bottomAnchor constant:12]];
    [constraints addObject:[floatingCheckbox.heightAnchor constraintEqualToConstant:24]];
    [constraints addObject:[transparencyLabel.topAnchor constraintEqualToAnchor:floatingCheckbox.bottomAnchor constant:12]];
    [constraints addObject:[transparencyLabel.heightAnchor constraintEqualToConstant:22]];
    [constraints addObject:[opacityRow.topAnchor constraintEqualToAnchor:transparencyLabel.bottomAnchor constant:4]];
    [constraints addObject:[opacityRow.heightAnchor constraintEqualToConstant:28]];
    [constraints addObject:[footer.topAnchor constraintEqualToAnchor:opacityRow.bottomAnchor constant:10]];
    [constraints addObject:[footer.heightAnchor constraintEqualToConstant:18]];
    [constraints addObject:[closeHelpButton.topAnchor constraintEqualToAnchor:footer.bottomAnchor constant:8]];
    [constraints addObject:[closeHelpButton.heightAnchor constraintEqualToConstant:30]];
    [constraints addObject:[closeHelpButton.widthAnchor constraintEqualToConstant:80]];
    [constraints addObject:[closeHelpButton.bottomAnchor constraintEqualToAnchor:helpView.bottomAnchor constant:-18]];
    [NSLayoutConstraint activateConstraints:constraints];
    themeSystem=[helpPanel appearance]==nil && [helpView appearance]==nil;
    if (!smokeMode) [transparencySlider setDoubleValue:MAX(0,MIN(80,[[NSUserDefaults standardUserDefaults] doubleForKey:@"PocketTankTransparency"]))];
    [controller setTransparency:nil];
    [NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskKeyDown | NSEventMaskKeyUp handler:^NSEvent *(NSEvent *event) {
        if ([event keyCode]==53) {
            if ([event type]==NSEventTypeKeyUp && escapeHeld) { escapeHeld=false; blockedUntil=SDL_GetTicks()+250; return nil; }
            if ([event type]==NSEventTypeKeyDown && ([helpPanel isVisible] || escapeHeld)) { escapeHeld=true; [helpPanel orderOut:nil]; blockedUntil=SDL_GetTicks()+250; return nil; }
        }
        return event;
    }];
    SDL_SetEventFilter(filterEvents, NULL);
    if (smokeMode) [tankWindow orderFront:nil];
    else { [tankWindow makeKeyAndOrderFront:nil]; [NSApp activateIgnoringOtherApps:YES]; }
    return true;
}
bool mac_shell_quit_requested(void) { return atomic_load(&quitRequested); }
void mac_shell_request_quit(void) { atomic_store(&quitRequested, true); }
bool mac_shell_save_failed(const char *save_path) {
    atomic_store(&quitRequested, false);
    if (smokeMode) return false;
    [tankWindow makeKeyAndOrderFront:nil];
    NSAlert *alert = [[[NSAlert alloc] init] autorelease];
    [alert setMessageText:@"Your aquarium could not be saved"];
    NSString *path = save_path ? [NSString stringWithUTF8String:save_path] : @"the save folder";
    [alert setInformativeText:[NSString stringWithFormat:@"Pocket Tank is staying open so your current fish and progress are kept. Check that the save folder is writable and there is free disk space, then retry.\n\n%@", path]];
    [alert setAlertStyle:NSAlertStyleWarning];
    [alert addButtonWithTitle:@"Retry Save"];
    [alert addButtonWithTitle:@"Keep Tank Open"];
    return [alert runModal] == NSAlertFirstButtonReturn;
}
bool mac_shell_floating(void) { return tankWindow && [tankWindow level] == NSFloatingWindowLevel; }
long mac_shell_window_level(void) { return tankWindow ? [tankWindow level] : 0; }
void mac_shell_model_missing(void) {
    NSAlert *alert = [[NSAlert alloc] init];
    [alert setMessageText:@"The fish brain could not load"];
    [alert setInformativeText:@"Pocket Tank will use its built-in rules. Reinstall the complete app to restore the local AI model."];
    [alert addButtonWithTitle:@"Continue"];
    [alert runModal]; [alert release];
}
void mac_shell_finish(void) {
    if (!smokeMode && tankWindow) { [tankWindow saveFrameUsingName:@"PocketTankWindow"]; [[NSUserDefaults standardUserDefaults] synchronize]; }
    (void)appPool; /* process-wide pool keeps resource C strings valid until exit */
}

int mac_shell_take_action(void) { return actionRead < actionWrite ? actions[actionRead++ % 32] : 0; }
bool mac_shell_input_focused(void) { return [NSApp isActive] && [tankWindow isKeyWindow]; }
bool mac_shell_input_blocked(void) {
    if (escapeHeld || [helpPanel isVisible] || (int32_t)(blockedUntil-SDL_GetTicks())>0) return true;
    NSPoint point = [tankWindow convertPointFromScreen:[NSEvent mouseLocation]];
    point = [[infoButton superview] convertPoint:point fromView:nil];
    return NSPointInRect(point,[infoButton frame]);
}
void mac_shell_controls_delivered(int action, bool applied) { if(applied && action>=1 && action<=4) deliveredMask |= 1u<<(action-1); }
void mac_shell_controls_tick(bool enabled, const char *directory, unsigned elapsed_ms) {
    if(!enabled || !tankWindow) return;
    if(testStage==0 && elapsed_ms>=300) {
        [infoButton performClick:nil]; testHelp=[helpPanel isVisible]; testBlocked=mac_shell_input_blocked();
        [floatingCheckbox performClick:nil]; bool normal=[tankWindow level]==NSNormalWindowLevel;
        [floatingCheckbox performClick:nil]; testFloat=normal && [tankWindow level]==NSFloatingWindowLevel;
        [transparencySlider setDoubleValue:45]; [transparencySlider sendAction:[transparencySlider action] to:[transparencySlider target]];
        bool changed=fabs([tankWindow alphaValue]-0.55)<0.001 && fabs([helpPanel alphaValue]-1.0)<0.001;
        [controller resetTransparency:nil]; testAlpha=changed && fabs([tankWindow alphaValue]-1.0)<0.001;
        for(int i=0;i<4;i++) [actionButtons[i] performClick:nil]; testStage=1;
    }
    if(testStage==1 && elapsed_ms>=1000) {
        if (![helpPanel isVisible]) [infoButton performClick:nil];
        NSView *view=[helpPanel contentView];
        [view displayIfNeeded]; NSBitmapImageRep *bitmap=[view bitmapImageRepForCachingDisplayInRect:[view bounds]];
        [view cacheDisplayInRect:[view bounds] toBitmapImageRep:bitmap];
        NSData *png=[bitmap representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
        NSString *path=[[NSString stringWithUTF8String:directory] stringByAppendingPathComponent:@"help-popover.png"];
        testCapture=[png writeToFile:path atomically:YES];
        SDL_Event escape={0}; escape.type=SDL_KEYDOWN; escape.key.keysym.sym=SDLK_ESCAPE; SDL_PushEvent(&escape);
        testEscape=![helpPanel isVisible] && mac_shell_input_blocked() && !mac_shell_quit_requested(); testStage=2;
    }
    if(testStage==2 && elapsed_ms>=1800) {
        testEscape=testEscape && mac_shell_input_blocked() && !mac_shell_quit_requested();
        SDL_Event release={0}; release.type=SDL_KEYUP; release.key.keysym.sym=SDLK_ESCAPE; SDL_PushEvent(&release); testStage=3;
    }
}
void mac_shell_controls_report(void *file) {
    fprintf((FILE *)file,"help_button=%d\nhelp_popover=%d\ncontrols=%d\ntransparency_checks=%d\ninput_blocked=%d\nescape_closes_help=%d\n",infoButton!=nil,testHelp && testCapture && ![helpPanel isVisible],deliveredMask==15,testFloat && testAlpha,testBlocked,testEscape);
    fprintf((FILE *)file,"theme_follows_system=%d\ntheme_light=%d\ntheme_dark=%d\nhelp_resizable=%d\nhelp_close_reopen=%d\n",themeSystem,testLight,testDark,testResize,testCloseReopen);
}

void mac_shell_close_help(void) { [controller closeHelp:nil]; }
void mac_shell_set_controls_enabled(bool enabled) { for(int i=0;i<4;i++) [actionButtons[i] setEnabled:enabled]; }

static bool captureHelp(const char *directory, NSString *name) {
    NSView *view=[helpPanel contentView]; [view layoutSubtreeIfNeeded]; [view display];
    NSBitmapImageRep *bitmap=[view bitmapImageRepForCachingDisplayInRect:[view bounds]];
    [view cacheDisplayInRect:[view bounds] toBitmapImageRep:bitmap];
    NSData *png=[bitmap representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
    return [png writeToFile:[[NSString stringWithUTF8String:directory] stringByAppendingPathComponent:name] atomically:YES];
}
static bool controlsFit(void) {
    NSView *view=[helpPanel contentView]; [view layoutSubtreeIfNeeded]; NSRect area=[view bounds];
    NSArray *controls=@[actionButtons[0],actionButtons[1],actionButtons[2],actionButtons[3],floatingCheckbox,transparencyLabel,transparencySlider,opaqueButton,closeHelpButton,helpScroll];
    for(NSView *control in controls) {
        NSRect rect=[control convertRect:[control bounds] toView:view];
        if(NSWidth(rect)<10 || NSHeight(rect)<10 || !NSContainsRect(area,rect)) return false;
    }
    return NSHeight([helpScroll frame])>=109;
}
static bool appearanceReadable(NSString *expected) {
    NSAppearance *appearance=[helpPanel effectiveAppearance];
    NSString *match=[appearance bestMatchFromAppearancesWithNames:@[NSAppearanceNameAqua,NSAppearanceNameDarkAqua]];
    __block bool contrast=false;
    [appearance performAsCurrentDrawingAppearance:^{
        NSColor *foreground=[[NSColor labelColor] colorUsingColorSpace:[NSColorSpace sRGBColorSpace]];
        NSColor *background=[[NSColor windowBackgroundColor] colorUsingColorSpace:[NSColorSpace sRGBColorSpace]];
        if(foreground && background) {
            double fg=(foreground.redComponent+foreground.greenComponent+foreground.blueComponent)/3;
            double bg=(background.redComponent+background.greenComponent+background.blueComponent)/3;
            contrast=fabs(fg-bg)>0.45;
        }
    }];
    return [match isEqualToString:expected] && contrast;
}
void mac_shell_theme_resize_tick(bool enabled, const char *directory, unsigned elapsed_ms) {
    if(!enabled || !smokeMode || !tankWindow) return;
    if(themeStage==0 && elapsed_ms>=2100) {
        if(![helpPanel isVisible]) [infoButton performClick:nil];
        [helpPanel setAppearance:[NSAppearance appearanceNamed:NSAppearanceNameAqua]];
        [helpPanel setContentSize:NSMakeSize(410,650)]; [[helpPanel contentView] layoutSubtreeIfNeeded];
        testLight=appearanceReadable(NSAppearanceNameAqua) && controlsFit() && captureHelp(directory,@"help-light.png"); themeStage=1;
    }
    if(themeStage==1 && elapsed_ms>=2600) {
        [helpPanel setAppearance:[NSAppearance appearanceNamed:NSAppearanceNameDarkAqua]];
        testDark=appearanceReadable(NSAppearanceNameDarkAqua) && controlsFit() && captureHelp(directory,@"help-dark.png");
        CGFloat original=NSHeight([helpScroll frame]);
        [helpPanel setContentSize:NSMakeSize(570,790)]; [[helpPanel contentView] layoutSubtreeIfNeeded];
        bool larger=controlsFit() && NSHeight([helpScroll frame])>original+100;
        [helpPanel setContentSize:NSMakeSize(380,500)]; [[helpPanel contentView] layoutSubtreeIfNeeded];
        testResize=larger && controlsFit() && ([helpPanel styleMask]&NSWindowStyleMaskResizable);
        captureHelp(directory,@"help-minimum.png");
        [helpPanel setAppearance:nil]; themeStage=2;
    }
    if(themeStage==2 && elapsed_ms>=3200) {
        [[helpPanel standardWindowButton:NSWindowCloseButton] performClick:nil];
        bool closed=![helpPanel isVisible] && !mac_shell_quit_requested() && [tankWindow isVisible];
        [infoButton performClick:nil]; testCloseReopen=closed && [helpPanel isVisible];
        [closeHelpButton performClick:nil]; testCloseReopen=testCloseReopen && ![helpPanel isVisible] && !mac_shell_quit_requested(); themeStage=3;
    }
}
