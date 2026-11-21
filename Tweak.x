// iPhoneXAOD - minimal Always-On-Display for iPhone X (OLED), SpringBoard tweak
// Target: iOS 13-14 (checkra1n, rootful). Build with Theos.
#import <UIKit/UIKit.h>
#import <objc/runtime.h>

@interface SBLockScreenManager : NSObject
+ (instancetype)sharedInstance;
- (BOOL)isUILocked;
@end

static UIWindow *aodWindow = nil;
static UILabel *timeLabel = nil, *dateLabel = nil, *batLabel = nil;
static NSTimer *tickTimer = nil;
static CGFloat savedBrightness = -1.0;
static NSInteger tick = 0;

static const CGFloat kAODBrightness = 0.03; // very dim, OLED black = pixels off

static void updateAOD(void) {
    if (!aodWindow) return;
    static NSDateFormatter *tf, *df;
    if (!tf) {
        tf = [NSDateFormatter new]; tf.dateFormat = @"H:mm";
        df = [NSDateFormatter new]; df.dateFormat = @"EEEE, d MMMM";
    }
    NSDate *now = [NSDate date];
    timeLabel.text = [tf stringFromDate:now];
    dateLabel.text = [df stringFromDate:now];
    float lvl = [UIDevice currentDevice].batteryLevel;
    batLabel.text = lvl >= 0 ? [NSString stringWithFormat:@"%d%%", (int)(lvl * 100)] : @"";

    // Pixel shift every minute to reduce OLED burn-in
    static const CGFloat dx[] = {0, 6, -6, 4, -4, 0};
    static const CGFloat dy[] = {0, -4, 4, 6, -6, 0};
    NSInteger i = tick++ % 6;
    CGRect b = aodWindow.bounds;
    CGFloat cx = CGRectGetMidX(b) + dx[i], cy = CGRectGetMidY(b) + dy[i];
    timeLabel.center = CGPointMake(cx, cy - 20);
    dateLabel.center = CGPointMake(cx, cy + 40);
    batLabel.center  = CGPointMake(cx, cy + 75);
}

static UILabel *makeLabel(CGFloat size, UIFontWeight w, CGFloat height) {
    UILabel *l = [[UILabel alloc] initWithFrame:CGRectMake(0, 0, 320, height)];
    l.textColor = [UIColor colorWithWhite:1.0 alpha:0.7];
    l.font = [UIFont systemFontOfSize:size weight:w];
    l.textAlignment = NSTextAlignmentCenter;
    return l;
}

static void showAOD(void) {
    if (aodWindow) return;
    [UIDevice currentDevice].batteryMonitoringEnabled = YES;

    aodWindow = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    aodWindow.windowLevel = UIWindowLevelAlert + 10000;
    aodWindow.backgroundColor = [UIColor blackColor];
    aodWindow.userInteractionEnabled = NO;

    timeLabel = makeLabel(88, UIFontWeightUltraLight, 100);
    dateLabel = makeLabel(20, UIFontWeightRegular, 26);
    batLabel  = makeLabel(15, UIFontWeightRegular, 20);
    [aodWindow addSubview:timeLabel];
    [aodWindow addSubview:dateLabel];
    [aodWindow addSubview:batLabel];
    aodWindow.hidden = NO;
    updateAOD();

    if (savedBrightness < 0) savedBrightness = [UIScreen mainScreen].brightness;
    [UIScreen mainScreen].brightness = kAODBrightness;

    tickTimer = [NSTimer scheduledTimerWithTimeInterval:60 repeats:YES block:^(NSTimer *t) {
        updateAOD();
    }];
}

static void hideAOD(void) {
    [tickTimer invalidate];
    tickTimer = nil;
    if (aodWindow) {
        aodWindow.hidden = YES;
        aodWindow = nil;
        timeLabel = dateLabel = batLabel = nil;
    }
    if (savedBrightness >= 0) {
        [UIScreen mainScreen].brightness = savedBrightness;
        savedBrightness = -1.0;
    }
}

%hook SBBacklightController
// VERIFY this selector exists on your iOS version (see README).
- (void)_animateBacklightToFactor:(float)factor duration:(double)duration source:(long long)source silently:(BOOL)silently completion:(id)completion {
    BOOL locked = NO;
    Class lm = objc_getClass("SBLockScreenManager");
    if (lm) locked = [[lm sharedInstance] isUILocked];

    if (factor <= 0.0f && locked) {
        showAOD();
        %orig(0.02f, duration, source, silently, completion);
        return;
    }
    if (factor > 0.0f) hideAOD();
    %orig;
}
%end
