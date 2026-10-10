#import <AVFoundation/AVFoundation.h>
#import "BatchDownload.h"
#import "../Utils.h"

@implementation SCIBatchDownload

static NSURL *cacheFileURL(NSString *extension) {
    NSString *cacheDir = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES).firstObject;
    NSString *name = [NSString stringWithFormat:@"%@.%@", NSUUID.UUID.UUIDString, extension.length ? extension : @"jpg"];

    return [[NSURL fileURLWithPath:cacheDir] URLByAppendingPathComponent:name];
}

static void shareFiles(NSArray<NSURL *> *files) {
    UIActivityViewController *acVC = [[UIActivityViewController alloc] initWithActivityItems:files applicationActivities:nil];
    if (is_iPad()) {
        acVC.popoverPresentationController.sourceView = topMostController().view;
        acVC.popoverPresentationController.sourceRect = CGRectMake(topMostController().view.bounds.size.width / 2.0, topMostController().view.bounds.size.height / 2.0, 1.0, 1.0);
    }
    [topMostController() presentViewController:acVC animated:YES completion:nil];
}

+ (void)downloadAndShareURLs:(NSArray<NSURL *> *)urls {
    if (!urls.count) return;

    JGProgressHUD *hud = [[JGProgressHUD alloc] init];
    hud.textLabel.text = [NSString stringWithFormat:@"Downloading 0/%lu", (unsigned long)urls.count];
    [hud showInView:topMostController().view];

    NSMutableArray<NSURL *> *files = [NSMutableArray array];
    __block NSUInteger finished = 0;
    __block NSUInteger failed = 0;

    // Downloads run in parallel; results are kept in the original order
    NSMutableArray *results = [NSMutableArray arrayWithCapacity:urls.count];
    for (NSUInteger i = 0; i < urls.count; i++) [results addObject:[NSNull null]];

    [urls enumerateObjectsUsingBlock:^(NSURL *url, NSUInteger index, BOOL *stop) {
        NSURLSessionDownloadTask *task = [[NSURLSession sharedSession] downloadTaskWithURL:url completionHandler:^(NSURL *location, NSURLResponse *response, NSError *error) {
            NSURL *destination = nil;
            if (location && !error) {
                destination = cacheFileURL(url.pathExtension);
                if (![[NSFileManager defaultManager] moveItemAtURL:location toURL:destination error:nil]) destination = nil;
            }

            dispatch_async(dispatch_get_main_queue(), ^{
                if (destination) results[index] = destination;
                else failed++;

                finished++;
                hud.textLabel.text = [NSString stringWithFormat:@"Downloading %lu/%lu", (unsigned long)finished, (unsigned long)urls.count];
                if (finished < urls.count) return;

                [hud dismiss];
                for (id result in results) {
                    if ([result isKindOfClass:NSURL.class]) [files addObject:result];
                }

                if (!files.count) {
                    [SCIUtils showErrorHUDWithDescription:@"Download failed, try again later"];
                    return;
                }
                if (failed) {
                    [SCIUtils showToastForDuration:3.0 title:[NSString stringWithFormat:@"%lu of %lu downloads failed", (unsigned long)failed, (unsigned long)urls.count]];
                }

                shareFiles(files);
            });
        }];
        [task resume];
    }];
}

+ (void)downloadAudioFromVideoURL:(NSURL *)url {
    if (!url) return;

    JGProgressHUD *hud = [[JGProgressHUD alloc] init];
    hud.textLabel.text = @"Extracting audio";
    [hud showInView:topMostController().view];

    void (^fail)(NSString *) = ^(NSString *reason) {
        dispatch_async(dispatch_get_main_queue(), ^{
            NSLog(@"[SCInsta] Audio extraction failed: %@", reason);
            [hud dismiss];
            [SCIUtils showErrorHUDWithDescription:@"Could not extract audio"];
        });
    };

    NSURLSessionDownloadTask *task = [[NSURLSession sharedSession] downloadTaskWithURL:url completionHandler:^(NSURL *location, NSURLResponse *response, NSError *error) {
        if (!location || error) return fail(error.localizedDescription);

        NSURL *videoFile = cacheFileURL(@"mp4");
        if (![[NSFileManager defaultManager] moveItemAtURL:location toURL:videoFile error:nil]) return fail(@"move failed");

        AVURLAsset *asset = [AVURLAsset URLAssetWithURL:videoFile options:nil];
        AVAssetExportSession *export = [AVAssetExportSession exportSessionWithAsset:asset presetName:AVAssetExportPresetAppleM4A];
        if (!export) return fail(@"no export session");

        NSURL *audioFile = cacheFileURL(@"m4a");
        export.outputURL = audioFile;
        export.outputFileType = AVFileTypeAppleM4A;

        [export exportAsynchronouslyWithCompletionHandler:^{
            [[NSFileManager defaultManager] removeItemAtURL:videoFile error:nil];
            if (export.status != AVAssetExportSessionStatusCompleted) return fail(export.error.localizedDescription);

            dispatch_async(dispatch_get_main_queue(), ^{
                [hud dismiss];
                shareFiles(@[audioFile]);
            });
        }];
    }];
    [task resume];
}

@end
