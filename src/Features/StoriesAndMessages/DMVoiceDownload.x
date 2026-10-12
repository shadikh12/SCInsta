#import "../../InstagramHeaders.h"
#import "../../Utils.h"
#import "../../Downloader/Download.h"

// Download voice messages: long-press with finger(s) on a voice message in DMs

@interface IGAudio : NSObject
- (NSURL *)playbackURL;
- (NSURL *)fallbackURL;
@end

@interface _TtC22IGDirectAudioMessageUI24IGDirectAudioMessageCell : UICollectionViewCell
- (void)addVoiceDownloadGesture;
- (void)handleVoiceDownload:(UILongPressGestureRecognizer *)sender;
@end

static NSURL *voiceMessageURL(id cell) {
    id directAudio = [SCIUtils findIvarObjectOfClass:%c(IGDirectAudio) inObject:cell maxDepth:3];
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
