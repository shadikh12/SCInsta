#import "../../Utils.h"
#import "../../InstagramHeaders.h"

// Story seen receipts
// - "Disable story seen receipt" (no_seen_receipt) stops stories from being marked as seen
// - A button in the story viewer switches it on/off, and marks the current story as seen on demand

static NSString *const kNoSeenPref = @"no_seen_receipt";
static const NSInteger kSeenButtonTag = 0x5C1F0D;

// Lets manually marked stories through (uploads are batched, so allow a short window)
static BOOL forceStorySeen = NO;
static NSDate *allowUploadsUntil;

static BOOL blockStorySeen(void) {
    if (forceStorySeen) return NO;
    if (allowUploadsUntil && [allowUploadsUntil timeIntervalSinceNow] > 0) return NO;

    return [SCIUtils getBoolPref:kNoSeenPref];
}

@interface IGStoryViewerViewController : UIViewController
- (id)currentStoryItem;
- (id)currentlyDisplayedSectionController;
- (void)fullscreenSectionController:(id)controller didMarkItemAsSeen:(id)item;
- (void)sci_addSeenButton;
- (void)sci_updateSeenButton;
- (void)sci_markCurrentStorySeen;
- (void)sci_toggleNoSeenMode;
@end

%hook IGStorySeenStateUploader
// Uploads fail without a networker. Checked per upload, so it can be switched on/off at any time
- (id)networker {
    if (blockStorySeen()) {
        NSLog(@"[SCInsta] Prevented seen receipt from being sent");

        return nil;
    }

    return %orig;
}
%end

%hook IGStoryViewerViewController
- (void)fullscreenSectionController:(id)controller didMarkItemAsSeen:(id)item {
    if (blockStorySeen()) return;

    %orig;
}

- (void)viewDidLayoutSubviews {
    %orig;

    if ([SCIUtils getBoolPref:@"story_seen_button"]) {
        [self sci_addSeenButton];
    }
    else {
        [[self.view viewWithTag:kSeenButtonTag] removeFromSuperview];
    }
}

%new - (void)sci_addSeenButton {
    UIButton *button = [self.view viewWithTag:kSeenButtonTag];

    if (!button) {
        button = [UIButton buttonWithType:UIButtonTypeSystem];
        button.tag = kSeenButtonTag;
        button.tintColor = [UIColor whiteColor];
        button.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.35];
        button.layer.cornerRadius = 18;
        button.showsMenuAsPrimaryAction = YES;
        button.accessibilityLabel = @"Story seen options";
        [self.view addSubview:button];
    }

    // Right edge, just under the story header
    CGFloat top = self.view.safeAreaInsets.top + 64;
    button.frame = CGRectMake(CGRectGetWidth(self.view.bounds) - 36 - 12, top, 36, 36);
    [self.view bringSubviewToFront:button];

    [self sci_updateSeenButton];
}

%new - (void)sci_updateSeenButton {
    UIButton *button = [self.view viewWithTag:kSeenButtonTag];
    if (!button) return;

    BOOL noSeen = [SCIUtils getBoolPref:kNoSeenPref];
    [button setImage:[UIImage systemImageNamed:noSeen ? @"eye.slash" : @"eye"] forState:UIControlStateNormal];

    __weak typeof(self) weakSelf = self;
    UIAction *markSeen = [UIAction actionWithTitle:@"Mark this story as seen"
                                             image:[UIImage systemImageNamed:@"checkmark.circle"]
                                        identifier:nil
                                           handler:^(UIAction *action) { [weakSelf sci_markCurrentStorySeen]; }];
    if (!noSeen) markSeen.attributes = UIMenuElementAttributesDisabled;

    UIAction *toggle = [UIAction actionWithTitle:noSeen ? @"Turn seen receipts back on" : @"Hide that I viewed stories"
                                           image:[UIImage systemImageNamed:noSeen ? @"eye" : @"eye.slash"]
                                      identifier:nil
                                         handler:^(UIAction *action) { [weakSelf sci_toggleNoSeenMode]; }];

    button.menu = [UIMenu menuWithTitle:noSeen ? @"Others can't see you viewed their stories" : @"Others can see you viewed their stories"
                               children:@[markSeen, toggle]];
}

%new - (void)sci_markCurrentStorySeen {
    [SCIUtils runFeature:@"Mark story as seen" block:^{
        id item = [self currentStoryItem];
        id sectionController = [self currentlyDisplayedSectionController];
        if (!item || !sectionController) {
            [SCIUtils showErrorHUDWithDescription:@"Could not find the current story"];
            return;
        }

        allowUploadsUntil = [NSDate dateWithTimeIntervalSinceNow:10];

        forceStorySeen = YES;
        [self fullscreenSectionController:sectionController didMarkItemAsSeen:item];
        forceStorySeen = NO;

        [SCIUtils showToastForDuration:2.5 title:@"Marked story as seen"];
    }];
}

%new - (void)sci_toggleNoSeenMode {
    BOOL noSeen = ![SCIUtils getBoolPref:kNoSeenPref];
    [[NSUserDefaults standardUserDefaults] setBool:noSeen forKey:kNoSeenPref];

    [self sci_updateSeenButton];
    [SCIUtils showToastForDuration:2.5
                             title:noSeen ? @"Story seen receipts off" : @"Story seen receipts on"
                          subtitle:noSeen ? @"Use the eye button to mark a story as seen" : @"Stories you view will be marked as seen"];
}
%end
