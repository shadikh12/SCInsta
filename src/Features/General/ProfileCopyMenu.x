#import "../../InstagramHeaders.h"
#import "../../Utils.h"

// Two-finger long press on a profile opens a menu to copy its username, name, bio or link
%hook IGProfileViewController
- (void)viewDidLoad {
    %orig;

    if (![SCIUtils getBoolPref:@"profile_copy_menu"]) return;

    UILongPressGestureRecognizer *longPress = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(handleProfileCopyLongPress:)];
    longPress.minimumPressDuration = 0.5;
    longPress.numberOfTouchesRequired = 2;
    longPress.cancelsTouchesInView = NO;
    [self.view addGestureRecognizer:longPress];
}

%new - (void)handleProfileCopyLongPress:(UILongPressGestureRecognizer *)sender {
    if (sender.state != UIGestureRecognizerStateBegan) return;

    [SCIUtils runFeature:@"Profile copy menu" block:^{
        IGUser *user = [self user];
        if (!user.username.length) return;

        NSString *username = user.username;
        NSString *fullName = [user respondsToSelector:@selector(fullName)] ? [user fullName] : nil;
        NSString *biography = [user respondsToSelector:@selector(biography)] ? [user biography] : nil;
        NSString *link = [NSString stringWithFormat:@"https://www.instagram.com/%@/", username];

        UIAlertController *sheet = [UIAlertController alertControllerWithTitle:[NSString stringWithFormat:@"@%@", username]
                                                                       message:nil
                                                                preferredStyle:UIAlertControllerStyleActionSheet];

        void (^addCopyAction)(NSString *, NSString *) = ^(NSString *title, NSString *value) {
            if (!value.length) return;

            [sheet addAction:[UIAlertAction actionWithTitle:title style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
                [UIPasteboard generalPasteboard].string = value;
                [SCIUtils showToastForDuration:2.0 title:@"Copied to clipboard"];
            }]];
        };
        addCopyAction(@"Copy username", username);
        addCopyAction(@"Copy name", fullName);
        addCopyAction(@"Copy bio", biography);
        addCopyAction(@"Copy profile link", link);
        [sheet addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];

        // iPad requires a popover anchor
        sheet.popoverPresentationController.sourceView = self.view;
        sheet.popoverPresentationController.sourceRect = CGRectMake(CGRectGetMidX(self.view.bounds), CGRectGetMidY(self.view.bounds), 1, 1);

        [self presentViewController:sheet animated:YES completion:nil];
    }];
}
%end
