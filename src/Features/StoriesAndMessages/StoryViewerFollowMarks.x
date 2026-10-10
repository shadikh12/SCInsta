#import "../../InstagramHeaders.h"
#import "../../Utils.h"

// Marks viewers of your story who don't follow you

static char kViewerObjectKey;
static const NSInteger kViewerMarkLabelTag = 0x5C1F0C;

// The section controller's object is the viewer (or a model wrapping it)
static IGUser *viewerUser(id object) {
    if ([object isKindOfClass:%c(IGUser)]) return object;

    for (NSString *key in @[@"user", @"viewer", @"viewerUser"]) {
        SEL sel = NSSelectorFromString(key);
        if (![object respondsToSelector:sel]) continue;

        id value = ((id (*)(id, SEL))objc_msgSend)(object, sel);
        if ([value isKindOfClass:%c(IGUser)]) return value;
    }

    return nil;
}

// Pass each viewer from its section controller on to its cell
%hook IGStoryViewerSectionController.IGStoryViewerSectionController
- (void)didUpdateToObject:(id)object {
    %orig;

    objc_setAssociatedObject(self, &kViewerObjectKey, object, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
- (id)cellForItemAtIndex:(NSInteger)index {
    id cell = %orig;

    if ([SCIUtils getBoolPref:@"story_viewer_follow_marks"] && [cell isKindOfClass:%c(IGStoryViewerCell)]) {
        objc_setAssociatedObject(cell, &kViewerObjectKey, objc_getAssociatedObject(self, &kViewerObjectKey), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [cell setNeedsLayout];
    }

    return cell;
}
%end

%hook IGStoryViewerCell
- (void)layoutSubviews {
    %orig;

    UILabel *label = [self.contentView viewWithTag:kViewerMarkLabelTag];

    if (![SCIUtils getBoolPref:@"story_viewer_follow_marks"]) {
        label.hidden = YES;
        return;
    }

    [SCIUtils runFeature:@"Story viewer follow marks" block:^{
        id object = objc_getAssociatedObject(self, &kViewerObjectKey);
        IGUser *user = viewerUser(object);
        if (object && !user) NSLog(@"[SCInsta] Story viewer object has no user: %@", [object class]);

        // Only mark once the follow status is known
        BOOL show = user && user.friendshipStatus && !user.followsCurrentUser;

        UILabel *markLabel = label;
        if (!markLabel && show) {
            markLabel = [[UILabel alloc] init];
            markLabel.tag = kViewerMarkLabelTag;
            markLabel.text = @"Doesn't follow you";
            markLabel.font = [UIFont systemFontOfSize:10 weight:UIFontWeightSemibold];
            markLabel.textColor = [UIColor systemRedColor];
            [self.contentView addSubview:markLabel];
        }
        if (!markLabel) return;

        markLabel.hidden = !show;
        [markLabel sizeToFit];

        // Under the username/name, or bottom-left if that view can't be found
        UIView *descriptionView = [SCIUtils getIvarForObj:self name:"_descriptionView"];
        CGRect anchor = descriptionView ? [descriptionView convertRect:descriptionView.bounds toView:self.contentView] : CGRectZero;

        CGFloat x = descriptionView ? CGRectGetMinX(anchor) : 72;
        CGFloat y = MIN(CGRectGetMaxY(anchor), CGRectGetMaxY(self.contentView.bounds) - markLabel.bounds.size.height - 2);
        markLabel.frame = (CGRect){ CGPointMake(x, y), markLabel.bounds.size };
    }];
}
%end
