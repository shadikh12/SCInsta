#import "SCIListViewController.h"
#import "../Utils.h"
#import "../InstagramHeaders.h"

@implementation SCIListViewController

- (instancetype)initWithTitle:(NSString *)title sections:(NSArray<NSDictionary *> *)sections {
    self = [super initWithStyle:UITableViewStyleInsetGrouped];
    if (self) {
        self.title = title;
        _sections = [sections copy];
        _emptyText = @"Nothing here yet";
    }

    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    if (self.actionTitle.length) {
        self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:self.actionTitle style:UIBarButtonItemStylePlain target:self action:@selector(didTapAction)];
    }
}

- (void)setSections:(NSArray<NSDictionary *> *)sections {
    _sections = [sections copy];

    if (self.isViewLoaded) [self.tableView reloadData];
}

- (void)didTapAction {
    if (self.action) self.action(self);
}

- (void)show {
    UIViewController *top = topMostController();
    UINavigationController *nav = [top isKindOfClass:[UINavigationController class]] ? (UINavigationController *)top : top.navigationController;

    if (nav) {
        [nav pushViewController:self animated:YES];
    }
    else {
        self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemClose target:self action:@selector(close)];
        [top presentViewController:[[UINavigationController alloc] initWithRootViewController:self] animated:YES completion:nil];
    }
}

- (void)close {
    [self dismissViewControllerAnimated:YES completion:nil];
}

#pragma mark - Table view

- (BOOL)isEmpty {
    for (NSDictionary *section in self.sections) {
        if ([section[@"rows"] count]) return NO;
    }

    return YES;
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return [self isEmpty] ? 1 : self.sections.count;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return [self isEmpty] ? 1 : [self.sections[section][@"rows"] count];
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return [self isEmpty] ? nil : self.sections[section][@"header"];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"SCIListCell"] ?: [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"SCIListCell"];

    cell.textLabel.numberOfLines = 0;
    cell.detailTextLabel.numberOfLines = 0;
    cell.detailTextLabel.textColor = [UIColor secondaryLabelColor];

    if ([self isEmpty]) {
        cell.textLabel.text = self.emptyText;
        cell.textLabel.textColor = [UIColor secondaryLabelColor];
        cell.detailTextLabel.text = nil;
        cell.accessoryType = UITableViewCellAccessoryNone;

        return cell;
    }

    NSDictionary *row = self.sections[indexPath.section][@"rows"][indexPath.row];
    cell.textLabel.text = row[@"title"];
    cell.textLabel.textColor = [UIColor labelColor];
    cell.detailTextLabel.text = row[@"subtitle"];
    cell.accessoryType = row[@"url"] ? UITableViewCellAccessoryDisclosureIndicator : UITableViewCellAccessoryNone;

    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if ([self isEmpty]) return;

    NSDictionary *row = self.sections[indexPath.section][@"rows"][indexPath.row];
    NSURL *url = row[@"url"] ? [NSURL URLWithString:row[@"url"]] : nil;
    if (url) [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:nil];
}

// Long-press a row to copy it
- (UIContextMenuConfiguration *)tableView:(UITableView *)tableView contextMenuConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath point:(CGPoint)point {
    if ([self isEmpty]) return nil;

    NSDictionary *row = self.sections[indexPath.section][@"rows"][indexPath.row];

    return [UIContextMenuConfiguration configurationWithIdentifier:nil previewProvider:nil actionProvider:^UIMenu *(NSArray *suggested) {
        UIAction *copy = [UIAction actionWithTitle:@"Copy" image:[UIImage systemImageNamed:@"doc.on.doc"] identifier:nil handler:^(UIAction *action) {
            NSString *subtitle = row[@"subtitle"];
            [UIPasteboard generalPasteboard].string = subtitle.length ? [NSString stringWithFormat:@"%@\n%@", row[@"title"], subtitle] : row[@"title"];
        }];

        return [UIMenu menuWithChildren:@[copy]];
    }];
}

@end
