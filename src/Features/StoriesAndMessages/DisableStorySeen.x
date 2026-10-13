#import "../../Utils.h"
#import "../../InstagramHeaders.h"
#import "../../Settings/SCIListViewController.h"

// Story seen receipts
// - "Disable story seen receipt" (no_seen_receipt) stops stories from being marked as seen
// - A button in the story viewer switches it on/off, and marks the current story as seen on demand

static NSString *const kNoSeenPref = @"no_seen_receipt";
static const NSInteger kSeenButtonTag = 0x5C1F0D;
static const CGFloat kButtonSize = 32;
static NSString *const kButtonXPref = @"story_button_x";
static NSString *const kButtonYPref = @"story_button_y";

// Keeps the button fully on screen and out of the status bar / home indicator areas
static CGPoint clampedButtonCenter(CGPoint center, UIView *container) {
    UIEdgeInsets insets = container.safeAreaInsets;
    CGFloat half = kButtonSize / 2 + 4;
    CGSize size = container.bounds.size;

    center.x = MIN(MAX(center.x, insets.left + half), size.width - insets.right - half);
    center.y = MIN(MAX(center.y, insets.top + half), size.height - insets.bottom - half);

    return center;
}

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
- (void)sci_storyButtonTapped:(UIButton *)button;
- (void)sci_storyButtonDragged:(UIPanGestureRecognizer *)pan;
- (NSArray<NSDictionary *> *)sci_currentStoryMentions;
- (void)sci_showMentions;
@end

@interface IGAPIMediaDict : NSObject
- (NSArray *)reelMentions;
@end

// Value of a getter if the object has it (IG model getters vary between versions)
static id valueFor(id obj, NSString *key) {
    SEL sel = NSSelectorFromString(key);
    if (![obj respondsToSelector:sel]) return nil;

    return ((id (*)(id, SEL))objc_msgSend)(obj, sel);
}

static double doubleFor(id obj, NSString *key) {
    SEL sel = NSSelectorFromString(key);
    if (![obj respondsToSelector:sel]) return 0;

    NSMethodSignature *signature = [obj methodSignatureForSelector:sel];
    const char *type = signature.methodReturnType;
    if (type[0] == '@') return [valueFor(obj, key) doubleValue];
    if (type[0] == 'd') return ((double (*)(id, SEL))objc_msgSend)(obj, sel);
    if (type[0] == 'f') return ((float (*)(id, SEL))objc_msgSend)(obj, sel);

    return 0;
}

static BOOL storyButtonEnabled(void) {
    return [SCIUtils getBoolPref:@"story_seen_button"] || [SCIUtils getBoolPref:@"story_mentions"];
}

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

    if (storyButtonEnabled()) {
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
        button.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.3];
        button.layer.cornerRadius = kButtonSize / 2;
        button.accessibilityLabel = @"Story options";
        button.accessibilityHint = @"Drag to move";
        [button addTarget:self action:@selector(sci_storyButtonTapped:) forControlEvents:UIControlEventTouchUpInside];

        // Drag the button anywhere; the position is remembered
        UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(sci_storyButtonDragged:)];
        [button addGestureRecognizer:pan];

        [self.view addSubview:button];
    }

    // Saved position is the button centre, as a fraction of the screen
    NSNumber *savedX = [[NSUserDefaults standardUserDefaults] objectForKey:kButtonXPref];
    NSNumber *savedY = [[NSUserDefaults standardUserDefaults] objectForKey:kButtonYPref];
    CGSize size = self.view.bounds.size;

    BOOL dragging = NO;
    for (UIGestureRecognizer *gesture in button.gestureRecognizers) {
        if (gesture.state == UIGestureRecognizerStateBegan || gesture.state == UIGestureRecognizerStateChanged) dragging = YES;
    }

    button.bounds = CGRectMake(0, 0, kButtonSize, kButtonSize);
    if (!dragging) {
        button.center = clampedButtonCenter(CGPointMake((savedX ? savedX.doubleValue : 0.93) * size.width,
                                                        (savedY ? savedY.doubleValue : 0.36) * size.height), self.view);
    }
    [self.view bringSubviewToFront:button];

    BOOL noSeen = [SCIUtils getBoolPref:kNoSeenPref];
    UIImageSymbolConfiguration *config = [UIImageSymbolConfiguration configurationWithPointSize:14 weight:UIImageSymbolWeightSemibold];
    [button setImage:[UIImage systemImageNamed:noSeen ? @"eye.slash" : @"eye" withConfiguration:config] forState:UIControlStateNormal];
}

%new - (void)sci_updateSeenButton {
    [self sci_addSeenButton];
}

%new - (void)sci_storyButtonDragged:(UIPanGestureRecognizer *)pan {
    UIView *button = pan.view;
    CGPoint translation = [pan translationInView:self.view];

    button.center = clampedButtonCenter(CGPointMake(button.center.x + translation.x, button.center.y + translation.y), self.view);
    [pan setTranslation:CGPointZero inView:self.view];

    if (pan.state == UIGestureRecognizerStateEnded || pan.state == UIGestureRecognizerStateCancelled) {
        CGSize size = self.view.bounds.size;
        [[NSUserDefaults standardUserDefaults] setDouble:button.center.x / size.width forKey:kButtonXPref];
        [[NSUserDefaults standardUserDefaults] setDouble:button.center.y / size.height forKey:kButtonYPref];
    }
}

%new - (void)sci_storyButtonTapped:(UIButton *)button {
    BOOL noSeen = [SCIUtils getBoolPref:kNoSeenPref];

    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:nil
                                                                   message:[SCIUtils getBoolPref:@"story_seen_button"]
                                                                           ? (noSeen ? @"Others can't see you viewed their stories" : @"Others can see you viewed their stories")
                                                                           : nil
                                                            preferredStyle:UIAlertControllerStyleActionSheet];

    if ([SCIUtils getBoolPref:@"story_seen_button"]) {
        if (noSeen) {
            [sheet addAction:[UIAlertAction actionWithTitle:@"Mark this story as seen" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
                [self sci_markCurrentStorySeen];
            }]];
        }

        [sheet addAction:[UIAlertAction actionWithTitle:noSeen ? @"Turn seen receipts back on" : @"Hide that I viewed stories" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            [self sci_toggleNoSeenMode];
        }]];
    }

    if ([SCIUtils getBoolPref:@"story_mentions"]) {
        NSArray *mentions = [self sci_currentStoryMentions];
        NSUInteger hidden = [[mentions filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"hidden == YES"]] count];

        if (mentions.count) {
            NSString *title = hidden ? [NSString stringWithFormat:@"Mentions: %lu (%lu hidden)", (unsigned long)mentions.count, (unsigned long)hidden]
                                     : [NSString stringWithFormat:@"Mentions: %lu", (unsigned long)mentions.count];

            [sheet addAction:[UIAlertAction actionWithTitle:title style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
                [self sci_showMentions];
            }]];
        }
        else {
            UIAlertAction *none = [UIAlertAction actionWithTitle:@"No mentions in this story" style:UIAlertActionStyleDefault handler:nil];
            none.enabled = NO;
            [sheet addAction:none];
        }
    }

    [sheet addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];

    sheet.popoverPresentationController.sourceView = button;
    sheet.popoverPresentationController.sourceRect = button.bounds;
    [self presentViewController:sheet animated:YES completion:nil];
}

// Everyone mentioned in the current story, including mentions hidden by making them tiny,
// placing them off-screen, or covering them. @[@{@"username", @"name", @"hidden"}]
%new - (NSArray<NSDictionary *> *)sci_currentStoryMentions {
    NSMutableArray *result = [NSMutableArray array];

    @try {
        id item = [self currentStoryItem];
        IGAPIMediaDict *mediaDict = [SCIUtils findIvarObjectOfClass:%c(IGAPIMediaDict) inObject:item maxDepth:3];

        NSArray *mentions = [mediaDict respondsToSelector:@selector(reelMentions)] ? [mediaDict reelMentions] : nil;
        NSMutableSet *seen = [NSMutableSet set];

        for (id mention in mentions) {
            id user = valueFor(mention, @"user");
            NSString *username = valueFor(user, @"username");
            if (!username.length || [seen containsObject:username]) continue;
            [seen addObject:username];

            double x = doubleFor(mention, @"x"), y = doubleFor(mention, @"y");
            double width = doubleFor(mention, @"width"), height = doubleFor(mention, @"height");

            // Positions are fractions of the story size (centre point)
            BOOL tiny = width * height < 0.0015;
            BOOL offscreen = x < 0 || x > 1 || y < 0 || y > 1;
            BOOL notSticker = [valueFor(mention, @"isSticker") respondsToSelector:@selector(boolValue)] && ![valueFor(mention, @"isSticker") boolValue];

            [result addObject:@{
                @"username": username,
                @"name": valueFor(user, @"fullName") ?: @"",
                @"hidden": @(tiny || offscreen),
                @"text": @(notSticker)
            }];
        }
    }
    @catch (NSException *exception) {
        NSLog(@"[SCInsta] Reading story mentions failed: %@", exception.reason);
    }

    return result;
}

%new - (void)sci_showMentions {
    NSArray *mentions = [self sci_currentStoryMentions];

    NSMutableArray *rows = [NSMutableArray array];
    for (NSDictionary *mention in mentions) {
        NSMutableArray *details = [NSMutableArray array];
        if ([mention[@"name"] length]) [details addObject:mention[@"name"]];
        if ([mention[@"hidden"] boolValue]) [details addObject:@"Hidden mention"];

        [rows addObject:@{
            @"title": [@"@" stringByAppendingString:mention[@"username"]],
            @"subtitle": [details componentsJoinedByString:@" · "],
            @"url": [@"instagram://user?username=" stringByAppendingString:mention[@"username"]]
        }];
    }

    SCIListViewController *list = [[SCIListViewController alloc] initWithTitle:@"Mentioned in this story" sections:@[@{@"header": @"", @"rows": rows}]];
    list.emptyText = @"No one is mentioned in this story";
    [list show];
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
