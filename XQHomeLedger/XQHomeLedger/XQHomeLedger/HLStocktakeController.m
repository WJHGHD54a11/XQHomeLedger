//
//  HLStocktakeController.m
//  XQHomeLedger
//

#import "HLStocktakeController.h"
#import "HLKit.h"
#import "HLStore.h"
#import "HLItemController.h"

typedef NS_ENUM(NSInteger, HLEntryResult) {
    HLEntryPending = 0,
    HLEntryChecked = 1,
    HLEntryMissing = 2,
    HLEntryAction = 3,
};

@interface HLStocktakeController ()
@property (nonatomic, copy, nullable) NSString *sessionId;
@property (nonatomic, strong, nullable) HLRow *session;
@property (nonatomic, copy) NSArray<HLRow *> *entries;
@property (nonatomic, copy) NSArray<HLRow *> *history;
@end

@implementation HLStocktakeController

- (instancetype)initWithSession:(NSString *)sessionId {
    if ((self = [super initWithStyle:UITableViewStyleInsetGrouped])) _sessionId = [sessionId copy];
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeNever;
    self.tableView.backgroundColor = [HLKit mist];
    self.tableView.separatorColor = [HLKit hair];
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 64;
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(reload) name:HLDataChangedNotification object:nil];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self reload];
}

- (BOOL)overview {
    return self.sessionId == nil;
}

- (BOOL)finished {
    return self.session[@"finished"] != nil;
}

- (void)reload {
    if (!self.isViewLoaded) return;
    HLStore *store = [HLStore shared];
    if ([self overview]) {
        self.title = HLT(@"stock.title");
        self.history = [store stocktakes];
        self.navigationItem.rightBarButtonItem = nil;
    } else {
        self.session = [store row:@"SELECT * FROM stocktake WHERE id = ?" args:@[self.sessionId]];
        if (!self.session) { [self.navigationController popViewControllerAnimated:YES]; return; }
        self.title = self.session[@"title"] ?: HLT(@"stock.title");
        self.entries = [store entriesFor:self.sessionId];
        self.navigationItem.rightBarButtonItem = [self finished] ? nil :
            [[UIBarButtonItem alloc] initWithTitle:HLT(@"stock.finish") style:UIBarButtonItemStyleDone target:self action:@selector(finish)];
        self.navigationItem.rightBarButtonItem.tintColor = [HLKit leafText];
    }
    self.tableView.tableHeaderView = [self header];
    [self.tableView reloadData];
}

#pragma mark - Header

- (UIView *)header {
    CGFloat w = self.tableView.bounds.size.width ?: self.view.bounds.size.width;
    UIView *wrap = [[UIView alloc] init];
    UIView *card = [[UIView alloc] init];
    card.backgroundColor = [HLKit mint];
    card.layer.cornerRadius = 24;
    card.translatesAutoresizingMaskIntoConstraints = NO;
    [wrap addSubview:card];
    UIStackView *s = [[UIStackView alloc] init];
    s.axis = UILayoutConstraintAxisVertical;
    s.spacing = 10;
    s.translatesAutoresizingMaskIntoConstraints = NO;
    [card addSubview:s];
    if ([self overview]) {
        UILabel *t = [HLKit label:15 weight:UIFontWeightRegular color:[HLKit ink]];
        t.text = HLT(@"stock.intro");
        [s addArrangedSubview:t];
        HLRow *open = [[HLStore shared] openStocktake];
        UIButton *b = [HLKit pill:open ? HLT(@"stock.continue") : HLT(@"stock.start") icon:open ? @"play.fill" : @"checklist" filled:YES];
        [b addTarget:self action:@selector(startOrContinue:) forControlEvents:UIControlEventTouchUpInside];
        [s addArrangedSubview:b];
    } else {
        NSInteger total = self.entries.count, done = 0, flagged = 0;
        for (HLRow *e in self.entries) {
            NSInteger r = [e[@"result"] integerValue];
            if (r == HLEntryChecked) done++;
            if (r == HLEntryMissing || r == HLEntryAction) flagged++;
        }
        NSInteger pending = total - done - flagged;
        UIView *ring = [HLKit ring:total ? (CGFloat)(done + flagged) / total : 0 color:[HLKit leaf] diameter:76 line:9];
        UILabel *pct = [HLKit label:16 weight:UIFontWeightHeavy color:[HLKit ink]];
        pct.font = [HLKit rounded:16 weight:UIFontWeightHeavy];
        pct.text = [NSString stringWithFormat:@"%ld/%ld", (long)(done + flagged), (long)total];
        pct.translatesAutoresizingMaskIntoConstraints = NO;
        [ring addSubview:pct];
        [NSLayoutConstraint activateConstraints:@[[pct.centerXAnchor constraintEqualToAnchor:ring.centerXAnchor], [pct.centerYAnchor constraintEqualToAnchor:ring.centerYAnchor]]];
        UILabel *a = [HLKit label:14 weight:UIFontWeightSemibold color:[HLKit ink]];
        a.text = [NSString stringWithFormat:HLT(@"stock.counts"), (long)done, (long)pending, (long)flagged];
        UILabel *b = [HLKit label:12 weight:UIFontWeightRegular color:[HLKit ash]];
        b.text = [self finished] ? [NSString stringWithFormat:HLT(@"stock.finishedAt"), [HLKit dayTime:[HLKit dateFromStamp:[self.session[@"finished"] doubleValue]]]]
                                 : HLT(@"stock.swipeHint");
        UIStackView *txt = [[UIStackView alloc] initWithArrangedSubviews:@[a, b]];
        txt.axis = UILayoutConstraintAxisVertical;
        txt.spacing = 4;
        UIStackView *row = [[UIStackView alloc] initWithArrangedSubviews:@[ring, txt]];
        row.spacing = 16;
        row.alignment = UIStackViewAlignmentCenter;
        row.isAccessibilityElement = YES;
        row.accessibilityLabel = [NSString stringWithFormat:@"%@. %@", a.text, b.text];
        [s addArrangedSubview:row];
    }
    [NSLayoutConstraint activateConstraints:@[
        [card.topAnchor constraintEqualToAnchor:wrap.topAnchor constant:8], [card.bottomAnchor constraintEqualToAnchor:wrap.bottomAnchor constant:-4],
        [card.leadingAnchor constraintEqualToAnchor:wrap.leadingAnchor constant:20], [card.trailingAnchor constraintEqualToAnchor:wrap.trailingAnchor constant:-20],
        [s.topAnchor constraintEqualToAnchor:card.topAnchor constant:18], [s.bottomAnchor constraintEqualToAnchor:card.bottomAnchor constant:-18],
        [s.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:18], [s.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-18]]];
    CGSize sz = [wrap systemLayoutSizeFittingSize:CGSizeMake(w, UILayoutFittingCompressedSize.height)
                    withHorizontalFittingPriority:UILayoutPriorityRequired verticalFittingPriority:UILayoutPriorityFittingSizeLevel];
    wrap.frame = CGRectMake(0, 0, w, sz.height);
    return wrap;
}

#pragma mark - Session actions

- (void)startOrContinue:(UIView *)src {
    HLStore *store = [HLStore shared];
    HLRow *open = [store openStocktake];
    if (open) {
        [self.navigationController pushViewController:[[HLStocktakeController alloc] initWithSession:open[@"id"]] animated:YES];
        return;
    }
    UIAlertController *a = [UIAlertController alertControllerWithTitle:HLT(@"stock.scope") message:HLT(@"stock.scopeMsg")
                                                        preferredStyle:UIAlertControllerStyleActionSheet];
    void (^start)(NSString *, NSString *) = ^(NSString *scope, NSString *value) {
        NSString *err = nil;
        NSString *sid = [store startStocktakeScope:scope value:value error:&err];
        if (!sid) { [HLKit tell:self title:HLT(@"common.error") message:err]; return; }
        [self.navigationController pushViewController:[[HLStocktakeController alloc] initWithSession:sid] animated:YES];
    };
    [a addAction:[UIAlertAction actionWithTitle:HLT(@"stock.scopeAll") style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) { start(@"all", nil); }]];
    [a addAction:[UIAlertAction actionWithTitle:HLT(@"stock.scopeRoom") style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) {
        [self pickFrom:[store rooms] title:HLT(@"stock.scopeRoom") src:src then:^(HLRow *r) { start(@"room", r[@"id"]); }];
    }]];
    [a addAction:[UIAlertAction actionWithTitle:HLT(@"stock.scopeCategory") style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) {
        [self pickFrom:[store categories] title:HLT(@"stock.scopeCategory") src:src then:^(HLRow *r) { start(@"category", r[@"id"]); }];
    }]];
    [a addAction:[UIAlertAction actionWithTitle:HLT(@"common.cancel") style:UIAlertActionStyleCancel handler:nil]];
    a.popoverPresentationController.sourceView = src;
    a.popoverPresentationController.sourceRect = src.bounds;
    [self presentViewController:a animated:YES completion:nil];
}

- (void)pickFrom:(NSArray<HLRow *> *)rows title:(NSString *)title src:(UIView *)src then:(void (^)(HLRow *))then {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:title message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    for (HLRow *r in rows) {
        NSString *t = [NSString stringWithFormat:@"%@ (%@)", [[HLStore shared] nameOf:r], r[@"item_count"] ?: @0];
        [a addAction:[UIAlertAction actionWithTitle:t style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) { then(r); }]];
    }
    [a addAction:[UIAlertAction actionWithTitle:HLT(@"common.cancel") style:UIAlertActionStyleCancel handler:nil]];
    a.popoverPresentationController.sourceView = src;
    a.popoverPresentationController.sourceRect = src.bounds;
    [self presentViewController:a animated:YES completion:nil];
}

- (void)finish {
    NSInteger pending = 0;
    for (HLRow *e in self.entries) if ([e[@"result"] integerValue] == HLEntryPending) pending++;
    NSString *msg = pending ? [NSString stringWithFormat:HLT(@"stock.finishPending"), (long)pending] : HLT(@"stock.finishMsg");
    [HLKit ask:self title:HLT(@"stock.finish") message:msg action:HLT(@"stock.finish") destructive:NO then:^{
        NSString *err = nil;
        if (![[HLStore shared] finishStocktake:self.sessionId error:&err]) [HLKit tell:self title:HLT(@"common.error") message:err];
    }];
}

- (void)mark:(HLRow *)e result:(NSInteger)result note:(NSString *)note moveTo:(NSString *)rid {
    NSString *err = nil;
    if (![[HLStore shared] markEntry:e[@"id"] result:result note:note moveTo:rid error:&err]) [HLKit tell:self title:HLT(@"common.error") message:err];
}

/// Asks for a short note (missing / needs action), then records the result.
- (void)mark:(HLRow *)e result:(NSInteger)result askNote:(NSString *)title {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:title message:e[@"item_name"] preferredStyle:UIAlertControllerStyleAlert];
    [a addTextFieldWithConfigurationHandler:^(UITextField *t) { t.placeholder = HLT(@"stock.notePh"); t.text = e[@"note"]; }];
    [a addAction:[UIAlertAction actionWithTitle:HLT(@"common.cancel") style:UIAlertActionStyleCancel handler:nil]];
    [a addAction:[UIAlertAction actionWithTitle:HLT(@"common.save") style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) {
        [self mark:e result:result note:a.textFields.firstObject.text moveTo:nil];
    }]];
    [self presentViewController:a animated:YES completion:nil];
}

- (void)moveEntry:(HLRow *)e from:(UIView *)src {
    NSArray *rooms = [[HLStore shared] rooms];
    UIAlertController *a = [UIAlertController alertControllerWithTitle:HLT(@"stock.foundIn") message:e[@"item_name"] preferredStyle:UIAlertControllerStyleActionSheet];
    for (HLRow *r in rooms) {
        if ([r[@"id"] isEqualToString:e[@"room_id"] ?: @""]) continue;
        [a addAction:[UIAlertAction actionWithTitle:[[HLStore shared] nameOf:r] style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) {
            // Found elsewhere: confirmed, and the item's room is updated.
            [self mark:e result:HLEntryChecked note:nil moveTo:r[@"id"]];
        }]];
    }
    [a addAction:[UIAlertAction actionWithTitle:HLT(@"common.cancel") style:UIAlertActionStyleCancel handler:nil]];
    a.popoverPresentationController.sourceView = src ?: self.view;
    a.popoverPresentationController.sourceRect = src ? src.bounds : CGRectZero;
    [self presentViewController:a animated:YES completion:nil];
}

#pragma mark - Table

/// Session view groups entries: 0 to check, 1 needs attention, 2 confirmed.
- (NSArray<HLRow *> *)group:(NSInteger)g {
    NSMutableArray *a = [NSMutableArray array];
    for (HLRow *e in self.entries) {
        NSInteger r = [e[@"result"] integerValue];
        NSInteger eg = r == HLEntryPending ? 0 : (r == HLEntryChecked ? 2 : 1);
        if (eg == g) [a addObject:e];
    }
    return a;
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return [self overview] ? 1 : 3;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    if ([self overview]) return self.history.count ? HLT(@"stock.history") : nil;
    NSArray *t = @[HLT(@"stock.toCheck"), HLT(@"stock.attention"), HLT(@"stock.confirmed")];
    return [NSString stringWithFormat:@"%@ (%ld)", t[section], (long)[self group:section].count];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if ([self overview]) return self.history.count;
    return [self group:section].count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)ip {
    UITableViewCell *c = [tableView dequeueReusableCellWithIdentifier:@"st"] ?: [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"st"];
    c.backgroundColor = [HLKit paper];
    c.textLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightSemibold];
    c.textLabel.textColor = [HLKit ink];
    c.textLabel.numberOfLines = 0;
    c.detailTextLabel.textColor = [HLKit ash];
    c.detailTextLabel.numberOfLines = 0;
    c.accessoryView = nil;
    c.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    c.imageView.image = nil;
    if ([self overview]) {
        HLRow *s = self.history[ip.row];
        c.textLabel.text = s[@"title"];
        NSString *when = [HLKit day:[HLKit dateFromStamp:[s[@"started"] doubleValue]]];
        c.detailTextLabel.text = [NSString stringWithFormat:HLT(@"stock.historyRow"), when, (long)[s[@"checked"] integerValue],
                                  (long)[s[@"total"] integerValue], (long)[s[@"flagged"] integerValue]];
        BOOL open = s[@"finished"] == nil;
        UILabel *chip = [HLKit chip:open ? HLT(@"stock.inProgress") : HLT(@"stock.done") color:open ? [HLKit amber] : [HLKit leafText]];
        [chip sizeToFit];
        chip.frame = CGRectMake(0, 0, chip.frame.size.width + 4, 22);
        c.accessoryView = chip;
        return c;
    }
    HLRow *e = [self group:ip.section][ip.row];
    NSInteger r = [e[@"result"] integerValue];
    c.textLabel.text = e[@"item_name"];
    NSString *room = e[@"room_id"] ? [[HLStore shared] nameOf:@{@"name": e[@"room_name"] ?: @"", @"builtin": e[@"room_builtin"] ?: @""}] : HLT(@"common.unassigned");
    NSMutableArray *bits = [NSMutableArray arrayWithObject:room];
    if (r == HLEntryMissing) [bits addObject:HLT(@"stock.missing")];
    if (r == HLEntryAction) [bits addObject:HLT(@"stock.needsAction")];
    if (e[@"moved_to"]) [bits addObject:HLT(@"stock.moved")];
    if ([HLKit trim:e[@"note"]].length) [bits addObject:e[@"note"]];
    c.detailTextLabel.text = [bits componentsJoinedByString:@" · "];
    NSString *icon = r == HLEntryChecked ? @"checkmark.circle.fill" : (r == HLEntryPending ? @"circle" : @"exclamationmark.circle.fill");
    UIColor *color = r == HLEntryChecked ? [HLKit leaf] : (r == HLEntryPending ? [HLKit hair] : [HLKit amber]);
    c.imageView.image = [HLKit symbol:icon size:22];
    c.imageView.tintColor = color;
    c.accessoryType = UITableViewCellAccessoryNone;
    return c;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [tableView deselectRowAtIndexPath:ip animated:YES];
    if ([self overview]) {
        [self.navigationController pushViewController:[[HLStocktakeController alloc] initWithSession:self.history[ip.row][@"id"]] animated:YES];
        return;
    }
    HLRow *e = [self group:ip.section][ip.row];
    if ([self finished]) {
        [self.navigationController pushViewController:[[HLItemController alloc] initWithItemId:e[@"item_id"]] animated:YES];
        return;
    }
    // Tap = the quickest path: confirm present and in place.
    [self mark:e result:[e[@"result"] integerValue] == HLEntryChecked ? HLEntryPending : HLEntryChecked note:nil moveTo:nil];
}

- (UISwipeActionsConfiguration *)tableView:(UITableView *)tableView trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)ip {
    __weak typeof(self) ws = self;
    if ([self overview]) {
        HLRow *s = self.history[ip.row];
        UIContextualAction *del = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleDestructive title:HLT(@"common.delete")
                                                                        handler:^(UIContextualAction *a, UIView *v, void (^done)(BOOL)) {
            done(YES);
            [HLKit ask:ws title:HLT(@"stock.deleteTitle") message:HLT(@"stock.deleteMsg") action:HLT(@"common.delete") destructive:YES then:^{
                NSString *err = nil;
                if (![[HLStore shared] deleteStocktake:s[@"id"] error:&err]) [HLKit tell:ws title:HLT(@"common.error") message:err];
            }];
        }];
        return [UISwipeActionsConfiguration configurationWithActions:@[del]];
    }
    if ([self finished]) return nil;
    HLRow *e = [self group:ip.section][ip.row];
    UITableViewCell *cell = [tableView cellForRowAtIndexPath:ip];
    UIContextualAction *miss = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleNormal title:HLT(@"stock.missing")
                                                                     handler:^(UIContextualAction *a, UIView *v, void (^done)(BOOL)) {
        done(YES); [ws mark:e result:HLEntryMissing askNote:HLT(@"stock.missing")];
    }];
    miss.backgroundColor = [HLKit coral];
    UIContextualAction *act = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleNormal title:HLT(@"stock.needsAction")
                                                                    handler:^(UIContextualAction *a, UIView *v, void (^done)(BOOL)) {
        done(YES); [ws mark:e result:HLEntryAction askNote:HLT(@"stock.needsAction")];
    }];
    act.backgroundColor = [HLKit amber];
    UIContextualAction *move = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleNormal title:HLT(@"stock.foundIn")
                                                                     handler:^(UIContextualAction *a, UIView *v, void (^done)(BOOL)) {
        done(YES); [ws moveEntry:e from:cell];
    }];
    move.backgroundColor = [UIColor colorWithRed:0.29 green:0.47 blue:0.78 alpha:1];
    UISwipeActionsConfiguration *c = [UISwipeActionsConfiguration configurationWithActions:@[miss, act, move]];
    c.performsFirstActionWithFullSwipe = NO;
    return c;
}

@end
