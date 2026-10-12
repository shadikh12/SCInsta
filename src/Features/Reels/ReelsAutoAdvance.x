#import "../../InstagramHeaders.h"
#import "../../Utils.h"

// Reels auto-advance: turns on Instagram's own (server-gated) reels auto-scroll,
// which moves to the next reel once the current one finishes

static BOOL autoAdvanceEnabled(void) {
    return [SCIUtils getBoolPref:@"reels_auto_advance"] && ![SCIUtils getBoolPref:@"disable_scrolling_reels"];
}

// Demangled name: IGSundialAutoScroll.IGSundialAutoScroll
%hook _TtC19IGSundialAutoScroll19IGSundialAutoScroll
- (BOOL)isEnabled {
    if ([SCIUtils getBoolPref:@"disable_scrolling_reels"]) return NO;
    if (autoAdvanceEnabled()) return YES;

    return %orig;
}
%end

%hook IGSundialFeedViewController
- (BOOL)shouldForceEnableAutoScroll {
    if (autoAdvanceEnabled()) return YES;

    return %orig;
}

- (BOOL)autoAdvanceToNextItem {
    if (autoAdvanceEnabled()) return YES;

    return %orig;
}
%end
