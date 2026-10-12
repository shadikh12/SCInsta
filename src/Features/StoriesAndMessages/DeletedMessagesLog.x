#import "../../InstagramHeaders.h"
#import "../../Utils.h"
#import "../../Settings/SCIListViewController.h"

// Deleted messages log: remembers messages shown in chats, and when one is unsent,
// saves it to Documents/SCInsta/deleted_messages.json (viewable from SCInsta settings)

static NSString *const kLogFile = @"deleted_messages.json";
static const NSUInteger kMaxCached = 3000;
static const NSUInteger kMaxLogged = 1000;

@interface IGDirectMessageKey : NSObject
- (NSString *)serverId;
- (NSString *)clientId;
@end

@interface IGDirectUIMessageMetadata : NSObject
- (IGDirectMessageKey *)key;
- (NSString *)senderPk;
- (NSString *)threadId;
- (NSDate *)sentDate;
@end

@interface _TtC19IGDirectMessageCell19IGDirectMessageCell : UICollectionViewCell
- (id)viewModel;
- (void)sci_captureMessage;
@end

static NSMutableDictionary<NSString *, NSDictionary *> *recentMessages;
static NSMutableArray<NSString *> *recentOrder;

static void collectTexts(UIView *view, NSMutableArray<NSString *> *texts) {
    if ([view isKindOfClass:%c(IGCoreTextView)]) {
        NSString *text = [(IGCoreTextView *)view text];
        if (text.length) [texts addObject:text];
        return;
    }

    for (UIView *subview in view.subviews) collectTexts(subview, texts);
}

static NSString *messageKindForCell(UIView *cell) {
    NSString *name = NSStringFromClass([cell class]);

    if ([name containsString:@"Audio"]) return @"[Voice message]";
    if ([name containsString:@"Media"] || [name containsString:@"Photo"] || [name containsString:@"Video"] || [name containsString:@"Visual"]) return @"[Photo/video]";
    if ([name containsString:@"Story"]) return @"[Story reply/share]";
    if ([name containsString:@"Clip"] || [name containsString:@"Reel"] || [name containsString:@"XMA"]) return @"[Shared post/reel]";
    if ([name containsString:@"Sticker"] || [name containsString:@"Animated"]) return @"[Sticker/GIF]";

    return @"[Message]";
}

static NSArray<NSString *> *idsForMessageKey(id key) {
    NSMutableArray *ids = [NSMutableArray array];

    if ([key isKindOfClass:[NSString class]]) {
        [ids addObject:key];
        return ids;
    }

    for (NSString *selName in @[@"serverId", @"clientId", @"value"]) {
        SEL sel = NSSelectorFromString(selName);
        if (![key respondsToSelector:sel]) continue;

        id value = ((id (*)(id, SEL))objc_msgSend)(key, sel);
        if ([value isKindOfClass:[NSString class]] && [value length]) [ids addObject:value];
    }

    return ids;
}

static void cacheMessage(NSDictionary *entry, NSArray<NSString *> *ids) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        recentMessages = [NSMutableDictionary dictionary];
        recentOrder = [NSMutableArray array];
    });

    for (NSString *messageId in ids) {
        if (!recentMessages[messageId]) [recentOrder addObject:messageId];
        recentMessages[messageId] = entry;
    }

    while (recentOrder.count > kMaxCached) {
        [recentMessages removeObjectForKey:recentOrder.firstObject];
        [recentOrder removeObjectAtIndex:0];
    }
}

// Called from KeepDeletedMessages.x when Instagram receives an unsend event
void SCILogDeletedMessage(id messageKey) {
    if (!messageKey || ![SCIUtils getBoolPref:@"log_deleted_messages"]) return;

    // Unsend events can arrive on background threads; the cache is only touched on main
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{ SCILogDeletedMessage(messageKey); });
        return;
    }

    [SCIUtils runFeature:@"Deleted messages log" block:^{
        NSDictionary *entry = nil;
        for (NSString *messageId in idsForMessageKey(messageKey)) {
            entry = recentMessages[messageId];
            if (entry) break;
        }
        if (!entry) return;

        NSMutableArray *log = [SCIUtils loadJSONFileWithName:kLogFile] ?: [NSMutableArray array];
        for (NSDictionary *logged in log) {
            if ([logged[@"id"] isEqualToString:entry[@"id"]]) return;
        }

        NSMutableDictionary *deleted = [entry mutableCopy];
        deleted[@"deletedAt"] = @([[NSDate date] timeIntervalSince1970]);
        [log insertObject:deleted atIndex:0];
        while (log.count > kMaxLogged) [log removeLastObject];

        [SCIUtils saveJSONObject:log toFileWithName:kLogFile];

        [SCIUtils showToastForDuration:3.0
                                 title:[NSString stringWithFormat:@"%@ unsent a message", entry[@"sender"]]
                              subtitle:entry[@"text"]];
    }];
}

static NSString *formatTimestamp(NSNumber *timestamp) {
    if (!timestamp) return @"?";

    static NSDateFormatter *formatter;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        formatter = [[NSDateFormatter alloc] init];
        [formatter setLocalizedDateFormatFromTemplate:@"yMMMdjmm"];
    });

    return [formatter stringFromDate:[NSDate dateWithTimeIntervalSince1970:timestamp.doubleValue]];
}

// Opened from SCInsta settings
void SCIShowDeletedMessagesLog(void) {
    NSArray *log = [SCIUtils loadJSONFileWithName:kLogFile] ?: @[];

    NSMutableArray *rows = [NSMutableArray array];
    for (NSDictionary *entry in log) {
        [rows addObject:@{
            @"title": entry[@"text"] ?: @"",
            @"subtitle": [NSString stringWithFormat:@"%@ · in %@\nSent %@ · Deleted %@",
                          entry[@"sender"], entry[@"thread"], formatTimestamp(entry[@"sentAt"]), formatTimestamp(entry[@"deletedAt"])]
        }];
    }

    SCIListViewController *list = [[SCIListViewController alloc] initWithTitle:@"Deleted messages" sections:@[@{@"header": @"", @"rows": rows}]];
    list.emptyText = @"No deleted messages saved yet";
    list.actionTitle = @"Clear";
    list.action = ^(SCIListViewController *vc) {
        [SCIUtils showConfirmation:^{
            [SCIUtils saveJSONObject:@[] toFileWithName:kLogFile];
            vc.sections = @[];
        } title:@"Clear deleted messages log?"];
    };

    [list show];
}

// Remember each message as its cell is shown
// Demangled name: IGDirectMessageCell.IGDirectMessageCell
%hook _TtC19IGDirectMessageCell19IGDirectMessageCell
- (void)configureWithViewModel:(id)viewModel ringViewSpecFactory:(id)factory mobileConfig:(id)config {
    %orig;

    if ([SCIUtils getBoolPref:@"log_deleted_messages"]) {
        dispatch_async(dispatch_get_main_queue(), ^{ [self sci_captureMessage]; });
    }
}

%new - (void)sci_captureMessage {
    @try {
        id viewModel = [self respondsToSelector:@selector(viewModel)] ? [self viewModel] : nil;

        IGDirectUIMessageMetadata *metadata = [SCIUtils findIvarObjectOfClass:%c(IGDirectUIMessageMetadata) inObject:(viewModel ?: self) maxDepth:3];
        if (!metadata) return;

        NSArray<NSString *> *ids = idsForMessageKey([metadata key]);
        if (!ids.count) return;

        NSMutableArray<NSString *> *texts = [NSMutableArray array];
        collectTexts(self.contentView, texts);
        NSString *text = texts.count ? [texts componentsJoinedByString:@"\n"] : messageKindForCell(self);

        IGUser *sender = [SCIUtils findIvarObjectOfClass:%c(IGUser) inObject:viewModel maxDepth:3];
        NSString *senderName = sender.username.length ? sender.username : ([metadata senderPk] ?: @"Someone");

        UIViewController *threadController = [SCIUtils nearestViewControllerForView:self];
        NSString *thread = threadController.navigationItem.title ?: threadController.title ?: [metadata threadId] ?: @"a chat";

        cacheMessage(@{
            @"id": ids.firstObject,
            @"text": text,
            @"sender": senderName,
            @"thread": thread,
            @"sentAt": @([[metadata sentDate] timeIntervalSince1970])
        }, ids);
    }
    @catch (NSException *exception) {
        NSLog(@"[SCInsta] Capturing message failed: %@", exception.reason);
    }
}
%end

// Text messages use a different configure method
// Demangled name: IGDirectTextMessageUISwift.IGDirectTextMessageCell
%hook _TtC26IGDirectTextMessageUISwift23IGDirectTextMessageCell
- (void)configureWithViewModel:(id)viewModel userSession:(id)session ringViewSpecFactory:(id)factory {
    %orig;

    if ([SCIUtils getBoolPref:@"log_deleted_messages"]) {
        dispatch_async(dispatch_get_main_queue(), ^{ [(id)self sci_captureMessage]; });
    }
}
%end
