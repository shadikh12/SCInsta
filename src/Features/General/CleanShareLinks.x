#import "../../Utils.h"

// Strips tracking parameters (igsh, igshid, utm_*) from copied Instagram links
static NSString *cleanInstagramLink(NSString *string) {
    if (!string.length || [string rangeOfString:@"instagr"].location == NSNotFound) return string;

    NSString *trimmed = [string stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    NSURLComponents *components = [NSURLComponents componentsWithString:trimmed];

    NSString *host = components.host.lowercaseString;
    if (!host || !([host hasSuffix:@"instagram.com"] || [host hasSuffix:@"instagr.am"])) return string;
    if (!components.queryItems.count) return string;

    NSMutableArray<NSURLQueryItem *> *kept = [NSMutableArray array];
    for (NSURLQueryItem *item in components.queryItems) {
        NSString *name = item.name.lowercaseString;
        if ([name isEqualToString:@"igsh"] || [name isEqualToString:@"igshid"] || [name hasPrefix:@"utm_"]) continue;

        [kept addObject:item];
    }

    components.queryItems = kept.count ? kept : nil;
    return components.string ?: string;
}

%hook UIPasteboard
- (void)setString:(NSString *)string {
    if ([SCIUtils getBoolPref:@"clean_share_links"]) {
        string = cleanInstagramLink(string);
    }

    %orig(string);
}
- (void)setURL:(NSURL *)url {
    if ([SCIUtils getBoolPref:@"clean_share_links"] && url) {
        NSString *cleaned = cleanInstagramLink(url.absoluteString);
        url = [NSURL URLWithString:cleaned] ?: url;
    }

    %orig(url);
}
%end
