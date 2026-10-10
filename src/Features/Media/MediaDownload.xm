#import "../../InstagramHeaders.h"
#import "../../Utils.h"
#import "../../Downloader/Download.h"
#import "../../Downloader/BatchDownload.h"

static SCIDownloadDelegate *imageDownloadDelegate;
static SCIDownloadDelegate *videoDownloadDelegate;

static void initDownloaders () {
    // Init downloaders only once
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        imageDownloadDelegate = [[SCIDownloadDelegate alloc] initWithAction:quickLook showProgress:NO];
        videoDownloadDelegate = [[SCIDownloadDelegate alloc] initWithAction:share showProgress:YES];
    });
}

// Action sheet with one button per choice: @[@[title, block], ...]
static void presentDownloadChoices(NSString *title, NSArray<NSArray *> *choices) {
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:title message:nil preferredStyle:UIAlertControllerStyleActionSheet];

    for (NSArray *choice in choices) {
        void (^handler)(void) = choice[1];
        [sheet addAction:[UIAlertAction actionWithTitle:choice[0] style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            [SCIUtils runFeature:title block:handler];
        }]];
    }
    [sheet addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];

    UIViewController *presenter = topMostController();
    sheet.popoverPresentationController.sourceView = presenter.view;
    sheet.popoverPresentationController.sourceRect = CGRectMake(CGRectGetMidX(presenter.view.bounds), CGRectGetMidY(presenter.view.bounds), 1, 1);

    [presenter presentViewController:sheet animated:YES completion:nil];
}

// Urls of every item (photo or video) in a carousel post, or nil if it's not a carousel
static NSArray<NSURL *> *carouselMediaUrls(IGMedia *media) {
    if (![media respondsToSelector:@selector(carouselMedia)]) return nil;

    // The cell may hold either the carousel itself or one of its items
    NSArray<IGMedia *> *items = [media carouselMedia];
    if (!items.count && [media respondsToSelector:@selector(carouselParent)]) {
        items = [[media carouselParent] carouselMedia];
    }

    NSMutableArray<NSURL *> *urls = [NSMutableArray array];
    for (IGMedia *item in items) {
        NSURL *url = item.video ? [SCIUtils getVideoUrlForMedia:item] : [SCIUtils getPhotoUrlForMedia:item];
        if (url) [urls addObject:url];
    }

    return urls;
}

/* * Feed * */

// Download feed images
%hook IGFeedPhotoView
- (void)didMoveToSuperview {
    %orig;

    if ([SCIUtils getBoolPref:@"dw_feed_posts"]) {
        [self addLongPressGestureRecognizer];
    }

    return;
}
%new - (void)addLongPressGestureRecognizer {
    NSLog(@"[SCInsta] Adding feed photo download long press gesture recognizer");

    UILongPressGestureRecognizer *longPress = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(handleLongPress:)];
    longPress.minimumPressDuration = [SCIUtils getDoublePref:@"dw_finger_duration"];
    longPress.numberOfTouchesRequired = [SCIUtils getDoublePref:@"dw_finger_count"];

    [self addGestureRecognizer:longPress];
}
%new - (void)handleLongPress:(UILongPressGestureRecognizer *)sender {
    [SCIUtils runFeature:@"Download post photo" block:^{
        if (sender.state != UIGestureRecognizerStateBegan) return;

        // Get photo instance
        IGPhoto *photo;

        if ([self.delegate isKindOfClass:%c(IGFeedItemPhotoCell)]) {
            IGFeedItemPhotoCellConfiguration *_configuration = MSHookIvar<IGFeedItemPhotoCellConfiguration *>(self.delegate, "_configuration");
            if (!_configuration) return;

            photo = MSHookIvar<IGPhoto *>(_configuration, "_photo");
        }
        else if ([self.delegate isKindOfClass:%c(IGFeedItemPagePhotoCell)]) {
            IGFeedItemPagePhotoCell *pagePhotoCell = self.delegate;

            photo = pagePhotoCell.pagePhotoPost.photo;
        }

        NSURL *photoUrl = [SCIUtils getPhotoUrl:photo];

        // Newer IG versions (carousel cells are Swift): use the url of the displayed image
        if (!photoUrl) {
            IGImageProgressView *_photoImageView = [SCIUtils getIvarForObj:self name:"_photoImageView"];
            if ([_photoImageView respondsToSelector:@selector(imageSpecifier)]) {
                photoUrl = _photoImageView.imageSpecifier.url;
            }
        }

        if (!photoUrl) {
            [SCIUtils showErrorHUDWithDescription:@"Could not extract photo url from post"];

            return;
        }

        // Download image & show in share menu
        void (^downloadThis)(void) = ^{
            initDownloaders();
            [imageDownloadDelegate downloadFileWithURL:photoUrl
                                         fileExtension:[[photoUrl lastPathComponent]pathExtension]
                                              hudLabel:nil];
        };

        // Carousel posts: offer to download every item at once
        IGMedia *post = [SCIUtils getIvarForObj:self.delegate name:"_post"];
        NSArray<NSURL *> *carouselUrls = carouselMediaUrls(post);
        if (carouselUrls.count < 2) {
            downloadThis();
            return;
        }

        presentDownloadChoices(@"Download", @[
            @[@"This photo", downloadThis],
            @[[NSString stringWithFormat:@"All %lu items", (unsigned long)carouselUrls.count], ^{ [SCIBatchDownload downloadAndShareURLs:carouselUrls]; }]
        ]);
    }];
}
%end

// Download feed videos
%hook IGModernFeedVideoCell.IGModernFeedVideoCell
- (void)didMoveToSuperview {
    %orig;

    if ([SCIUtils getBoolPref:@"dw_feed_posts"]) {
        [self addLongPressGestureRecognizer];
    }

    return;
}
%new - (void)addLongPressGestureRecognizer {
    NSLog(@"[SCInsta] Adding feed video download long press gesture recognizer");

    UILongPressGestureRecognizer *longPress = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(handleLongPress:)];
    longPress.minimumPressDuration = [SCIUtils getDoublePref:@"dw_finger_duration"];
    longPress.numberOfTouchesRequired = [SCIUtils getDoublePref:@"dw_finger_count"];

    [self addGestureRecognizer:longPress];
}
%new - (void)handleLongPress:(UILongPressGestureRecognizer *)sender {
    [SCIUtils runFeature:@"Download post video" block:^{
        if (sender.state != UIGestureRecognizerStateBegan) return;

        NSURL *videoUrl = [SCIUtils getVideoUrlForMedia:[self mediaCellFeedItem]];
        if (!videoUrl) {
            [SCIUtils showErrorHUDWithDescription:@"Could not extract video url from post"];

            return;
        }

        // Download video & show in share menu
        initDownloaders();
        [videoDownloadDelegate downloadFileWithURL:videoUrl
                                     fileExtension:[[videoUrl lastPathComponent] pathExtension]
                                          hudLabel:nil];
    }];
}
%end


/* * Reels * */

// Download reels (photos)
%hook IGSundialViewerPhotoView
- (void)didMoveToSuperview {
    %orig;

    if ([SCIUtils getBoolPref:@"dw_reels"]) {
        [self addLongPressGestureRecognizer];
    }

    return;
}
%new - (void)addLongPressGestureRecognizer {
    NSLog(@"[SCInsta] Adding reels photo download long press gesture recognizer");

    UILongPressGestureRecognizer *longPress = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(handleLongPress:)];
    longPress.minimumPressDuration = [SCIUtils getDoublePref:@"dw_finger_duration"];
    longPress.numberOfTouchesRequired = [SCIUtils getDoublePref:@"dw_finger_count"];

    [self addGestureRecognizer:longPress];
}
%new - (void)handleLongPress:(UILongPressGestureRecognizer *)sender {
    [SCIUtils runFeature:@"Download reel photo" block:^{
        if (sender.state != UIGestureRecognizerStateBegan) return;

        IGPhoto *_photo = MSHookIvar<IGPhoto *>(self, "_photo");

        NSURL *photoUrl = [SCIUtils getPhotoUrl:_photo];
        if (!photoUrl) {
            [SCIUtils showErrorHUDWithDescription:@"Could not extract photo url from reel"];

            return;
        }

        // Download image & show in share menu
        initDownloaders();
        [imageDownloadDelegate downloadFileWithURL:photoUrl
                                     fileExtension:[[photoUrl lastPathComponent]pathExtension]
                                          hudLabel:nil];
    }];
}
%end

// Download reels (videos)
%hook IGSundialViewerVideoCell
- (void)didMoveToSuperview {
    %orig;

    if ([SCIUtils getBoolPref:@"dw_reels"]) {
        [self addLongPressGestureRecognizer];
    }

    return;
}
%new - (void)addLongPressGestureRecognizer {
    NSLog(@"[SCInsta] Adding reels video download long press gesture recognizer");

    UILongPressGestureRecognizer *longPress = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(handleLongPress:)];
    longPress.minimumPressDuration = [SCIUtils getDoublePref:@"dw_finger_duration"];
    longPress.numberOfTouchesRequired = [SCIUtils getDoublePref:@"dw_finger_count"];

    [self addGestureRecognizer:longPress];
}
%new - (void)handleLongPress:(UILongPressGestureRecognizer *)sender {
    [SCIUtils runFeature:@"Download reel video" block:^{
        if (sender.state != UIGestureRecognizerStateBegan) return;
    
        // Get reel media (newer IG versions removed the -video getter)
        IGMedia *media = [self respondsToSelector:@selector(video)]
                       ? self.video
                       : [SCIUtils getIvarForObj:self name:"_mediaPassthrough"];

        NSURL *videoUrl = [SCIUtils getVideoUrlForMedia:media];
        if (!videoUrl) {
            [SCIUtils showErrorHUDWithDescription:@"Could not extract video url from reel"];

            return;
        }

        // Download video & show in share menu
        void (^downloadVideo)(void) = ^{
            initDownloaders();
            [videoDownloadDelegate downloadFileWithURL:videoUrl
                                         fileExtension:[[videoUrl lastPathComponent] pathExtension]
                                              hudLabel:nil];
        };

        if (![SCIUtils getBoolPref:@"dw_reel_audio"]) {
            downloadVideo();
            return;
        }

        presentDownloadChoices(@"Download reel", @[
            @[@"Video", downloadVideo],
            @[@"Audio only", ^{ [SCIBatchDownload downloadAudioFromVideoURL:videoUrl]; }]
        ]);
    }];
}
%end


/* * Stories * */

// Download story (images)
%hook IGStoryPhotoView
- (void)didMoveToSuperview {
    %orig;

    if ([SCIUtils getBoolPref:@"dw_story"]) {
        [self addLongPressGestureRecognizer];
    }

    return;
}
%new - (void)addLongPressGestureRecognizer {
    NSLog(@"[SCInsta] Adding story photo download long press gesture recognizer");

    UILongPressGestureRecognizer *longPress = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(handleLongPress:)];
    longPress.minimumPressDuration = [SCIUtils getDoublePref:@"dw_finger_duration"];
    longPress.numberOfTouchesRequired = [SCIUtils getDoublePref:@"dw_finger_count"];

    [self addGestureRecognizer:longPress];
}
%new - (void)handleLongPress:(UILongPressGestureRecognizer *)sender {
    [SCIUtils runFeature:@"Download story photo" block:^{
        if (sender.state != UIGestureRecognizerStateBegan) return;

        NSURL *photoUrl = [SCIUtils getPhotoUrlForMedia:[self item]];
        if (!photoUrl) {
            [SCIUtils showErrorHUDWithDescription:@"Could not extract photo url from story"];
        
            return;
        }

        // Download image & show in share menu
        initDownloaders();
        [imageDownloadDelegate downloadFileWithURL:photoUrl
                                     fileExtension:[[photoUrl lastPathComponent]pathExtension]
                                          hudLabel:nil];
    }];
}
%end

// Download story (videos)
%hook IGStoryModernVideoView
- (void)didMoveToSuperview {
    %orig;

    if ([SCIUtils getBoolPref:@"dw_story"]) {
        [self addLongPressGestureRecognizer];
    }

    return;
}
%new - (void)addLongPressGestureRecognizer {
    //NSLog(@"[SCInsta] Adding story video download long press gesture recognizer");

    UILongPressGestureRecognizer *longPress = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(handleLongPress:)];
    longPress.minimumPressDuration = [SCIUtils getDoublePref:@"dw_finger_duration"];
    longPress.numberOfTouchesRequired = [SCIUtils getDoublePref:@"dw_finger_count"];

    [self addGestureRecognizer:longPress];
}
%new - (void)handleLongPress:(UILongPressGestureRecognizer *)sender {
    [SCIUtils runFeature:@"Download story video" block:^{
        if (sender.state != UIGestureRecognizerStateBegan) return;

        NSURL *videoUrl = [SCIUtils getVideoUrlForMedia:self.item];
    
        if (!videoUrl) {
            [SCIUtils showErrorHUDWithDescription:@"Could not extract video url from story"];

            return;
        }

        // Download video & show in share menu
        initDownloaders();
        [videoDownloadDelegate downloadFileWithURL:videoUrl
                                     fileExtension:[[videoUrl lastPathComponent] pathExtension]
                                          hudLabel:nil];
    }];
}
%end

// Download story (videos, legacy)
%hook IGStoryVideoView
- (void)didMoveToSuperview {
    %orig;

    if ([SCIUtils getBoolPref:@"dw_story"]) {
        [self addLongPressGestureRecognizer];
    }

    return;
}
%new - (void)addLongPressGestureRecognizer {
    //NSLog(@"[SCInsta] Adding story video download long press gesture recognizer");

    UILongPressGestureRecognizer *longPress = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(handleLongPress:)];
    longPress.minimumPressDuration = [SCIUtils getDoublePref:@"dw_finger_duration"];
    longPress.numberOfTouchesRequired = [SCIUtils getDoublePref:@"dw_finger_count"];

    [self addGestureRecognizer:longPress];
}
%new - (void)handleLongPress:(UILongPressGestureRecognizer *)sender {
    [SCIUtils runFeature:@"Download story video" block:^{
        if (sender.state != UIGestureRecognizerStateBegan) return;

        NSURL *videoUrl;

        IGStoryFullscreenSectionController *captionDelegate = self.captionDelegate;
        if (captionDelegate) {
            videoUrl = [SCIUtils getVideoUrlForMedia:captionDelegate.currentStoryItem];
        }
        else {
            // Direct messages video player
            id parentVC = [SCIUtils nearestViewControllerForView:self];
            if (!parentVC || ![parentVC isKindOfClass:%c(IGDirectVisualMessageViewerController)]) return;

            IGDirectVisualMessageViewerViewModeAwareDataSource *_dataSource = MSHookIvar<IGDirectVisualMessageViewerViewModeAwareDataSource *>(parentVC, "_dataSource");
            if (!_dataSource) return;
        
            IGDirectVisualMessage *_currentMessage = MSHookIvar<IGDirectVisualMessage *>(_dataSource, "_currentMessage"); 
            if (!_currentMessage) return;
        
            IGVideo *rawVideo = _currentMessage.rawVideo;
            if (!rawVideo) return;
        
            videoUrl = [SCIUtils getVideoUrl:rawVideo];
        }
    
        if (!videoUrl) {
            [SCIUtils showErrorHUDWithDescription:@"Could not extract video url from story"];

            return;
        }

        // Download video & show in share menu
        initDownloaders();
        [videoDownloadDelegate downloadFileWithURL:videoUrl
                                     fileExtension:[[videoUrl lastPathComponent] pathExtension]
                                          hudLabel:nil];
    }];
}
%end


/* * Profile pictures * */

%hook IGProfilePictureImageView
- (void)didMoveToSuperview {
    %orig;

    if ([SCIUtils getBoolPref:@"save_profile"]) {
        [self addLongPressGestureRecognizer];
    }

    return;
}
%new - (void)addLongPressGestureRecognizer {
    NSLog(@"[SCInsta] Adding profile picture long press gesture recognizer");

    UILongPressGestureRecognizer *longPress = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(handleLongPress:)];
    [self addGestureRecognizer:longPress];
}
%new - (void)handleLongPress:(UILongPressGestureRecognizer *)sender {
    [SCIUtils runFeature:@"Save profile picture" block:^{
        if (sender.state != UIGestureRecognizerStateBegan) return;

        IGImageView *_imageView = MSHookIvar<IGImageView *>(self, "_imageView");
        if (!_imageView) return;
    
        IGImageSpecifier *imageSpecifier = _imageView.imageSpecifier;
        if (!imageSpecifier) return;

        NSURL *imageUrl = imageSpecifier.url;
        if (!imageUrl) return;

        // Download image & preview in quick look
        initDownloaders();
        [imageDownloadDelegate downloadFileWithURL:imageUrl
                                     fileExtension:[[imageUrl lastPathComponent] pathExtension]
                                          hudLabel:@"Loading"];
    }];
}
%end