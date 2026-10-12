#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <QuickLook/QuickLook.h>
#import <os/log.h>
#import <objc/message.h>

#import "../modules/JGProgressHUD/JGProgressHUD.h"

#import "InstagramHeaders.h"
#import "QuickLook.h"

#import "Settings/SCISettingsViewController.h"

#define SCILog(fmt, ...) \
    do { \
        NSString *tmpStr = [NSString stringWithFormat:(fmt), ##__VA_ARGS__]; \
        os_log(OS_LOG_DEFAULT, "[SCInsta Test] %{public}s", tmpStr.UTF8String); \
    } while(0)

#define SCILogId(prefix, obj) os_log(OS_LOG_DEFAULT, "[SCInsta Test] %{public}@: %{public}@", prefix, obj);

@interface SCIUtils : NSObject

+ (BOOL)getBoolPref:(NSString *)key;
+ (double)getDoublePref:(NSString *)key;
+ (NSString *)getStringPref:(NSString *)key;

+ (_Bool)liquidGlassEnabledBool:(_Bool)fallback;

+ (void)cleanCache;

// Displaying View Controllers
+ (void)showQuickLookVC:(NSArray<id> *)items;
+ (void)showShareVC:(id)item;
+ (void)showSettingsVC:(UIWindow *)window;

// Colours
+ (UIColor *)SCIColor_Primary;

// Errors
+ (NSError *)errorWithDescription:(NSString *)errorDesc;
+ (NSError *)errorWithDescription:(NSString *)errorDesc code:(NSInteger)errorCode;

+ (JGProgressHUD *)showErrorHUDWithDescription:(NSString *)errorDesc;
+ (JGProgressHUD *)showErrorHUDWithDescription:(NSString *)errorDesc dismissAfterDelay:(CGFloat)dismissDelay;

// Runs a feature's action, showing an error instead of crashing if it throws
+ (void)runFeature:(NSString *)feature block:(void(^)(void))block;

// Media
+ (NSURL *)getPhotoUrl:(IGPhoto *)photo;
+ (NSURL *)getPhotoUrlForMedia:(IGMedia *)media;

+ (NSURL *)getVideoUrl:(IGVideo *)video;
+ (NSURL *)getVideoUrlForMedia:(IGMedia *)media;

// View Controllers
+ (UIViewController *)viewControllerForView:(UIView *)view;
+ (UIViewController *)viewControllerForAncestralView:(UIView *)view;
+ (UIViewController *)nearestViewControllerForView:(UIView *)view;

// Functions
+ (NSString *)IGVersionString;
+ (BOOL)isNotch;

+ (BOOL)existingLongPressGestureRecognizerForView:(UIView *)view;

// Alerts
+ (BOOL)showConfirmation:(void(^)(void))okHandler title:(NSString *)title;
+ (BOOL)showConfirmation:(void(^)(void))okHandler cancelHandler:(void(^)(void))cancelHandler title:(NSString *)title;
+ (BOOL)showConfirmation:(void(^)(void))okHandler;
+ (BOOL)showConfirmation:(void(^)(void))okHandler cancelHandler:(void(^)(void))cancelHandler;
+ (void)showRestartConfirmation;

// Toasts
+ (void)showToastForDuration:(double)duration title:(NSString *)title;
+ (void)showToastForDuration:(double)duration title:(NSString *)title subtitle:(NSString *)subtitle;

// Math
+ (NSUInteger)decimalPlacesInDouble:(double)value;

// Ivars
+ (id)getIvarForObj:(id)obj name:(const char *)name;
+ (void)setIvarForObj:(id)obj name:(const char *)name value:(id)value;

// Breadth-first search through an object's ivars (and theirs, up to maxDepth) for the first
// object of a class. For Swift models whose ivar names/layout change between IG versions
+ (id)findIvarObjectOfClass:(Class)cls inObject:(id)root maxDepth:(NSInteger)maxDepth;

// Files in Documents/SCInsta (created on demand)
+ (NSURL *)dataFileURLWithName:(NSString *)name;
+ (id)loadJSONFileWithName:(NSString *)name;
+ (void)saveJSONObject:(id)object toFileWithName:(NSString *)name;

@end

// Feature compatibility (see FeatureCheck.m)
@interface SCIUtils (FeatureCheck)

// Titles of enabled features whose hooks don't match the installed Instagram
+ (NSArray<NSString *> *)brokenEnabledFeatures;
+ (void)showFeatureCompatibilityReport:(BOOL)onlyIfChanged;

@end
