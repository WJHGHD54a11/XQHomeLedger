//
//  HLItemController.m
//  XQHomeLedger
//

#import "HLItemController.h"
#import "HLKit.h"
#import "HLStore.h"
#import "HLInsights.h"
#import "HLFormController.h"

@interface HLItemController () <UIScrollViewDelegate>
@property (nonatomic, copy) NSString *itemId;
@property (nonatomic, strong, nullable) HLRow *item;
@property (nonatomic, strong) UIStackView *stack;
@property (nonatomic, strong) UIPageControl *pager;
@end

@implementation HLItemController

- (instancetype)initWithItemId:(NSString *)itemId {
    if ((self = [super initWithNibName:nil bundle:nil])) _itemId = [itemId copy];
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [HLKit mist];
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeNever;
    __weak typeof(self) ws = self;
    UIAction *edit = [UIAction actionWithTitle:HLT(@"common.edit") image:[HLKit symbol:@"pencil" size:14] identifier:nil handler:^(UIAction *a) { [ws edit]; }];
    UIAction *dup = [UIAction actionWithTitle:HLT(@"item.duplicate") image:[HLKit symbol:@"plus.square.on.square" size:14] identifier:nil handler:^(UIAction *a) { [ws duplicate]; }];
    UIAction *del = [UIAction actionWithTitle:HLT(@"item.delete") image:[HLKit symbol:@"trash" size:14] identifier:nil handler:^(UIAction *a) { [ws remove]; }];
    del.attributes = UIMenuElementAttributesDestructive;
    UIBarButtonItem *more = [[UIBarButtonItem alloc] initWithImage:[HLKit symbol:@"ellipsis.circle" size:17] menu:[UIMenu menuWithTitle:@"" children:@[edit, dup, del]]];
    more.accessibilityLabel = HLT(@"item.actions");
    more.tintColor = [HLKit ink];
    self.navigationItem.rightBarButtonItem = more;

    UIScrollView *sv = [[UIScrollView alloc] init];
    sv.translatesAutoresizingMaskIntoConstraints = NO;
    sv.alwaysBounceVertical = YES;
    [self.view addSubview:sv];
    self.stack = [[UIStackView alloc] init];
    self.stack.axis = UILayoutConstraintAxisVertical;
    self.stack.spacing = 16;
    self.stack.translatesAutoresizingMaskIntoConstraints = NO;
    [sv addSubview:self.stack];
    [NSLayoutConstraint activateConstraints:@[
        [sv.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [sv.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
        [sv.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [sv.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.stack.topAnchor constraintEqualToAnchor:sv.contentLayoutGuide.topAnchor constant:6],
        [self.stack.bottomAnchor constraintEqualToAnchor:sv.contentLayoutGuide.bottomAnchor constant:-32],
        [self.stack.leadingAnchor constraintEqualToAnchor:sv.frameLayoutGuide.leadingAnchor constant:16],
        [self.stack.trailingAnchor constraintEqualToAnchor:sv.frameLayoutGuide.trailingAnchor constant:-16],
    ]];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(rebuild) name:HLDataChangedNotification object:nil];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self rebuild];
}

#pragma mark - Actions

- (void)edit {
    if (self.item) [HLFormController presentItemFormFor:self.item from:self];
}

- (void)duplicate {
    NSString *err = nil;
    NSString *nid = [[HLStore shared] duplicateItem:self.itemId error:&err];
    if (!nid) { [HLKit tell:self title:HLT(@"common.error") message:err]; return; }
    // Open the copy so the user can adjust it straight away.
    [self.navigationController pushViewController:[[HLItemController alloc] initWithItemId:nid] animated:YES];
}

- (void)remove {
    NSArray *m = [[HLStore shared] maintenanceForItem:self.itemId];
    NSString *msg = [NSString stringWithFormat:HLT(@"item.deleteMsg"), (long)m.count];
    [HLKit ask:self title:[NSString stringWithFormat:HLT(@"item.deleteTitle"), self.item[@"name"] ?: @""] message:msg
        action:HLT(@"common.delete") destructive:YES then:^{
        NSString *err = nil;
        if ([[HLStore shared] deleteItems:@[self.itemId] error:&err]) [self.navigationController popViewControllerAnimated:YES];
        else [HLKit tell:self title:HLT(@"common.error") message:err];
    }];
}

- (void)toggleChecked {
    NSInteger now = [self.item[@"check_state"] integerValue] ? 0 : 1;
    NSString *err = nil;
    if (![[HLStore shared] run:@"UPDATE item SET check_state = ?, checked_at = ? WHERE id = ?"
                          args:@[@(now), now ? @([[HLStore shared] now]) : [NSNull null], self.itemId] error:&err]) {
        [HLKit tell:self title:HLT(@"common.error") message:err];
        return;
    }
    [[HLStore shared] notifyChanged];
}

#pragma mark - Build

- (void)rebuild {
    if (!self.isViewLoaded) return;
    self.item = [[HLStore shared] itemWithId:self.itemId];
    if (!self.item) {
        // Deleted from another screen (batch delete, restore, erase).
        if (self.navigationController.topViewController == self) [self.navigationController popViewControllerAnimated:YES];
        return;
    }
    self.title = self.item[@"name"];
    for (UIView *v in self.stack.arrangedSubviews) [v removeFromSuperview];
    [self.stack addArrangedSubview:[self gallery]];
    [self.stack addArrangedSubview:[self headline]];
    [self.stack addArrangedSubview:[self facts]];
    [self.stack addArrangedSubview:[self warrantyCard]];
    [self.stack addArrangedSubview:[self maintenanceCard]];
    [self.stack addArrangedSubview:[self reminderCard]];
}

- (UIView *)gallery {
    NSArray *photos = [[HLStore shared] attachmentsFor:@"item" owner:self.itemId];
    UIScrollView *sv = [[UIScrollView alloc] init];
    sv.pagingEnabled = YES;
    sv.showsHorizontalScrollIndicator = NO;
    sv.delegate = self;
    sv.layer.cornerRadius = 26;
    sv.layer.cornerCurve = kCACornerCurveContinuous;
    sv.backgroundColor = [HLKit mint];
    [sv.heightAnchor constraintEqualToConstant:240].active = YES;
    UIStackView *row = [[UIStackView alloc] init];
    row.translatesAutoresizingMaskIntoConstraints = NO;
    [sv addSubview:row];
    [NSLayoutConstraint activateConstraints:@[
        [row.leadingAnchor constraintEqualToAnchor:sv.contentLayoutGuide.leadingAnchor], [row.trailingAnchor constraintEqualToAnchor:sv.contentLayoutGuide.trailingAnchor],
        [row.topAnchor constraintEqualToAnchor:sv.contentLayoutGuide.topAnchor], [row.bottomAnchor constraintEqualToAnchor:sv.contentLayoutGuide.bottomAnchor],
        [row.heightAnchor constraintEqualToAnchor:sv.frameLayoutGuide.heightAnchor]]];
    if (photos.count == 0) {
        UIButtonConfiguration *c = [UIButtonConfiguration plainButtonConfiguration];
        c.image = [HLKit symbol:self.item[@"category_icon"] ?: @"camera" size:44];
        c.title = HLT(@"item.addPhoto");
        c.imagePlacement = NSDirectionalRectEdgeTop;
        c.imagePadding = 12;
        c.baseForegroundColor = [HLKit leafText];
        UIButton *b = [UIButton buttonWithConfiguration:c primaryAction:[UIAction actionWithHandler:^(UIAction *a) { [self edit]; }]];
        [row addArrangedSubview:b];
        [b.widthAnchor constraintEqualToAnchor:sv.frameLayoutGuide.widthAnchor].active = YES;
    }
    for (HLRow *p in photos) {
        UIImage *img = [[HLStore shared] imageNamed:p[@"file"]];
        UIImageView *iv = [[UIImageView alloc] initWithImage:img ?: [HLKit symbol:@"exclamationmark.triangle" size:30]];
        iv.contentMode = img ? UIViewContentModeScaleAspectFill : UIViewContentModeCenter;
        iv.tintColor = [HLKit amber];
        iv.clipsToBounds = YES;
        iv.isAccessibilityElement = YES;
        iv.accessibilityLabel = img ? self.item[@"name"] : HLT(@"photo.missing");
        [row addArrangedSubview:iv];
        [iv.widthAnchor constraintEqualToAnchor:sv.frameLayoutGuide.widthAnchor].active = YES;
    }
    if (photos.count < 2) return sv;
    UIView *wrap = [[UIView alloc] init];
    sv.translatesAutoresizingMaskIntoConstraints = NO;
    [wrap addSubview:sv];
    self.pager = [[UIPageControl alloc] init];
    self.pager.numberOfPages = (NSInteger)photos.count;
    self.pager.currentPageIndicatorTintColor = UIColor.whiteColor;
    self.pager.pageIndicatorTintColor = [UIColor colorWithWhite:1 alpha:0.5];
    self.pager.userInteractionEnabled = NO;
    self.pager.translatesAutoresizingMaskIntoConstraints = NO;
    [wrap addSubview:self.pager];
    [NSLayoutConstraint activateConstraints:@[
        [sv.topAnchor constraintEqualToAnchor:wrap.topAnchor], [sv.bottomAnchor constraintEqualToAnchor:wrap.bottomAnchor],
        [sv.leadingAnchor constraintEqualToAnchor:wrap.leadingAnchor], [sv.trailingAnchor constraintEqualToAnchor:wrap.trailingAnchor],
        [self.pager.centerXAnchor constraintEqualToAnchor:wrap.centerXAnchor], [self.pager.bottomAnchor constraintEqualToAnchor:wrap.bottomAnchor constant:-8]]];
    return wrap;
}

- (void)scrollViewDidScroll:(UIScrollView *)sv {
    if (sv.bounds.size.width > 0) self.pager.currentPage = (NSInteger)lround(sv.contentOffset.x / sv.bounds.size.width);
}

- (UIView *)headline {
    HLRow *it = self.item;
    UILabel *name = [HLKit label:26 weight:UIFontWeightBold color:[HLKit ink]];
    name.font = [HLKit rounded:26 weight:UIFontWeightBold];
    name.text = it[@"name"];
    NSInteger st = [it[@"status"] integerValue];
    BOOL checked = [it[@"check_state"] integerValue] == 1;
    UIStackView *chips = [[UIStackView alloc] initWithArrangedSubviews:@[[HLKit chip:[HLKit statusName:st] color:[HLKit statusColor:st]],
                                                                          [HLKit chip:checked ? HLT(@"check.done") : HLT(@"check.not") color:checked ? [HLKit leafText] : [HLKit ash]]]];
    chips.spacing = 6;
    [chips addArrangedSubview:[[UIView alloc] init]];
    UIButton *check = [HLKit pill:checked ? HLT(@"item.uncheck") : HLT(@"item.markChecked") icon:checked ? @"arrow.uturn.backward" : @"checkmark" filled:!checked];
    [check addTarget:self action:@selector(toggleChecked) forControlEvents:UIControlEventTouchUpInside];
    UIStackView *s = [[UIStackView alloc] initWithArrangedSubviews:@[name, chips, check]];
    s.axis = UILayoutConstraintAxisVertical;
    s.spacing = 10;
    s.alignment = UIStackViewAlignmentLeading;
    [chips.widthAnchor constraintEqualToAnchor:s.widthAnchor].active = YES;
    return s;
}

#pragma mark - Cards

- (UIView *)cardTitled:(NSString *)title rows:(NSArray<UIView *> *)rows accessory:(UIView *)accessory {
    UIView *card = [HLKit card];
    UILabel *t = [HLKit label:16 weight:UIFontWeightBold color:[HLKit ink]];
    t.font = [HLKit rounded:16 weight:UIFontWeightBold];
    t.text = title;
    t.accessibilityTraits = UIAccessibilityTraitHeader;
    UIStackView *head = [[UIStackView alloc] initWithArrangedSubviews:accessory ? @[t, accessory] : @[t]];
    head.alignment = UIStackViewAlignmentCenter;
    UIStackView *s = [[UIStackView alloc] initWithArrangedSubviews:[@[head] arrayByAddingObjectsFromArray:rows]];
    s.axis = UILayoutConstraintAxisVertical;
    s.spacing = 12;
    s.translatesAutoresizingMaskIntoConstraints = NO;
    [card addSubview:s];
    [NSLayoutConstraint activateConstraints:@[
        [s.topAnchor constraintEqualToAnchor:card.topAnchor constant:16], [s.bottomAnchor constraintEqualToAnchor:card.bottomAnchor constant:-16],
        [s.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:16], [s.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-16]]];
    return card;
}

- (UIView *)fact:(NSString *)label value:(NSString *)value {
    UILabel *l = [HLKit label:13 weight:UIFontWeightRegular color:[HLKit ash]];
    l.text = label;
    [l setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    UILabel *v = [HLKit label:14 weight:UIFontWeightSemibold color:[HLKit ink]];
    v.text = value.length ? value : HLT(@"common.notSet");
    if (!value.length) v.textColor = [HLKit ash];
    v.textAlignment = NSTextAlignmentRight;
    UIStackView *r = [[UIStackView alloc] initWithArrangedSubviews:@[l, v]];
    r.spacing = 12;
    r.alignment = UIStackViewAlignmentFirstBaseline;
    r.isAccessibilityElement = YES;
    r.accessibilityLabel = [NSString stringWithFormat:@"%@: %@", label, v.text];
    return r;
}

- (NSString *)dateOf:(NSString *)key {
    return self.item[key] ? [HLKit day:[HLKit dateFromStamp:[self.item[key] doubleValue]]] : nil;
}

- (NSString *)moneyOf:(NSString *)key cur:(NSString *)curKey {
    return self.item[key] ? [HLKit money:[self.item[key] longLongValue] currency:self.item[curKey] ?: [HLKit defaultCurrency]] : nil;
}

- (UIView *)facts {
    HLRow *it = self.item;
    HLStore *store = [HLStore shared];
    NSString *room = it[@"room_id"] ? [store nameOf:@{@"name": it[@"room_name"] ?: @"", @"builtin": it[@"room_builtin"] ?: @""}] : nil;
    NSString *cat = it[@"category_id"] ? [store nameOf:@{@"name": it[@"category_name"] ?: @"", @"builtin": it[@"category_builtin"] ?: @""}] : nil;
    NSMutableArray *rows = [NSMutableArray arrayWithArray:@[
        [self fact:HLT(@"field.room") value:room], [self fact:HLT(@"field.spot") value:it[@"spot"]],
        [self fact:HLT(@"field.category") value:cat], [self fact:HLT(@"field.brand") value:it[@"brand"]],
        [self fact:HLT(@"field.model") value:it[@"model"]], [self fact:HLT(@"field.serial") value:it[@"serial"]],
        [self fact:HLT(@"field.purchaseDate") value:[self dateOf:@"purchase_date"]],
        [self fact:HLT(@"field.price") value:[self moneyOf:@"price" cur:@"price_cur"]],
        [self fact:HLT(@"field.value") value:[self moneyOf:@"value" cur:@"value_cur"]],
        [self fact:HLT(@"field.channel") value:it[@"channel"]],
    ]];
    NSString *tags = it[@"tags"];
    if (tags.length) [rows addObject:[self fact:HLT(@"field.tags") value:tags]];
    if ([HLKit trim:it[@"notes"]].length) {
        UILabel *n = [HLKit label:14 weight:UIFontWeightRegular color:[HLKit ink]];
        n.text = it[@"notes"];
        [rows addObject:n];
    }
    UILabel *meta = [HLKit label:11 weight:UIFontWeightRegular color:[HLKit ash]];
    meta.text = [NSString stringWithFormat:HLT(@"item.meta"), [HLKit dayTime:[HLKit dateFromStamp:[it[@"created"] doubleValue]]],
                 [HLKit dayTime:[HLKit dateFromStamp:[it[@"updated"] doubleValue]]]];
    [rows addObject:meta];
    return [self cardTitled:HLT(@"item.details") rows:rows accessory:nil];
}

- (UIView *)warrantyCard {
    NSDate *end = self.item[@"warranty_end"] ? [HLKit dateFromStamp:[self.item[@"warranty_end"] doubleValue]] : nil;
    HLWarranty w = [HLKit warrantyForEnd:end];
    NSMutableArray *rows = [NSMutableArray array];
    if (end) {
        NSCalendar *cal = [NSCalendar currentCalendar];
        NSInteger days = [cal components:NSCalendarUnitDay fromDate:[cal startOfDayForDate:[NSDate date]] toDate:[cal startOfDayForDate:end] options:0].day;
        UILabel *big = [HLKit label:20 weight:UIFontWeightHeavy color:[HLKit warrantyColor:w]];
        big.font = [HLKit rounded:20 weight:UIFontWeightHeavy];
        big.text = days >= 0 ? [NSString stringWithFormat:HLT(@"item.warrantyLeft"), (long)days] : [NSString stringWithFormat:HLT(@"item.warrantyAgo"), (long)-days];
        [rows addObject:big];
    }
    [rows addObject:[self fact:HLT(@"field.warrantyStart") value:[self dateOf:@"warranty_start"]]];
    [rows addObject:[self fact:HLT(@"field.warrantyEnd") value:[self dateOf:@"warranty_end"]]];
    if ([HLKit trim:self.item[@"warranty_note"]].length) {
        UILabel *n = [HLKit label:13 weight:UIFontWeightRegular color:[HLKit ink]];
        n.text = self.item[@"warranty_note"];
        [rows addObject:n];
    }
    if (!end) {
        UILabel *n = [HLKit label:12 weight:UIFontWeightRegular color:[HLKit ash]];
        n.text = HLT(@"item.noWarrantyNote");
        [rows addObject:n];
    }
    return [self cardTitled:HLT(@"item.warranty") rows:rows accessory:[HLKit chip:[HLKit warrantyName:w] color:[HLKit warrantyColor:w]]];
}

#pragma mark - Maintenance

- (UIView *)stat:(NSString *)value caption:(NSString *)caption {
    UILabel *v = [HLKit label:16 weight:UIFontWeightHeavy color:[HLKit ink]];
    v.font = [HLKit rounded:16 weight:UIFontWeightHeavy];
    v.text = value;
    v.adjustsFontSizeToFitWidth = YES;
    v.minimumScaleFactor = 0.6;
    v.numberOfLines = 2;
    UILabel *c = [HLKit label:11 weight:UIFontWeightRegular color:[HLKit ash]];
    c.text = caption;
    UIStackView *s = [[UIStackView alloc] initWithArrangedSubviews:@[v, c]];
    s.axis = UILayoutConstraintAxisVertical;
    s.spacing = 2;
    return s;
}

- (UIView *)maintenanceCard {
    NSArray *records = [[HLStore shared] maintenanceForItem:self.itemId];
    NSMutableDictionary *costs = [NSMutableDictionary dictionary];
    for (HLRow *m in records) {
        if (m[@"cost"] && m[@"cost_cur"]) costs[m[@"cost_cur"]] = @([costs[m[@"cost_cur"]] longLongValue] + [m[@"cost"] longLongValue]);
    }
    UIStackView *stats = [[UIStackView alloc] initWithArrangedSubviews:@[
        [self stat:[NSString stringWithFormat:@"%ld", (long)records.count] caption:HLT(@"maint.count")],
        [self stat:costs.count ? [[HLInsights describe:costs] stringByReplacingOccurrencesOfString:@"  ·  " withString:@"\n"] : @"—" caption:HLT(@"maint.totalCost")],
        [self stat:records.count ? [HLKit day:[HLKit dateFromStamp:[records.firstObject[@"date"] doubleValue]]] : @"—" caption:HLT(@"maint.last")]]];
    stats.distribution = UIStackViewDistributionFillEqually;
    stats.alignment = UIStackViewAlignmentTop;
    stats.spacing = 10;
    NSMutableArray *rows = [NSMutableArray arrayWithObject:stats];
    NSArray *kinds = @[HLT(@"mkind.maintenance"), HLT(@"mkind.repair"), HLT(@"mkind.inspection"), HLT(@"mkind.other")];
    for (HLRow *m in records) {
        NSInteger k = MIN(3, MAX(0, [m[@"kind"] integerValue]));
        UIButtonConfiguration *c = [UIButtonConfiguration plainButtonConfiguration];
        NSString *head = [HLKit trim:m[@"issue"]].length ? m[@"issue"] : (m[@"action"] ?: kinds[k]);
        c.title = head;
        NSMutableArray *sub = [NSMutableArray arrayWithObjects:[HLKit day:[HLKit dateFromStamp:[m[@"date"] doubleValue]]], kinds[k], nil];
        if (m[@"cost"]) [sub addObject:[HLKit money:[m[@"cost"] longLongValue] currency:m[@"cost_cur"] ?: [HLKit defaultCurrency]]];
        if ([m[@"photo_count"] integerValue]) [sub addObject:[NSString stringWithFormat:HLT(@"maint.photosN"), (long)[m[@"photo_count"] integerValue]]];
        c.subtitle = [sub componentsJoinedByString:@" · "];
        c.image = [HLKit symbol:k == 1 ? @"wrench" : @"calendar" size:15];
        c.imagePadding = 12;
        c.baseForegroundColor = [HLKit ink];
        c.imageColorTransformer = ^UIColor *(UIColor *x) { return [HLKit leafText]; };
        c.background.backgroundColor = [HLKit mist];
        c.background.cornerRadius = 14;
        c.contentInsets = NSDirectionalEdgeInsetsMake(10, 12, 10, 12);
        UIButton *b = [UIButton buttonWithConfiguration:c primaryAction:nil];
        b.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeading;
        __weak typeof(self) ws = self;
        UIAction *edit = [UIAction actionWithTitle:HLT(@"common.edit") image:[HLKit symbol:@"pencil" size:14] identifier:nil handler:^(UIAction *a) {
            [HLFormController presentMaintenanceFor:m item:ws.item from:ws done:nil];
        }];
        UIAction *del = [UIAction actionWithTitle:HLT(@"common.delete") image:[HLKit symbol:@"trash" size:14] identifier:nil handler:^(UIAction *a) {
            [HLKit ask:ws title:HLT(@"maint.deleteTitle") message:HLT(@"maint.deleteMsg") action:HLT(@"common.delete") destructive:YES then:^{
                NSString *err = nil;
                if (![[HLStore shared] deleteMaintenance:m[@"id"] error:&err]) [HLKit tell:ws title:HLT(@"common.error") message:err];
            }];
        }];
        del.attributes = UIMenuElementAttributesDestructive;
        b.menu = [UIMenu menuWithTitle:@"" children:@[edit, del]];
        b.showsMenuAsPrimaryAction = YES;
        [rows addObject:b];
    }
    if (records.count == 0) {
        UILabel *e = [HLKit label:13 weight:UIFontWeightRegular color:[HLKit ash]];
        e.text = HLT(@"maint.empty");
        [rows addObject:e];
    }
    UIButton *add = [HLKit pill:HLT(@"maint.new") icon:@"plus" filled:NO];
    __weak typeof(self) ws = self;
    [add addAction:[UIAction actionWithHandler:^(UIAction *a) { [HLFormController presentMaintenanceFor:nil item:ws.item from:ws done:nil]; }]
  forControlEvents:UIControlEventTouchUpInside];
    [rows addObject:add];
    return [self cardTitled:HLT(@"maint.history") rows:rows accessory:nil];
}

#pragma mark - Reminders

- (UIView *)reminderCard {
    NSArray *rs = [[HLStore shared] remindersForItem:self.itemId];
    NSMutableArray *rows = [NSMutableArray array];
    double now = [NSDate date].timeIntervalSince1970;
    __weak typeof(self) ws = self;
    for (HLRow *r in rs) {
        BOOL past = [r[@"fire_at"] doubleValue] <= now;
        UILabel *t = [HLKit label:14 weight:UIFontWeightSemibold color:past ? [HLKit ash] : [HLKit ink]];
        t.text = r[@"title"];
        UILabel *d = [HLKit label:12 weight:UIFontWeightRegular color:[HLKit ash]];
        d.text = past ? [NSString stringWithFormat:HLT(@"rem.past"), [HLKit dayTime:[HLKit dateFromStamp:[r[@"fire_at"] doubleValue]]]]
                      : [HLKit dayTime:[HLKit dateFromStamp:[r[@"fire_at"] doubleValue]]];
        UIStackView *txt = [[UIStackView alloc] initWithArrangedSubviews:@[t, d]];
        txt.axis = UILayoutConstraintAxisVertical;
        UIButton *x = [UIButton buttonWithType:UIButtonTypeSystem];
        [x setImage:[HLKit symbol:@"trash" size:14] forState:UIControlStateNormal];
        x.tintColor = [HLKit coral];
        x.accessibilityLabel = HLT(@"rem.delete");
        [x addAction:[UIAction actionWithHandler:^(UIAction *a) {
            NSString *err = nil;
            if ([[HLStore shared] deleteReminder:r[@"id"] error:&err]) [HLInsights rescheduleAll];
            else [HLKit tell:ws title:HLT(@"common.error") message:err];
        }] forControlEvents:UIControlEventTouchUpInside];
        UIImageView *bell = [[UIImageView alloc] initWithImage:[HLKit symbol:@"bell" size:14]];
        bell.tintColor = [HLKit leafText];
        UIStackView *row = [[UIStackView alloc] initWithArrangedSubviews:@[bell, txt, x]];
        row.spacing = 12;
        row.alignment = UIStackViewAlignmentCenter;
        [rows addObject:row];
    }
    UILabel *note = [HLKit label:11 weight:UIFontWeightRegular color:[HLKit ash]];
    note.text = HLT(@"rem.note");
    [rows addObject:note];

    NSMutableArray *opts = [NSMutableArray array];
    NSDate *end = self.item[@"warranty_end"] ? [HLKit dateFromStamp:[self.item[@"warranty_end"] doubleValue]] : nil;
    NSCalendar *cal = [NSCalendar currentCalendar];
    if (end) {
        for (NSNumber *d in @[@30, @7]) {
            NSDate *fire = [cal dateBySettingHour:9 minute:0 second:0 ofDate:[cal dateByAddingUnit:NSCalendarUnitDay value:-d.integerValue toDate:end options:0] options:0];
            if ([fire timeIntervalSinceNow] > 60) {
                [opts addObject:@{@"title": [NSString stringWithFormat:HLT(@"rem.warrantyBefore"), (long)d.integerValue], @"kind": @"warranty", @"fire": fire}];
            }
        }
    }
    for (NSNumber *mo in @[@3, @6, @12]) {
        NSDate *fire = [cal dateBySettingHour:9 minute:0 second:0 ofDate:[cal dateByAddingUnit:NSCalendarUnitMonth value:mo.integerValue toDate:[NSDate date] options:0] options:0];
        [opts addObject:@{@"title": [NSString stringWithFormat:HLT(@"rem.maintainIn"), (long)mo.integerValue], @"kind": @"maintenance", @"fire": fire}];
    }
    NSMutableArray *acts = [NSMutableArray array];
    for (NSDictionary *o in opts) {
        [acts addObject:[UIAction actionWithTitle:o[@"title"] image:nil identifier:nil handler:^(UIAction *a) { [ws addReminder:o]; }]];
    }
    UIButton *add = [HLKit pill:HLT(@"rem.add") icon:@"bell.badge" filled:NO];
    add.menu = [UIMenu menuWithTitle:HLT(@"rem.add") children:acts];
    add.showsMenuAsPrimaryAction = YES;
    [rows addObject:add];
    return [self cardTitled:HLT(@"rem.title") rows:rows accessory:nil];
}

- (void)addReminder:(NSDictionary *)o {
    // Permission is asked only now, because the user chose to set a reminder.
    [HLInsights requestPermission:^(BOOL granted) {
        NSString *kind = [o[@"kind"] isEqualToString:@"warranty"] ? HLT(@"rem.kindWarranty") : HLT(@"rem.kindMaintenance");
        NSString *title = [NSString stringWithFormat:@"%@ · %@", kind, self.item[@"name"] ?: @""];
        NSString *err = nil;
        if (![[HLStore shared] saveReminder:nil item:self.itemId kind:o[@"kind"] fireAt:[o[@"fire"] timeIntervalSince1970] title:title error:&err]) {
            [HLKit tell:self title:HLT(@"common.error") message:err];
            return;
        }
        [HLInsights rescheduleAll];
        if (!granted) [HLKit tell:self title:HLT(@"rem.deniedTitle") message:HLT(@"rem.deniedMsg")];
    }];
}

@end
