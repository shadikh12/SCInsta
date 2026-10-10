#import "../../Utils.h"
#import "../../InstagramHeaders.h"

%hook IGDirectRealtimeIrisThreadDelta
+ (id)removeItemWithMessageId:(id)arg1 {
    if ([SCIUtils getBoolPref:@"keep_deleted_message"]) {
        arg1 = NULL;
    }

    return %orig(arg1);
}

// Newer IG versions: remove deltas are created elsewhere, so clear the removed
// message id before the delta is handled (same effect as the hook above)
- (BOOL)matchBooleanAddItem:(id)addItem removeItem:(id)removeItem replaceItem:(id)replaceItem mutateItem:(id)mutateItem mutateThreadMetadata:(id)mutateThreadMetadata markSeen:(id)markSeen replaceThreadMetadata:(id)replaceThreadMetadata removeThread:(id)removeThread markSeenDisappearingMessages:(id)markSeenDisappearingMessages refetchItem:(id)refetchItem {
    if ([SCIUtils getBoolPref:@"keep_deleted_message"] && [SCIUtils getIvarForObj:self name:"_removeItem_messageId"]) {
        NSLog(@"[SCInsta] Keeping deleted message");

        [SCIUtils setIvarForObj:self name:"_removeItem_messageId" value:nil];
    }

    return %orig;
}
%end

%hook IGDirectRealtimeIrisThreadDeltaMatcher
+ (id)match:(id)delta addItem:(id)addItem removeItem:(id)removeItem replaceItem:(id)replaceItem mutateItem:(id)mutateItem mutateThreadMetadata:(id)mutateThreadMetadata markSeen:(id)markSeen replaceThreadMetadata:(id)replaceThreadMetadata removeThread:(id)removeThread markSeenDisappearingMessages:(id)markSeenDisappearingMessages refetchItem:(id)refetchItem {
    if ([SCIUtils getBoolPref:@"keep_deleted_message"] && [SCIUtils getIvarForObj:delta name:"_removeItem_messageId"]) {
        NSLog(@"[SCInsta] Keeping deleted message");

        [SCIUtils setIvarForObj:delta name:"_removeItem_messageId" value:nil];
    }

    return %orig;
}
%end

%hook IGDirectMessageUpdate
+ (id)removeMessageWithMessageId:(id)arg1{
    if ([SCIUtils getBoolPref:@"keep_deleted_message"]) {
        arg1 = NULL;
    }

    return %orig(arg1);
}
%end
