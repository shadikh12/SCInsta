#import <objc/runtime.h>
#import "../../InstagramHeaders.h"
#import "../../Utils.h"
#import "../../Downloader/Download.h"

// Download voice messages: long-press with finger(s) on a voice message in DMs

@interface IGAudio : NSObject
- (NSURL *)playbackURL;
- (NSURL *)fallbackURL;
@end

// Breadth-first search through object ivars for the first object of a given class.
// The audio model lives in Swift view models whose layout changes between IG versions
static id findIvarObjectOfClass(id root, Class target, NSInteger maxDepth) {
    if (!root || !target) return nil;

    NSMutableArray *level = [NSMutableArray arrayWithObject:root];
    NSHashTable *visited = [NSHashTable weakObjectsHashTable];

    for (NSInteger depth = 0; depth <= maxDepth && level.count; depth++) {
        NSMutableArray *next = [NSMutableArray array];

        for (id obj in level) {
            if ([visited containsObject:obj]) continue;
            [visited addObject:obj];

            if ([obj isKindOfClass:target]) return obj;

            for (Class cls = object_getClass(obj); cls && cls != [NSObject class] && cls != [UIView class] && cls != [UICollectionViewCell class]; cls = class_getSuperclass(cls)) {
                unsigned int count = 0;
                Ivar *ivars = class_copyIvarList(cls, &count);

                for (unsigned int i = 0; i < count; i++) {
                    const char *type = ivar_getTypeEncoding(ivars[i]);
                    if (!type || type[0] != '@') continue;

                    id value = object_getIvar(obj, ivars[i]);
                    if (!value || [value isKindOfClass:[UIView class]] || [value isKindOfClass:[UIViewController class]]) continue;

                    [next addObject:value];
                }

                free(ivars);
            }
        }

        level = next;
    }

    return nil;
}

static NSURL *voiceMessageURL(id cell) {
    id directAudio = findIvarObjectOfClass(cell, %c(IGDirectAudio), 3);
    if (!directAudio) return nil;

    IGAudio *serverAudio = [SCIUtils getIvarForObj:directAudio name:"_server_audio"];
    NSURL *url = [serverAudio playbackURL] ?: [serverAudio fallbackURL];

    // Messages you just sent may only exist locally
    return url ?: [SCIUtils getIvarForObj:directAudio name:"_pending_fileURL"];
}

// Demangled name: IGDirectAudioMessageUI.IGDirectAudioMessageCell
%hook _TtC22IGDirectAudioMessageUI24IGDirectAudioMessageCell
- (void)didMoveToSuperview {
    %orig;

    if ([SCIUtils getBoolPref:@"dw_voice_messages"]) {
        [self addVoiceDownloadGesture];
    }
}

%new - (void)addVoiceDownloadGesture {
    for (UIGestureRecognizer *gesture in [(UIView *)self gestureRecognizers]) {
        if ([gesture.name isEqualToString:@"SCIVoiceDownload"]) return;
    }

    UILongPressGestureRecognizer *longPress = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(handleVoiceDownload:)];
    longPress.name = @"SCIVoiceDownload";
    longPress.minimumPressDuration = [SCIUtils getDoublePref:@"dw_finger_duration"];
    longPress.numberOfTouchesRequired = [SCIUtils getDoublePref:@"dw_finger_count"];

    [(UIView *)self addGestureRecognizer:longPress];
}

%new - (void)handleVoiceDownload:(UILongPressGestureRecognizer *)sender {
    [SCIUtils runFeature:@"Download voice message" block:^{
        if (sender.state != UIGestureRecognizerStateBegan) return;

        NSURL *url = voiceMessageURL(self);
        if (!url) {
            [SCIUtils showErrorHUDWithDescription:@"Could not find this voice message's audio"];
            return;
        }

        static SCIDownloadDelegate *audioDownloadDelegate;
        static dispatch_once_t once;
        dispatch_once(&once, ^{
            audioDownloadDelegate = [[SCIDownloadDelegate alloc] initWithAction:share showProgress:YES];
        });

        NSString *extension = url.pathExtension.length ? url.pathExtension : @"m4a";
        [audioDownloadDelegate downloadFileWithURL:url fileExtension:extension hudLabel:@"Downloading voice message"];
    }];
}
%end
