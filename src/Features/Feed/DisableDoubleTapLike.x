#import "../../Utils.h"

#define SKIPIFDOUBLETAPDISABLED(orig)                          \
    if ([SCIUtils getBoolPref:@"disable_double_tap_like"]) {   \
        return;                                                \
    }                                                          \
    return orig;                                               \

// Feed photos
%hook IGFeedPhotoView
- (void)_onDoubleTap:(id)arg1 {
    SKIPIFDOUBLETAPDISABLED(%orig);
}
%end
%hook IGFeedItemPhotoCell
- (void)feedPhotoDidDoubleTapToLike:(id)arg1 locationInfo:(id)arg2 {
    SKIPIFDOUBLETAPDISABLED(%orig);
}
%end
%hook IGFeedItemPageCell.IGFeedItemPagePhotoCell
- (void)feedPhotoDidDoubleTapToLike:(id)arg1 locationInfo:(id)arg2 {
    SKIPIFDOUBLETAPDISABLED(%orig);
}
%end

// Feed videos
%hook IGModernFeedVideoCell.IGModernFeedVideoCell
- (void)videoPlayerOverlayControllerDidDoubleTap:(id)arg1 locationInfo:(id)arg2 {
    SKIPIFDOUBLETAPDISABLED(%orig);
}
%end

// Reels
%hook IGSundialViewerVideoCell
- (void)gestureController:(id)arg1 didObserveDoubleTap:(id)arg2 {
    SKIPIFDOUBLETAPDISABLED(%orig);
}
%end
%hook IGSundialViewerPhotoCell
- (void)gestureController:(id)arg1 didObserveDoubleTap:(id)arg2 {
    SKIPIFDOUBLETAPDISABLED(%orig);
}
%end
