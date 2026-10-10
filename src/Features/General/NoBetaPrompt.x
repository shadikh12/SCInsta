#import <Foundation/Foundation.h>

// Sideloaded apps report a TestFlight-style receipt, which makes Instagram
// show the "update via TestFlight" beta prompt. Report an App Store receipt instead.
%hook NSBundle
- (NSURL *)appStoreReceiptURL {
    NSURL *url = %orig;
    if ([url.lastPathComponent isEqualToString:@"sandboxReceipt"]) {
        return [[url URLByDeletingLastPathComponent] URLByAppendingPathComponent:@"receipt"];
    }
    return url;
}
%end
