#import "../../Utils.h"

// Demangled name: IGFeedPlayback.IGFeedPlaybackStrategy
%hook _TtC14IGFeedPlayback22IGFeedPlaybackStrategy
- (id)initWithShouldDisableAutoplay:(_Bool)autoplay {
    if ([SCIUtils getBoolPref:@"disable_feed_autoplay"]) return %orig(true);

    return %orig(autoplay);
}

// Newer IG versions
- (id)initWithShouldDisableAutoplay:(_Bool)autoplay shouldClearStaleReservation:(_Bool)clear {
    if ([SCIUtils getBoolPref:@"disable_feed_autoplay"]) return %orig(true, clear);

    return %orig(autoplay, clear);
}
- (id)initWithShouldDisableAutoplay:(_Bool)autoplay shouldClearStaleReservation:(_Bool)clear shouldBypassDisabledAutoplayForVoiceover:(_Bool)bypass {
    if ([SCIUtils getBoolPref:@"disable_feed_autoplay"]) return %orig(true, clear, bypass);

    return %orig(autoplay, clear, bypass);
}
- (id)initWithShouldDisableAutoplay:(_Bool)autoplay shouldClearStaleReservation:(_Bool)clear shouldBypassDisabledAutoplayForVoiceover:(_Bool)bypass shouldOverrideDefaultThresholds:(_Bool)thresholds mobileConfig:(id)config {
    if ([SCIUtils getBoolPref:@"disable_feed_autoplay"]) return %orig(true, clear, bypass, thresholds, config);

    return %orig(autoplay, clear, bypass, thresholds, config);
}
%end
