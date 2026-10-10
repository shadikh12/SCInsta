#import <Foundation/Foundation.h>

@interface SCIBatchDownload : NSObject

// Downloads every url, then opens one share sheet with all the files
+ (void)downloadAndShareURLs:(NSArray<NSURL *> *)urls;

// Downloads a video and shares only its audio track (as .m4a)
+ (void)downloadAudioFromVideoURL:(NSURL *)url;

@end
