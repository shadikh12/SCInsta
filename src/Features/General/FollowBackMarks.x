#import "../../InstagramHeaders.h"
#import "../../Utils.h"

static const NSInteger kFollowBackLabelTag = 0x5C1F0B;

// Marks users who don't follow you back in follower/following lists
%hook IGFollowListCollectionCell
- (void)layoutSubviews {
    %orig;

    UILabel *label = [self.contentView viewWithTag:kFollowBackLabelTag];

    if (![SCIUtils getBoolPref:@"follow_back_marks"]) {
        label.hidden = YES;
        return;
    }

    [SCIUtils runFeature:@"Follow back marks" block:^{
        IGUser *user = [SCIUtils getIvarForObj:self name:"_user"];
        IGUserSession *session = [SCIUtils getIvarForObj:self name:"_userSession"];

        // Only mark once the follow status is known, and never mark yourself
        BOOL show = user && user.friendshipStatus && !user.followsCurrentUser
                    && ![user.username isEqualToString:session.user.username];

        UILabel *markLabel = label;
        if (!markLabel && show) {
            markLabel = [[UILabel alloc] init];
            markLabel.tag = kFollowBackLabelTag;
            markLabel.text = @"Doesn't follow you";
            markLabel.font = [UIFont systemFontOfSize:10 weight:UIFontWeightSemibold];
            markLabel.textColor = [UIColor systemRedColor];
            [self.contentView addSubview:markLabel];
        }
        if (!markLabel) return;

        markLabel.hidden = !show;
        [markLabel sizeToFit];

        // Bottom-right corner, under the follow button
        CGSize size = markLabel.bounds.size;
        CGRect bounds = self.contentView.bounds;
        markLabel.frame = CGRectMake(CGRectGetMaxX(bounds) - size.width - 16, CGRectGetMaxY(bounds) - size.height - 2, size.width, size.height);
    }];
}
%end
