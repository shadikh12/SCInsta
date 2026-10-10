#import <objc/runtime.h>
#import "Utils.h"
#import "FeatureCheckTable.h"

@implementation SCIUtils (FeatureCheck)

static BOOL hookResolves(const SCIFeatureHook *hook) {
    Class cls = objc_getClass(hook->cls);
    if (!cls) return NO;

    SEL sel = sel_registerName(hook->sel);
    return hook->isClassMethod ? class_getClassMethod(cls, sel) != NULL
                               : class_getInstanceMethod(cls, sel) != NULL;
}

// A feature is broken when none of its hooks (including legacy ones) match this IG version
+ (NSArray<NSString *> *)brokenEnabledFeatures {
    NSMutableArray<NSString *> *broken = [NSMutableArray array];
    NSMutableSet<NSString *> *working = [NSMutableSet set];
    NSMutableSet<NSString *> *checked = [NSMutableSet set];

    size_t count = sizeof(SCIFeatureHooks) / sizeof(SCIFeatureHooks[0]);
    for (size_t i = 0; i < count; i++) {
        NSString *pref = @(SCIFeatureHooks[i].pref);
        if (![SCIUtils getBoolPref:pref]) continue;

        [checked addObject:pref];
        if (hookResolves(&SCIFeatureHooks[i])) [working addObject:pref];
    }

    for (size_t i = 0; i < count; i++) {
        NSString *pref = @(SCIFeatureHooks[i].pref);
        NSString *title = @(SCIFeatureHooks[i].title);

        if ([checked containsObject:pref] && ![working containsObject:pref] && ![broken containsObject:title]) {
            [broken addObject:title];
        }
    }

    return [broken copy];
}

+ (void)showFeatureCompatibilityReport:(BOOL)onlyIfChanged {
    NSArray<NSString *> *broken = [SCIUtils brokenEnabledFeatures];

    // Only notify once per Instagram version & set of broken features
    if (onlyIfChanged) {
        NSString *signature = [NSString stringWithFormat:@"%@|%@", [SCIUtils IGVersionString], [broken componentsJoinedByString:@","]];
        NSString *lastSignature = [[NSUserDefaults standardUserDefaults] stringForKey:@"SCIFeatureCheckSignature"];

        if ([signature isEqualToString:lastSignature]) return;
        [[NSUserDefaults standardUserDefaults] setObject:signature forKey:@"SCIFeatureCheckSignature"];

        if (broken.count == 0) return;
    }

    for (NSString *title in broken) {
        NSLog(@"[SCInsta] Feature not supported on IG v%@: %@", [SCIUtils IGVersionString], title);
    }

    NSString *message;
    if (broken.count == 0) {
        message = [NSString stringWithFormat:@"All enabled features are supported on Instagram v%@.", [SCIUtils IGVersionString]];
    }
    else {
        message = [NSString stringWithFormat:@"These enabled features don't support Instagram v%@ and will have no effect:\n\n• %@",
                   [SCIUtils IGVersionString], [broken componentsJoinedByString:@"\n• "]];
    }

    UIAlertController *alert = [UIAlertController alertControllerWithTitle:broken.count ? @"Some SCInsta features won't work" : @"SCInsta feature check"
                                                                   message:message
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];

    [topMostController() presentViewController:alert animated:YES completion:nil];
}

@end
