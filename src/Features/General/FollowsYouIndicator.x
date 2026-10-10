#import "../../InstagramHeaders.h"
#import "../../Utils.h"

// Reads a boxed boolean (FBBoxedBoolean / NSNumber) from the relationship info, NO if missing
static BOOL relationshipFlag(id relationship, NSString *key) {
    SEL sel = NSSelectorFromString(key);
    if (![relationship respondsToSelector:sel]) return NO;

    id value = ((id (*)(id, SEL))objc_msgSend)(relationship, sel);
    return [value respondsToSelector:@selector(boolValue)] && [value boolValue];
}

// Show whether the user of an opened profile follows you back (+ your relationship with them)
%hook IGProfileViewController
- (void)viewDidAppear:(BOOL)animated {
    %orig;

    if ([SCIUtils getBoolPref:@"show_follows_you"]) {
        [self showFollowsYouIndicatorWithAttempt:0];
    }
}

%new - (void)showFollowsYouIndicatorWithAttempt:(NSInteger)attempt {
    [SCIUtils runFeature:@"Show if user follows you" block:^{
        if (!self.view.window) return;

        IGUser *user = [self user];
        IGUser *currentUser = [self userSession].user;
        if (!user || !currentUser || [user.username isEqualToString:currentUser.username]) return;

        // Only show once per opened profile
        static char shownKey;
        if ([objc_getAssociatedObject(self, &shownKey) isEqualToString:user.username]) return;

        // Follow status is loaded after the profile appears; wait for it (up to ~5s)
        id relationship = user.friendshipStatus;
        if (!relationship) {
            if (attempt >= 10) return;

            __weak typeof(self) weakSelf = self;
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                [weakSelf showFollowsYouIndicatorWithAttempt:attempt + 1];
            });
            return;
        }

        objc_setAssociatedObject(self, &shownKey, user.username, OBJC_ASSOCIATION_COPY_NONATOMIC);

        NSMutableArray<NSString *> *details = [NSMutableArray arrayWithObject:[NSString stringWithFormat:@"@%@", user.username]];
        if (relationshipFlag(relationship, @"isBestie")) [details addObject:@"Close friend"];
        if (relationshipFlag(relationship, @"isFeedFavorite")) [details addObject:@"Favorite"];
        if (relationshipFlag(relationship, @"muting")) [details addObject:@"Posts muted"];
        if (relationshipFlag(relationship, @"isMutingReel")) [details addObject:@"Story muted"];
        if (relationshipFlag(relationship, @"isRestricted")) [details addObject:@"Restricted"];

        [SCIUtils showToastForDuration:3.5
                                 title:user.followsCurrentUser ? @"Follows you" : @"Doesn't follow you"
                              subtitle:[details componentsJoinedByString:@" · "]];
    }];
}
%end
