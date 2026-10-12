#import "../../InstagramHeaders.h"
#import "../../Utils.h"

// Detailed dates: replaces relative times ("2h", "3d", "Active 5m ago") with the full date & time

@interface FBDateFormatterResult : NSObject
- (instancetype)initWithString:(NSString *)string accessibleString:(NSString *)accessibleString rule:(id)rule;
- (NSString *)string;
- (id)rule;
@end

static NSString *detailedDateString(NSDate *date) {
    static NSDateFormatter *formatter;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        formatter = [[NSDateFormatter alloc] init];
        formatter.locale = [NSLocale currentLocale];
        [formatter setLocalizedDateFormatFromTemplate:@"yMMMdjmm"];
    });

    return [formatter stringFromDate:date];
}

%hook FBAtomicDateFormatter
- (id)formatDate:(NSDate *)date relativeToDate:(NSDate *)relativeDate timeZone:(NSTimeZone *)timeZone {
    id result = %orig;

    if (![SCIUtils getBoolPref:@"detailed_dates"] || ![date isKindOfClass:[NSDate class]]) return result;

    __block id detailed = result;
    [SCIUtils runFeature:@"Detailed dates" block:^{
        // Only past dates (future ones are countdowns, e.g. event start times)
        NSDate *now = relativeDate ?: [NSDate date];
        if ([date timeIntervalSinceDate:now] > 0) return;

        NSString *text = detailedDateString(date);

        if ([result isKindOfClass:[NSString class]]) {
            detailed = text;
        }
        else if ([result isKindOfClass:%c(FBDateFormatterResult)]) {
            detailed = [[%c(FBDateFormatterResult) alloc] initWithString:text accessibleString:text rule:[result rule]];
        }
    }];

    return detailed;
}
%end
