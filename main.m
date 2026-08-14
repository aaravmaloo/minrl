#import <ApplicationServices/ApplicationServices.h>
#import <Cocoa/Cocoa.h>
#import <CoreGraphics/CoreGraphics.h>
#import <stdio.h>
#import <stdlib.h>
#import <unistd.h>

// Virtual keycodes (see Carbon's HIToolbox/Events.h).
enum {
    kVK_Tab          = 48,
    kVK_Escape       = 53,
    kVK_Command      = 55,
    kVK_RightCommand = 54,
};

static CFMachPortRef gTap = NULL;
static bool gCmdTabActive = false; // a Cmd+Tab switch is in progress
static bool gDebug = false;
static pid_t gBeforePid = -1; // frontmost app when the switch started
static int gPollCount = 0;    // ticks since the switch committed
static NSStatusItem *gStatusItem = nil;
static NSMenuItem *gStatusLabel = nil;

#pragma mark - Restoring minimized windows (Accessibility)

// Unminimize every minimized window of the given app. Returns how many
// windows were restored.
static int UnminimizeWindowsOfApp(pid_t pid) {
    int restored = 0;
    AXUIElementRef app = AXUIElementCreateApplication(pid);
    CFArrayRef windows = NULL;
    AXError err = AXUIElementCopyAttributeValue(app, kAXWindowsAttribute,
                                                (CFTypeRef *)&windows);
    if (err == kAXErrorSuccess && windows != NULL) {
        CFIndex count = CFArrayGetCount(windows);
        for (CFIndex i = 0; i < count; i++) {
            AXUIElementRef win =
                (AXUIElementRef)CFArrayGetValueAtIndex(windows, i);
            CFTypeRef minimized = NULL;
            if (AXUIElementCopyAttributeValue(win, kAXMinimizedAttribute,
                                              &minimized) == kAXErrorSuccess &&
                minimized != NULL &&
                CFGetTypeID(minimized) == CFBooleanGetTypeID() &&
                CFBooleanGetValue((CFBooleanRef)minimized)) {
                if (AXUIElementSetAttributeValue(win, kAXMinimizedAttribute,
                                                 kCFBooleanFalse) ==
                    kAXErrorSuccess) {
                    restored++;
                }
            }
            if (minimized != NULL) {
                CFRelease(minimized);
            }
        }
        CFRelease(windows);
    }
    CFRelease(app);
    return restored;
}

// PID of the frontmost app. NSWorkspace is reliable; CGWindowList is a
// fallback (the topmost layer-0 window).
static pid_t FrontmostAppPid(void) {
    NSRunningApplication *front =
        [NSWorkspace sharedWorkspace].frontmostApplication;
    if (front != nil) {
        return (pid_t)front.processIdentifier;
    }
    CFArrayRef list = CGWindowListCopyWindowInfo(
        kCGWindowListOptionOnScreenOnly | kCGWindowListExcludeDesktopElements,
        kCGNullWindowID);
    pid_t pid = -1;
    if (list != NULL) {
        CFIndex n = CFArrayGetCount(list);
        for (CFIndex i = 0; i < n; i++) {
            CFDictionaryRef info = CFArrayGetValueAtIndex(list, i);
            CFNumberRef layerNum = CFDictionaryGetValue(info, kCGWindowLayer);
            int layer = -1;
            if (layerNum != NULL) {
                CFNumberGetValue(layerNum, kCFNumberIntType, &layer);
            }
            if (layer != 0) {
                continue;
            }
            CFNumberRef owner = CFDictionaryGetValue(info, kCGWindowOwnerPID);
            int p = 0;
            if (owner != NULL) {
                CFNumberGetValue(owner, kCFNumberIntType, &p);
            }
            if (p > 0) {
                pid = p;
                break;
            }
        }
        CFRelease(list);
    }
    return pid;
}

// Poll until the frontmost app changes (the switch target), or ~1.5s elapse,
// then restore the minimized windows of whatever app is frontmost.
static void PollRestore(CFRunLoopTimerRef timer, void *info) {
    (void)info;
    pid_t now = FrontmostAppPid();
    bool switched = now > 0 && now != gBeforePid;
    bool timedOut = gPollCount >= 10;
    gPollCount++;
    if (switched || timedOut) {
        CFRunLoopTimerInvalidate(timer);
        if (gDebug) {
            printf("[minrl] switch settled, frontmost pid=%d\n", now);
        }
        if (now > 0) {
            int n = UnminimizeWindowsOfApp(now);
            if (gDebug) {
                printf("[minrl] restored %d minimized window(s)\n", n);
            }
        }
    }
}

static void ScheduleRestore(void) {
    gPollCount = 0;
    gBeforePid = FrontmostAppPid();
    CFRunLoopTimerRef timer = CFRunLoopTimerCreate(
        kCFAllocatorDefault,
        CFAbsoluteTimeGetCurrent() + 0.15, // first check soon after Cmd-up
        0.15,                              // then every 150ms
        0, 0, PollRestore, NULL);
    CFRunLoopAddTimer(CFRunLoopGetCurrent(), timer, kCFRunLoopCommonModes);
    CFRelease(timer);
}

#pragma mark - Event tap

static CGEventRef TapCallback(CGEventTapProxy proxy, CGEventType type,
                              CGEventRef event, void *refcon) {
    (void)proxy;
    (void)refcon;

    switch (type) {
        case kCGEventKeyDown: {
            CGKeyCode keycode = (CGKeyCode)CGEventGetIntegerValueField(
                event, kCGKeyboardEventKeycode);
            CGEventFlags flags = CGEventGetFlags(event);
            bool cmdDown = (flags & kCGEventFlagMaskCommand) != 0;

            if (keycode == kVK_Escape) {
                // Esc cancels the app switcher, so don't restore anything.
                gCmdTabActive = false;
            } else if (keycode == kVK_Tab && cmdDown) {
                // A Cmd+Tab switch is starting (first press only; holding
                // Tab to cycle keeps the flag set).
                bool isRepeat = CGEventGetIntegerValueField(
                    event, kCGKeyboardEventAutorepeat) != 0;
                if (!isRepeat) {
                    gCmdTabActive = true;
                    if (gDebug) {
                        printf("[minrl] Cmd+Tab detected\n");
                    }
                }
            }
            break;
        }
        case kCGEventFlagsChanged: {
            CGKeyCode keycode = (CGKeyCode)CGEventGetIntegerValueField(
                event, kCGKeyboardEventKeycode);
            if (keycode == kVK_Command || keycode == kVK_RightCommand) {
                CGEventFlags flags = CGEventGetFlags(event);
                bool cmdDown = (flags & kCGEventFlagMaskCommand) != 0;
                // Cmd released = the switch commits: restore minimized
                // windows of the app we just switched to.
                if (!cmdDown && gCmdTabActive) {
                    gCmdTabActive = false;
                    ScheduleRestore();
                }
            }
            break;
        }
        case kCGEventTapDisabledByTimeout:
        case kCGEventTapDisabledByUserInput:
            if (gTap != NULL) {
                CGEventTapEnable(gTap, true);
            }
            break;
        default:
            break;
    }
    return event;
}

#pragma mark - Menu bar app

@interface AppDelegate : NSObject <NSApplicationDelegate>
- (void)setupStatusItem;
@end

@implementation AppDelegate

// Window symbol (center) with a small Option badge (bottom-right).
- (NSImage *)statusIcon {
    // "interface.window" is not a real SF Symbol name, so use "macwindow".
    NSImage *windowSym = [NSImage imageWithSystemSymbolName:@"macwindow"
                                    accessibilityDescription:nil];
    windowSym = [windowSym imageWithSymbolConfiguration:
        [NSImageSymbolConfiguration configurationWithPointSize:17.0
                                                        weight:NSFontWeightSemibold]];

    NSImage *icon = [[NSImage alloc] initWithSize:NSMakeSize(22.0, 22.0)];
    [icon lockFocus];

    // Window glyph, centered.
    if (windowSym != nil) {
        [windowSym drawInRect:NSMakeRect(3.0, 4.0, 16.0, 13.5)
                      fromRect:NSZeroRect
                     operation:NSCompositingOperationSourceOver
                      fraction:1.0];
    }
    // Option badge in the bottom-right corner, drawn as the literal ⌥
    // character since no SF Symbol is named "option".
    NSDictionary *attrs = @{
        NSFontAttributeName : [NSFont boldSystemFontOfSize:9.0],
        NSForegroundColorAttributeName : [NSColor blackColor],
    };
    NSString *opt = @"\u2325"; // ⌥
    [opt drawAtPoint:NSMakePoint(12.5, 1.0) withAttributes:attrs];

    [icon unlockFocus];
    icon.template = YES; // adapts to light/dark menu bar

    if (gDebug) {
        // Save what the status bar actually got, so it can be inspected.
        NSBitmapImageRep *rep =
            [NSBitmapImageRep imageRepWithData:[icon TIFFRepresentation]];
        NSData *png = [rep representationUsingType:NSBitmapImageFileTypePNG
                                        properties:@{}];
        [png writeToFile:@"/tmp/minrl_status_icon.png" atomically:YES];
        long px = 0;
        if (rep != nil) {
            for (NSInteger y = 0; y < rep.pixelsHigh; y++) {
                for (NSInteger x = 0; x < rep.pixelsWide; x++) {
                    if ([[rep colorAtX:x y:y] alphaComponent] > 0.05) {
                        px++;
                    }
                }
            }
        }
        printf("minrl: status icon rendered, %ld non-transparent pixels "
               "(saved /tmp/minrl_status_icon.png)\n",
               px);
    }
    return icon;
}

- (void)setStatusLabel:(NSString *)text {
    if (gStatusLabel != nil) {
        gStatusLabel.title = text;
    }
}

- (void)setupStatusItem {
    gStatusItem = [[NSStatusBar systemStatusBar]
        statusItemWithLength:24.0]; // fixed width so the icon can't collapse
    gStatusItem.button.image = [self statusIcon];
    gStatusItem.button.toolTip = @"minrl - Cmd+Tab restores minimized windows";

    NSMenu *menu = [[NSMenu alloc] init];

    gStatusLabel = [[NSMenuItem alloc]
        initWithTitle:@"minrl - starting..." action:nil keyEquivalent:@""];
    gStatusLabel.enabled = NO;
    [menu addItem:gStatusLabel];

    NSMenuItem *settings = [[NSMenuItem alloc]
        initWithTitle:@"Open Accessibility Settings..."
               action:@selector(openAccessibilitySettings:)
        keyEquivalent:@""];
    settings.target = self;
    [menu addItem:settings];

    [menu addItem:[NSMenuItem separatorItem]];

    NSMenuItem *quit = [[NSMenuItem alloc]
        initWithTitle:@"Quit minrl"
               action:@selector(terminate:)
        keyEquivalent:@"q"];
    [menu addItem:quit];

    gStatusItem.menu = menu;
    printf("minrl: status item created\n");
    fflush(stdout);
}

- (void)openAccessibilitySettings:(id)sender {
    NSURL *url = [NSURL URLWithString:
        @"x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"];
    [NSWorkspace.sharedWorkspace openURL:url];
}

- (void)startTap {
    CGEventMask mask = CGEventMaskBit(kCGEventKeyDown) |
                       CGEventMaskBit(kCGEventFlagsChanged);
    // kCGEventTapDisabledByTimeout / kCGEventTapDisabledByUserInput are
    // 0xFFFFFFFE / 0xFFFFFFFF: the system reports them through the top two
    // bits of the 64-bit mask (CGEventMaskBit would shift past the width).
    mask |= (CGEventMask)1 << 62;
    mask |= (CGEventMask)1 << 63;

    gTap = CGEventTapCreate(
        kCGSessionEventTap,
        kCGHeadInsertEventTap,
        kCGEventTapOptionDefault,
        mask,
        TapCallback, NULL);

    if (gTap == NULL) {
        printf("minrl: could not create the event tap - grant Accessibility "
               "to minrl in System Settings → Privacy & Security → "
               "Accessibility\n");
        fflush(stdout);
        [self setStatusLabel:@"minrl - needs Accessibility permission"];
        return;
    }

    CFRunLoopSourceRef src =
        CFMachPortCreateRunLoopSource(kCFAllocatorDefault, gTap, 0);
    CFRunLoopAddSource(CFRunLoopGetCurrent(), src, kCFRunLoopCommonModes);
    CFRelease(src);
    CGEventTapEnable(gTap, true);

    printf("minrl: watching for Cmd+Tab, restoring minimized windows...\n");
    fflush(stdout);
    [self setStatusLabel:@"minrl - active"];
}

- (void)promptForPermission {
    CFStringRef keys[] = { kAXTrustedCheckOptionPrompt };
    CFTypeRef values[] = { kCFBooleanTrue };
    CFDictionaryRef opts = CFDictionaryCreate(
        kCFAllocatorDefault, (const void **)keys, (const void **)values, 1,
        &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
    AXIsProcessTrustedWithOptions(opts);
    CFRelease(opts);
}

- (void)pollForPermission {
    if (AXIsProcessTrusted()) {
        printf("minrl: Accessibility granted - starting tap.\n");
        fflush(stdout);
        [self startTap];
        return;
    }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,
                                 (int64_t)(1.0 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        [self pollForPermission];
    });
}

- (void)applicationDidFinishLaunching:(NSNotification *)note {
    if (AXIsProcessTrusted()) {
        printf("minrl: Accessibility trusted\n");
        [self startTap];
    } else {
        printf("minrl: Accessibility permission needed - prompting.\n");
        fflush(stdout);
        [self setStatusLabel:@"minrl - needs Accessibility permission"];
        [self promptForPermission];
        [self pollForPermission];
    }
}

- (void)applicationWillTerminate:(NSNotification *)note {
    if (gTap != NULL) {
        CFRelease(gTap);
        gTap = NULL;
    }
}

@end

int main(int argc, const char **argv) {
    (void)argc;
    (void)argv;
    @autoreleasepool {
        NSApplication *app = [NSApplication sharedApplication];
        [app setActivationPolicy:NSApplicationActivationPolicyAccessory];

        gDebug = getenv("MINRL_DEBUG") != NULL;
        // Always log to /tmp/minrl.log so state can be diagnosed.
        freopen("/tmp/minrl.log", "w", stdout);
        setvbuf(stdout, NULL, _IONBF, 0);
        printf("minrl: starting (log: /tmp/minrl.log%s)\n",
               gDebug ? ", debug on" : "");

        AppDelegate *delegate = [[AppDelegate alloc] init];
        app.delegate = delegate;

        // Create the status item before the app starts running so the menu
        // bar icon appears immediately.
        [delegate setupStatusItem];

        [app run];
    }
    return 0;
}
