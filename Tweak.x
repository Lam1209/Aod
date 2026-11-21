// SimpleAOD - Always On Display for OLED iPhones (written for iPhone X)
//
// SpringBoard switches the screen off by driving the backlight factor to 0
// through SBBacklightController. We intercept that request: instead of going
// dark we show a pure-black overlay window (clock, date, battery), drop the
// backlight to a very low level and stop the device from idle-sleeping.
// Any wake-up (side button, raise to wake, notification, tap on the overlay)
// brings the backlight back and the overlay fades out.
//
// v0.1 - written without access to a device. See README.md ("If it doesn't work").

#import <UIKit/UIKit.h>
#import <objc/message.h>
#import <math.h>

#define AODLog(fmt, ...) NSLog(@"[SimpleAOD] " fmt, ##__VA_ARGS__)

static NSString *const kPrefsDomain = @"com.local.simpleaod";
static const float kMinBattery = 0.10f;   // no AOD below 10 percent battery unless charging

// ---------------------------------------------------------------------------
// Private SpringBoard API (declared here so we don't need extra headers)
// ---------------------------------------------------------------------------
@interface SBBacklightController : NSObject
+ (instancetype)sharedInstance;
- (void)turnOnScreenFullyWithBacklightSource:(long long)source;
- (void)_animateBacklightToFactor:(float)factor duration:(double)duration source:(long long)source silently:(BOOL)silently completion:(id)completion;
- (void)setBacklightFactor:(float)factor source:(long long)source;
- (void)preventIdleSleep;
- (void)allowIdleSleep;
@end

// ---------------------------------------------------------------------------
// Preferences (/var/mobile/Library/Preferences/com.local.simpleaod.plist)
// ---------------------------------------------------------------------------
static id AODPref(NSString *key) {
    CFPropertyListRef value = CFPreferencesCopyAppValue((__bridge CFStringRef)key, (__bridge CFStringRef)kPrefsDomain);
    return value ? CFBridgingRelease(value) : nil;
}

static BOOL AODBool(NSString *key, BOOL fallback) {
    id value = AODPref(key);
    return [value respondsToSelector:@selector(boolValue)] ? [value boolValue] : fallback;
}

static float AODFloat(NSString *key, float fallback) {
    id value = AODPref(key);
    return [value respondsToSelector:@selector(floatValue)] ? [value floatValue] : fallback;
}

// Backlight factor used while the AOD is showing (the "screen off" brightness).
static float AODDimFactor(void) {
    float f = AODFloat(@"brightness", 0.10f);
    return fminf(fmaxf(f, 0.02f), 0.60f);
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------
static void AODOnMain(dispatch_block_t block) {
    if ([NSThread isMainThread]) block();
    else dispatch_async(dispatch_get_main_queue(), block);
}

static id AODBacklight(void) {
    Class cls = NSClassFromString(@"SBBacklightController");
    return [cls respondsToSelector:@selector(sharedInstance)] ? [(id)cls sharedInstance] : nil;
}

// True while a phone call is active (the proximity sensor must really blank
// the screen against your ear). Every step is guarded, so if the private class
// or selector is missing on your iOS version this simply returns NO.
static BOOL AODInCall(void) {
    Class cls = NSClassFromString(@"TUCallCenter");
    SEL sharedSel = NSSelectorFromString(@"sharedInstance");
    SEL countSel = NSSelectorFromString(@"currentCallCount");
    if (!cls || ![cls respondsToSelector:sharedSel]) return NO;
    id center = ((id (*)(Class, SEL))objc_msgSend)(cls, sharedSel);
    if (!center || ![center respondsToSelector:countSel]) return NO;
    return ((NSInteger (*)(id, SEL))objc_msgSend)(center, countSel) > 0;
}

// iOS 13+: make sure the overlay window belongs to a window scene.
// (No @available on purpose, so it builds with any SDK / deployment target.)
static void AODAttachToScene(UIWindow *window) {
    @try {
        if (![window respondsToSelector:NSSelectorFromString(@"windowScene")]) return;
        if ([window valueForKey:@"windowScene"]) return;
        Class sceneClass = NSClassFromString(@"UIWindowScene");
        id scenes = [[UIApplication sharedApplication] valueForKey:@"connectedScenes"];
        for (id scene in scenes) {
            if (sceneClass && [scene isKindOfClass:sceneClass]) {
                [window setValue:scene forKey:@"windowScene"];
                break;
            }
        }
    } @catch (NSException *e) {
        AODLog(@"could not attach to a scene: %@", e);
    }
}

static BOOL AODShouldRun(void) {
    CFPreferencesAppSynchronize((__bridge CFStringRef)kPrefsDomain);
    if (!AODBool(@"enabled", YES)) return NO;
    if (AODInCall()) return NO;

    UIDevice *device = [UIDevice currentDevice];
    BOOL charging = device.batteryState == UIDeviceBatteryStateCharging ||
                    device.batteryState == UIDeviceBatteryStateFull;
    if (AODBool(@"chargingOnly", NO) && !charging) return NO;
    if (!charging && device.batteryLevel >= 0.0f && device.batteryLevel < kMinBattery) return NO;
    return YES;
}

// ---------------------------------------------------------------------------
// The overlay
// ---------------------------------------------------------------------------
@interface AODController : NSObject {
    UIWindow *_window;
    UIView *_content;
    UILabel *_timeLabel;
    UILabel *_dateLabel;
    UILabel *_batteryLabel;
    UITapGestureRecognizer *_tap;
    NSTimer *_timer;
    BOOL _active;
    BOOL _holdingIdleSleep;
}
+ (instancetype)shared;
- (BOOL)isActive;
- (void)prepare;
- (void)show;
- (void)hide;
- (void)holdIdleSleep;
@end

@implementation AODController

+ (instancetype)shared {
    static AODController *instance;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ instance = [[AODController alloc] init]; });
    return instance;
}

- (BOOL)isActive {
    return _active;
}

- (void)prepare {
    [UIDevice currentDevice].batteryMonitoringEnabled = YES;
}

- (UILabel *)labelWithFrame:(CGRect)frame font:(UIFont *)font alpha:(CGFloat)alpha {
    UILabel *label = [[UILabel alloc] initWithFrame:frame];
    label.textAlignment = NSTextAlignmentCenter;
    label.font = font;
    label.textColor = [UIColor colorWithWhite:1.0 alpha:alpha];
    label.backgroundColor = [UIColor clearColor];
    label.adjustsFontSizeToFitWidth = YES;
    label.minimumScaleFactor = 0.5;
    return label;
}

- (void)buildWindow {
    CGRect bounds = [UIScreen mainScreen].bounds;
    CGFloat w = bounds.size.width;
    CGFloat h = bounds.size.height;

    _window = [[UIWindow alloc] initWithFrame:bounds];
    _window.windowLevel = 100000.0;              // above lock screen, alerts, HUDs
    _window.backgroundColor = [UIColor blackColor];
    AODAttachToScene(_window);

    _content = [[UIView alloc] initWithFrame:bounds];
    _content.backgroundColor = [UIColor clearColor];
    _content.userInteractionEnabled = NO;
    [_window addSubview:_content];

    CGFloat top = h * 0.28;
    _timeLabel = [self labelWithFrame:CGRectMake(0, top, w, 110)
                                 font:[UIFont monospacedDigitSystemFontOfSize:92 weight:UIFontWeightThin]
                                alpha:0.85];
    _dateLabel = [self labelWithFrame:CGRectMake(0, top + 108, w, 28)
                                 font:[UIFont systemFontOfSize:21 weight:UIFontWeightRegular]
                                alpha:0.65];
    _batteryLabel = [self labelWithFrame:CGRectMake(0, top + 144, w, 24)
                                    font:[UIFont systemFontOfSize:17 weight:UIFontWeightRegular]
                                   alpha:0.55];
    [_content addSubview:_timeLabel];
    [_content addSubview:_dateLabel];
    [_content addSubview:_batteryLabel];

    _tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(wakeTapped)];
    [_window addGestureRecognizer:_tap];
}

- (void)show {
    AODOnMain(^{
        [self prepare];
        if (self->_active) {
            [self refresh];
            return;
        }
        if (!self->_window) [self buildWindow];

        self->_active = YES;
        self->_tap.numberOfTapsRequired = AODBool(@"doubleTap", YES) ? 2 : 1;
        [self->_window.layer removeAllAnimations];
        self->_window.userInteractionEnabled = YES;
        self->_window.alpha = 1.0;
        self->_window.hidden = NO;
        [self refresh];
        [self scheduleTimer];
        AODLog(@"AOD on");
    });
}

- (void)hide {
    AODOnMain(^{
        if (!self->_active) return;
        self->_active = NO;
        [self->_timer invalidate];
        self->_timer = nil;
        self->_window.userInteractionEnabled = NO;
        [self releaseIdleSleep];
        [UIView animateWithDuration:0.25 animations:^{
            self->_window.alpha = 0.0;
        } completion:^(BOOL finished) {
            if (!self->_active) self->_window.hidden = YES;
        }];
        AODLog(@"AOD off");
    });
}

// Keep the device awake while the AOD is up (otherwise the clock would freeze).
- (void)holdIdleSleep {
    if (_holdingIdleSleep) return;
    id backlight = AODBacklight();
    if ([backlight respondsToSelector:@selector(preventIdleSleep)]) {
        [backlight preventIdleSleep];
        _holdingIdleSleep = YES;
    }
}

- (void)releaseIdleSleep {
    if (!_holdingIdleSleep) return;
    _holdingIdleSleep = NO;
    id backlight = AODBacklight();
    if ([backlight respondsToSelector:@selector(allowIdleSleep)]) {
        [backlight allowIdleSleep];
    }
}

- (void)wakeTapped {
    AODLog(@"tap to wake");
    id backlight = AODBacklight();
    if ([backlight respondsToSelector:@selector(turnOnScreenFullyWithBacklightSource:)]) {
        [backlight turnOnScreenFullyWithBacklightSource:1];
    } else if ([backlight respondsToSelector:@selector(_animateBacklightToFactor:duration:source:silently:completion:)]) {
        [backlight _animateBacklightToFactor:1.0f duration:0.2 source:1 silently:NO completion:nil];
    }
    [self hide];
}

// Refresh once a minute, aligned to the minute change.
- (void)scheduleTimer {
    [_timer invalidate];
    NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
    NSDate *fire = [NSDate dateWithTimeIntervalSince1970:(floor(now / 60.0) + 1.0) * 60.0];
    _timer = [[NSTimer alloc] initWithFireDate:fire interval:60.0 target:self selector:@selector(tick) userInfo:nil repeats:YES];
    [[NSRunLoop mainRunLoop] addTimer:_timer forMode:NSRunLoopCommonModes];
}

- (void)tick {
    if (_active) [self refresh];
}

// Burn-in protection: nudge everything to a new spot every minute.
- (void)applyPixelShift {
    if (!AODBool(@"pixelShift", YES)) {
        _content.transform = CGAffineTransformIdentity;
        return;
    }
    CGFloat dx = (CGFloat)arc4random_uniform(41) - 20.0;
    CGFloat dy = (CGFloat)arc4random_uniform(81) - 40.0;
    _content.transform = CGAffineTransformMakeTranslation(dx, dy);
}

- (void)refresh {
    NSDate *now = [NSDate date];
    NSLocale *locale = [NSLocale currentLocale];

    NSDateFormatter *timeFormat = [[NSDateFormatter alloc] init];
    timeFormat.locale = locale;
    timeFormat.dateFormat = [NSDateFormatter dateFormatFromTemplate:@"jmm" options:0 locale:locale];
    _timeLabel.text = [timeFormat stringFromDate:now];

    NSDateFormatter *dateFormat = [[NSDateFormatter alloc] init];
    dateFormat.locale = locale;
    dateFormat.dateFormat = [NSDateFormatter dateFormatFromTemplate:@"EEEEMMMMd" options:0 locale:locale];
    _dateLabel.text = [dateFormat stringFromDate:now];

    UIDevice *device = [UIDevice currentDevice];
    float level = device.batteryLevel;
    BOOL charging = device.batteryState == UIDeviceBatteryStateCharging ||
                    device.batteryState == UIDeviceBatteryStateFull;
    if (level < 0.0f) {
        _batteryLabel.text = @"";
    } else {
        _batteryLabel.text = [NSString stringWithFormat:@"%@%ld%%",
                              charging ? @"Charging \u00B7 " : @"",
                              lroundf(level * 100.0f)];
    }

    [self applyPixelShift];
}

@end

// ---------------------------------------------------------------------------
// Hooks
// ---------------------------------------------------------------------------
%hook SpringBoard

- (void)applicationDidFinishLaunching:(id)application {
    %orig;
    [[AODController shared] prepare];
}

%end

%hook SBBacklightController

// Main hook: every backlight change goes through here.
//   factor == 0     -> SpringBoard wants the screen OFF  -> show AOD at a low level instead
//   factor >> dim   -> screen is waking up                -> hide AOD
- (void)_animateBacklightToFactor:(float)factor duration:(double)duration source:(long long)source silently:(BOOL)silently completion:(id)completion {
    AODLog(@"_animateBacklightToFactor:%.3f source:%lld", factor, source);
    AODController *aod = [AODController shared];

    if (factor < 0.001f) {
        if (AODShouldRun()) {
            [aod show];
            %orig(AODDimFactor(), duration, source, silently, completion);
            [aod holdIdleSleep];
            return;
        }
        [aod hide];   // AOD can't run right now (disabled, low battery, on a call...)
    } else if ([aod isActive] && factor > AODDimFactor() + 0.05f) {
        [aod hide];
    }
    %orig;
}

// Same logic for the non-animated setter (some iOS versions use it).
- (void)setBacklightFactor:(float)factor source:(long long)source {
    AODLog(@"setBacklightFactor:%.3f source:%lld", factor, source);
    AODController *aod = [AODController shared];

    if (factor < 0.001f) {
        if (AODShouldRun()) {
            [aod show];
            %orig(AODDimFactor(), source);
            [aod holdIdleSleep];
            return;
        }
        [aod hide];
    } else if ([aod isActive] && factor > AODDimFactor() + 0.05f) {
        [aod hide];
    }
    %orig;
}

// Explicit "wake up" entry point (side button, raise to wake, notifications...).
- (void)turnOnScreenFullyWithBacklightSource:(long long)source {
    [[AODController shared] hide];
    %orig;
}

// SpringBoard tries to let the device idle-sleep when it thinks the screen is off.
// Ignore that while the AOD is showing.
- (void)allowIdleSleep {
    if ([[AODController shared] isActive]) {
        AODLog(@"allowIdleSleep ignored (AOD active)");
        return;
    }
    %orig;
}

%end
