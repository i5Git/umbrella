#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <substrate.h>

/*
 * Retica Rootless iOS 16 screen-off watchdog fix.
 *
 * The crash log shows SpringBoard's main queue staying unresponsive until
 * backboardd kills it after 60 seconds. LiquidAss avoids this class of lock
 * screen failure by treating the modern clock host as lifecycle-sensitive and
 * preventing unsafe clock work once the host is detached. Retica's original
 * implementation is preserved; this layer only guards its layout hook chain.
 */

static IMP gOrigProminentLayout = NULL;
static IMP gOrigLegacyLayout = NULL;

static const void *kRTCProminentApplyingKey = &kRTCProminentApplyingKey;
static const void *kRTCLegacyApplyingKey = &kRTCLegacyApplyingKey;

static inline BOOL RTCBeginClockLayout(UIView *view, const void *key) {
    if (!view || !view.window) {
        /* During screen-off / Cover Sheet teardown, do not let Retica mutate
         * a clock hierarchy that has already left its window. */
        return NO;
    }

    if ([objc_getAssociatedObject(view, key) boolValue]) {
        /* A font/text/frame mutation from Retica can synchronously cause
         * layoutSubviews again. Drop that nested pass instead of recursing. */
        return NO;
    }

    objc_setAssociatedObject(view, key, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return YES;
}

static inline void RTCEndClockLayout(UIView *view, const void *key) {
    if (view) {
        objc_setAssociatedObject(view, key, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
}

static void RTCProminentLayout(id self, SEL _cmd) {
    UIView *view = (UIView *)self;
    if (!RTCBeginClockLayout(view, kRTCProminentApplyingKey)) return;

    @try {
        if (gOrigProminentLayout) {
            ((void (*)(id, SEL))gOrigProminentLayout)(self, _cmd);
        }
    } @finally {
        RTCEndClockLayout(view, kRTCProminentApplyingKey);
    }
}

static void RTCLegacyLayout(id self, SEL _cmd) {
    UIView *view = (UIView *)self;
    if (!RTCBeginClockLayout(view, kRTCLegacyApplyingKey)) return;

    @try {
        if (gOrigLegacyLayout) {
            ((void (*)(id, SEL))gOrigLegacyLayout)(self, _cmd);
        }
    } @finally {
        RTCEndClockLayout(view, kRTCLegacyApplyingKey);
    }
}

static void RTCInstallHooks(void) {
    SEL layoutSEL = @selector(layoutSubviews);

    /* iOS 16+ modern lock-screen clock host. This is the important path for
     * the iPhone 12 / iOS 16.7.2 crash report. */
    Class prominent = objc_getClass("CSProminentTimeView");
    if (prominent) {
        MSHookMessageEx(prominent,
                        layoutSEL,
                        (IMP)RTCProminentLayout,
                        &gOrigProminentLayout);
    }

    /* Retica supports legacy lock-screen hosts too. Keeping the same guard
     * here makes the patched package safe if the fallback host is used. */
    Class legacy = objc_getClass("SBFLockScreenDateView");
    if (legacy) {
        MSHookMessageEx(legacy,
                        layoutSEL,
                        (IMP)RTCLegacyLayout,
                        &gOrigLegacyLayout);
    }
}

__attribute__((constructor))
static void RTCInit(void) {
    @autoreleasepool {
        if (![NSBundle.mainBundle.bundleIdentifier isEqualToString:@"com.apple.springboard"]) {
            return;
        }

        /* Install after the initial tweak constructors finish so this guard
         * wraps Retica's existing implementation instead of being wrapped by it. */
        dispatch_async(dispatch_get_main_queue(), ^{
            RTCInstallHooks();
        });
    }
}
