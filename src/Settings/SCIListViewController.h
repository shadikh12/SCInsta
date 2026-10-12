#import <UIKit/UIKit.h>

// Simple read-only list screen, used for the deleted messages log, profile analyzer results, etc.
// sections: @[@{@"header": NSString, @"rows": @[@{@"title": NSString, @"subtitle": NSString, @"url": NSString (optional)}]}]

@interface SCIListViewController : UITableViewController

@property (nonatomic, copy) NSArray<NSDictionary *> *sections;
@property (nonatomic, copy) NSString *emptyText;

// Optional top-right button
@property (nonatomic, copy) NSString *actionTitle;
@property (nonatomic, copy) void (^action)(SCIListViewController *list);

- (instancetype)initWithTitle:(NSString *)title sections:(NSArray<NSDictionary *> *)sections;

// Pushes onto the current navigation controller, or presents in a new one
- (void)show;

@end
