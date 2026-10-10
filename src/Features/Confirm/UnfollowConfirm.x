#import "../../Utils.h"

// Confirm before unfollowing (all follow buttons go through IGFollowController)
%hook IGFollowing.IGFollowController
- (void)performUnfollow {
    if ([SCIUtils getBoolPref:@"unfollow_confirm"]) {
        NSLog(@"[SCInsta] Confirm unfollow triggered");

        [SCIUtils showConfirmation:^(void) { %orig; } title:@"Unfollow?"];
    }
    else {
        return %orig;
    }
}
%end
