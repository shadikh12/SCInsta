#import "../../Utils.h"
#import "../../InstagramHeaders.h"
#import "../../Settings/SCIListViewController.h"

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
    NSMutableArray<UIMenuElement *> *children = [NSMutableArray array];

    if ([SCIUtils getBoolPref:@"story_seen_button"]) {
        UIAction *markSeen = [UIAction actionWithTitle:@"Mark this story as seen"
                                                 image:[UIImage systemImageNamed:@"checkmark.circle"]
                                            identifier:nil
                                               handler:^(UIAction *action) { [weakSelf sci_markCurrentStorySeen]; }];
        if (!noSeen) markSeen.attributes = UIMenuElementAttributesDisabled;

        UIAction *toggle = [UIAction actionWithTitle:noSeen ? @"Turn seen receipts back on" : @"Hide that I viewed stories"
                                               image:[UIImage systemImageNamed:noSeen ? @"eye" : @"eye.slash"]
                                          identifier:nil
                                             handler:^(UIAction *action) { [weakSelf sci_toggleNoSeenMode]; }];

        [children addObject:[UIMenu menuWithTitle:noSeen ? @"Others can't see you viewed their stories" : @"Others can see you viewed their stories"
                                            image:nil identifier:nil options:UIMenuOptionsDisplayInline children:@[markSeen, toggle]]];
    }

    // Built when the menu opens, so it matches the story currently on screen
    if ([SCIUtils getBoolPref:@"story_mentions"]) {
        [children addObject:[UIDeferredMenuElement elementWithUncachedProvider:^(void (^completion)(NSArray<UIMenuElement *> *)) {
            NSArray *mentions = [weakSelf sci_currentStoryMentions];
            NSUInteger hidden = [[mentions filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"hidden == YES"]] count];

            NSString *title = !mentions.count ? @"No mentions in this story"
                            : hidden ? [NSString stringWithFormat:@"Mentions: %lu (%lu hidden)", (unsigned long)mentions.count, (unsigned long)hidden]
                            : [NSString stringWithFormat:@"Mentions: %lu", (unsigned long)mentions.count];

            UIAction *show = [UIAction actionWithTitle:title
                                                 image:[UIImage systemImageNamed:@"at"]
                                            identifier:nil
                                               handler:^(UIAction *action) { [weakSelf sci_showMentions]; }];
            if (!mentions.count) show.attributes = UIMenuElementAttributesDisabled;

            completion(@[[UIMenu menuWithTitle:@"" image:nil identifier:nil options:UIMenuOptionsDisplayInline children:@[show]]]);
        }]];
    }

    button.menu = [UIMenu menuWithChildren:children];
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
