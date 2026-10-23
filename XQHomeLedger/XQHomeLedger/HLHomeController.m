//
//  HLHomeController.m
//  XQHomeLedger
//

#import "HLHomeController.h"
#import "HLKit.h"
#import "HLStore.h"
#import "HLInsights.h"
#import "HLDockController.h"
#import "HLInventoryController.h"
#import "HLItemController.h"
#import "HLSettingsController.h"
#import "HLStocktakeController.h"

@interface HLHomeController ()
@property (nonatomic, strong) UIScrollView *scroll;
@property (nonatomic, strong) UIStackView *stack;
@end

@implementation HLHomeController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = HLT(@"tab.home");
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeNever;
    self.view.backgroundColor = [HLKit mist];
    UIBarButtonItem *gear = [[UIBarButtonItem alloc] initWithImage:[HLKit symbol:@"gearshape" size:17] style:UIBarButtonItemStylePlain
                                                            target:self action:@selector(openSettings)];
    gear.accessibilityLabel = HLT(@"settings.title");
    gear.tintColor = [HLKit ink];
    self.navigationItem.rightBarButtonItem = gear;

    self.scroll = [[UIScrollView alloc] init];
    self.scroll.translatesAutoresizingMaskIntoConstraints = NO;
    self.scroll.alwaysBounceVertical = YES;
    [self.view addSubview:self.scroll];
    self.stack = [[UIStackView alloc] init];
    self.stack.axis = UILayoutConstraintAxisVertical;
    self.stack.spacing = 22;
    self.stack.translatesAutoresizingMaskIntoConstraints = NO;
    [self.scroll addSubview:self.stack];
    [NSLayoutConstraint activateConstraints:@[
        [self.scroll.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [self.scroll.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor],
        [self.scroll.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.scroll.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.stack.topAnchor constraintEqualToAnchor:self.scroll.contentLayoutGuide.topAnchor constant:4],
        [self.stack.bottomAnchor constraintEqualToAnchor:self.scroll.contentLayoutGuide.bottomAnchor constant:-24],
        [self.stack.leadingAnchor constraintEqualToAnchor:self.scroll.frameLayoutGuide.leadingAnchor constant:18],
        [self.stack.trailingAnchor constraintEqualToAnchor:self.scroll.frameLayoutGuide.trailingAnchor constant:-18],
    ]];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(rebuild) name:HLDataChangedNotification object:nil];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self rebuild];
}

- (void)openSettings {
    [self.navigationController pushViewController:[[HLSettingsController alloc] init] animated:YES];
}

- (HLDockController *)dock {
    return [self.tabBarController isKindOfClass:[HLDockController class]] ? (HLDockController *)self.tabBarController : nil;
}

- (void)openInventory:(NSDictionary *)filter title:(NSString *)title {
    [self.navigationController pushViewController:[[HLInventoryController alloc] initWithFilter:filter title:title] animated:YES];
}

#pragma mark - Build

- (void)rebuild {
    if (!self.isViewLoaded) return;
    for (UIView *v in self.stack.arrangedSubviews) [v removeFromSuperview];
    HLStore *store = [HLStore shared];
    NSArray *items = [store allItems];
    if (store.openError) [self.stack addArrangedSubview:[self banner:HLT(@"err.dbOpen") color:[HLKit coral]]];
    if (items.count == 0) {
        [self.stack addArrangedSubview:[self welcome]];
        return;
    }
    HLInsights *ins = [[HLInsights alloc] initWithItems:nil];
    [self.stack addArrangedSubview:[self hero:ins]];
    [self.stack addArrangedSubview:[self quickActions]];
    UIView *att = [self attention:ins];
    if (att) [self.stack addArrangedSubview:att];
    [self.stack addArrangedSubview:[self recent:items]];
    UIView *w = [self warranties:items];
    if (w) [self.stack addArrangedSubview:w];
    if ([store hasSampleData]) [self.stack addArrangedSubview:[self banner:HLT(@"home.sampleBanner") color:[HLKit amber]]];
}

- (UILabel *)sectionTitle:(NSString *)t {
    UILabel *l = [HLKit label:20 weight:UIFontWeightBold color:[HLKit ink]];
    l.font = [HLKit rounded:20 weight:UIFontWeightBold];
    l.text = t;
    l.accessibilityTraits = UIAccessibilityTraitHeader;
    return l;
}

- (UIView *)banner:(NSString *)text color:(UIColor *)color {
    UILabel *l = [HLKit label:13 weight:UIFontWeightMedium color:color];
    l.text = text;
    UIView *wrap = [[UIView alloc] init];
    wrap.backgroundColor = [color colorWithAlphaComponent:0.10];
    wrap.layer.cornerRadius = 16;
    l.translatesAutoresizingMaskIntoConstraints = NO;
    [wrap addSubview:l];
    [NSLayoutConstraint activateConstraints:@[
        [l.topAnchor constraintEqualToAnchor:wrap.topAnchor constant:12], [l.bottomAnchor constraintEqualToAnchor:wrap.bottomAnchor constant:-12],
        [l.leadingAnchor constraintEqualToAnchor:wrap.leadingAnchor constant:14], [l.trailingAnchor constraintEqualToAnchor:wrap.trailingAnchor constant:-14]]];
    return wrap;
}

#pragma mark - Welcome (first run / empty)

- (UIView *)welcome {
    UIView *card = [HLKit card];
    card.backgroundColor = [HLKit mint];
    card.layer.shadowOpacity = 0;
    UIImageView *mark = [[UIImageView alloc] initWithImage:[HLKit symbol:@"house.and.flag" size:34]];
    mark.tintColor = [HLKit leafText];
    UILabel *t = [HLKit label:28 weight:UIFontWeightBold color:[HLKit ink]];
    t.font = [HLKit rounded:28 weight:UIFontWeightBold];
    t.text = HLT(@"welcome.title");
    UILabel *m = [HLKit label:15 weight:UIFontWeightRegular color:[HLKit ink]];
    m.text = HLT(@"welcome.message");
    UIStackView *steps = [[UIStackView alloc] init];
    steps.axis = UILayoutConstraintAxisVertical;
    steps.spacing = 10;
    NSArray *icons = @[@"camera", @"square.grid.2x2", @"checkmark.seal"];
    for (NSInteger i = 0; i < 3; i++) {
        UIImageView *iv = [[UIImageView alloc] initWithImage:[HLKit symbol:icons[i] size:15]];
        iv.tintColor = [HLKit leafText];
        [iv.widthAnchor constraintEqualToConstant:24].active = YES;
        UILabel *l = [HLKit label:14 weight:UIFontWeightMedium color:[HLKit ink]];
        // Called directly: a comma inside [...] would split the HLT() macro arguments.
        l.text = [HLKit text:[NSString stringWithFormat:@"welcome.step%ld", (long)i + 1]];
        UIStackView *row = [[UIStackView alloc] initWithArrangedSubviews:@[iv, l]];
        row.spacing = 10;
        row.alignment = UIStackViewAlignmentCenter;
        [steps addArrangedSubview:row];
    }
    UIButton *add = [HLKit pill:HLT(@"welcome.addFirst") icon:@"plus" filled:YES];
    [add addAction:[UIAction actionWithHandler:^(UIAction *a) { [[self dock] presentQuickAdd]; }] forControlEvents:UIControlEventTouchUpInside];
    UIButton *sample = [HLKit pill:HLT(@"welcome.sample") icon:@"sparkles" filled:NO];
    sample.configuration = ({ UIButtonConfiguration *c = sample.configuration; c.baseBackgroundColor = [HLKit paper]; c; });
    [sample addAction:[UIAction actionWithHandler:^(UIAction *a) {
        NSString *err = nil;
        if (![[HLStore shared] loadSampleData:&err]) [HLKit tell:self title:HLT(@"common.error") message:err];
    }] forControlEvents:UIControlEventTouchUpInside];
    UILabel *note = [HLKit label:12 weight:UIFontWeightRegular color:[HLKit ash]];
    note.text = HLT(@"welcome.sampleNote");
    UIStackView *s = [[UIStackView alloc] initWithArrangedSubviews:@[mark, t, m, steps, add, sample, note]];
    s.axis = UILayoutConstraintAxisVertical;
    s.spacing = 12;
    [s setCustomSpacing:20 afterView:steps];
    s.alignment = UIStackViewAlignmentFill;
    mark.contentMode = UIViewContentModeLeft;
    s.translatesAutoresizingMaskIntoConstraints = NO;
    [card addSubview:s];
    [NSLayoutConstraint activateConstraints:@[
        [s.topAnchor constraintEqualToAnchor:card.topAnchor constant:24], [s.bottomAnchor constraintEqualToAnchor:card.bottomAnchor constant:-24],
        [s.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:22], [s.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-22]]];
    return card;
}

#pragma mark - Hero summary

- (UIView *)tile:(NSString *)caption value:(NSString *)value foot:(NSString *)foot {
    UIView *t = [[UIView alloc] init];
    t.backgroundColor = [HLKit paper];
    t.layer.cornerRadius = 18;
    t.layer.cornerCurve = kCACornerCurveContinuous;
    UILabel *c = [HLKit label:12 weight:UIFontWeightSemibold color:[HLKit ash]];
    c.text = caption;
    UILabel *v = [HLKit label:19 weight:UIFontWeightBold color:[HLKit ink]];
    v.font = [HLKit rounded:19 weight:UIFontWeightBold];
    v.text = value;
    v.adjustsFontSizeToFitWidth = YES;
    v.minimumScaleFactor = 0.6;
    v.numberOfLines = 1;
    UILabel *f = [HLKit label:11 weight:UIFontWeightRegular color:[HLKit ash]];
    f.text = foot;
    UIStackView *s = [[UIStackView alloc] initWithArrangedSubviews:@[c, v, f]];
    s.axis = UILayoutConstraintAxisVertical;
    s.spacing = 4;
    s.translatesAutoresizingMaskIntoConstraints = NO;
    [t addSubview:s];
    [NSLayoutConstraint activateConstraints:@[
        [s.topAnchor constraintEqualToAnchor:t.topAnchor constant:14], [s.bottomAnchor constraintEqualToAnchor:t.bottomAnchor constant:-14],
        [s.leadingAnchor constraintEqualToAnchor:t.leadingAnchor constant:14], [s.trailingAnchor constraintEqualToAnchor:t.trailingAnchor constant:-12]]];
    return t;
}

- (NSString *)headline:(HLMoneyBag *)bag {
    if (bag.count == 0) return @"—";
    BOOL others = NO;
    long long v = [HLInsights primary:bag otherCurrencies:&others];
    NSString *cur = bag[[HLKit defaultCurrency]] ? [HLKit defaultCurrency] : bag.allKeys.firstObject;
    if (!bag[[HLKit defaultCurrency]]) v = bag[cur].longLongValue;
    NSString *s = [HLKit money:v currency:cur];
    return bag.count > 1 ? [s stringByAppendingString:@" +"] : s;
}

- (UIView *)hero:(HLInsights *)ins {
    UIView *card = [[UIView alloc] init];
    card.backgroundColor = [HLKit mint];
    card.layer.cornerRadius = 28;
    card.layer.cornerCurve = kCACornerCurveContinuous;
    NSString *home = [HLKit trim:[[HLStore shared] household][@"name"]];
    UILabel *hi = [HLKit label:14 weight:UIFontWeightSemibold color:[HLKit leafText]];
    hi.text = home.length ? home : HLT(@"home.defaultName");
    UILabel *count = [HLKit label:46 weight:UIFontWeightHeavy color:[HLKit ink]];
    count.font = [HLKit rounded:46 weight:UIFontWeightHeavy];
    count.text = [NSString stringWithFormat:@"%ld", (long)ins.itemCount];
    UILabel *unit = [HLKit label:15 weight:UIFontWeightMedium color:[HLKit ash]];
    unit.text = HLT(@"home.itemsTracked");
    UIStackView *countRow = [[UIStackView alloc] initWithArrangedSubviews:@[count, unit]];
    countRow.spacing = 8;
    countRow.alignment = UIStackViewAlignmentLastBaseline;
    // The ring shows how much of the inventory has a current value entered — a nudge, not a score.
    CGFloat filled = ins.itemCount ? (CGFloat)ins.valuedCount / ins.itemCount : 0;
    UIView *ring = [HLKit ring:filled color:[HLKit leaf] diameter:58 line:7];
    UILabel *pct = [HLKit label:12 weight:UIFontWeightBold color:[HLKit leafText]];
    pct.font = [HLKit rounded:13 weight:UIFontWeightBold];
    pct.text = [NSString stringWithFormat:@"%.0f%%", filled * 100];
    pct.textAlignment = NSTextAlignmentCenter;
    pct.translatesAutoresizingMaskIntoConstraints = NO;
    [ring addSubview:pct];
    [NSLayoutConstraint activateConstraints:@[[pct.centerXAnchor constraintEqualToAnchor:ring.centerXAnchor], [pct.centerYAnchor constraintEqualToAnchor:ring.centerYAnchor]]];
    ring.isAccessibilityElement = YES;
    ring.accessibilityLabel = [NSString stringWithFormat:HLT(@"home.valuedA11y"), (long)ins.valuedCount, (long)ins.itemCount];
    UIStackView *top = [[UIStackView alloc] initWithArrangedSubviews:@[[[UIStackView alloc] initWithArrangedSubviews:@[hi, countRow]], ring]];
    ((UIStackView *)top.arrangedSubviews[0]).axis = UILayoutConstraintAxisVertical;
    top.alignment = UIStackViewAlignmentCenter;
    UIView *buy = [self tile:HLT(@"home.purchaseTotal") value:[self headline:ins.purchaseTotals]
                        foot:[NSString stringWithFormat:HLT(@"home.basedOn"), (long)ins.pricedCount]];
    UIView *val = [self tile:HLT(@"home.valueTotal") value:[self headline:ins.valueTotals]
                        foot:[NSString stringWithFormat:HLT(@"home.basedOn"), (long)ins.valuedCount]];
    UIStackView *tiles = [[UIStackView alloc] initWithArrangedSubviews:@[buy, val]];
    tiles.spacing = 10;
    tiles.distribution = UIStackViewDistributionFillEqually;
    UIStackView *s = [[UIStackView alloc] initWithArrangedSubviews:@[top, tiles]];
    s.axis = UILayoutConstraintAxisVertical;
    s.spacing = 16;
    s.translatesAutoresizingMaskIntoConstraints = NO;
    [card addSubview:s];
    [NSLayoutConstraint activateConstraints:@[
        [s.topAnchor constraintEqualToAnchor:card.topAnchor constant:20], [s.bottomAnchor constraintEqualToAnchor:card.bottomAnchor constant:-14],
        [s.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:18], [s.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-14]]];
    return card;
}

#pragma mark - Quick actions

- (UIButton *)action:(NSString *)title icon:(NSString *)icon tint:(UIColor *)tint handler:(void (^)(void))handler {
    UIButtonConfiguration *c = [UIButtonConfiguration plainButtonConfiguration];
    c.image = [HLKit symbol:icon size:20];
    c.title = title;
    c.imagePlacement = NSDirectionalRectEdgeTop;
    c.imagePadding = 8;
    c.baseForegroundColor = [HLKit ink];
    c.background.backgroundColor = [HLKit paper];
    c.background.cornerRadius = 18;
    c.contentInsets = NSDirectionalEdgeInsetsMake(14, 4, 12, 4);
    c.imageColorTransformer = ^UIColor *(UIColor *x) { return tint; };
    c.titleTextAttributesTransformer = ^NSDictionary<NSAttributedStringKey, id> *(NSDictionary<NSAttributedStringKey, id> *a) {
        NSMutableDictionary *m = [a mutableCopy];
        m[NSFontAttributeName] = [UIFont systemFontOfSize:12 weight:UIFontWeightSemibold];
        return m;
    };
    UIButton *b = [UIButton buttonWithConfiguration:c primaryAction:[UIAction actionWithHandler:^(UIAction *a) { handler(); }]];
    b.titleLabel.numberOfLines = 2;
    b.titleLabel.textAlignment = NSTextAlignmentCenter;
    return b;
}

- (UIView *)quickActions {
    __weak typeof(self) ws = self;
    UIStackView *row = [[UIStackView alloc] initWithArrangedSubviews:@[
        [self action:HLT(@"home.qaAdd") icon:@"plus.circle" tint:[HLKit leafText] handler:^{ [[ws dock] presentQuickAdd]; }],
        [self action:HLT(@"home.qaStock") icon:@"checklist" tint:[UIColor colorWithRed:0.29 green:0.47 blue:0.78 alpha:1] handler:^{
            [ws.navigationController pushViewController:[[HLStocktakeController alloc] initWithSession:nil] animated:YES];
        }],
        [self action:HLT(@"home.qaRooms") icon:@"square.grid.2x2" tint:[HLKit amber] handler:^{ [[ws dock] showTab:2]; }],
        [self action:HLT(@"home.qaReports") icon:@"doc.richtext" tint:[HLKit coral] handler:^{
            [ws.navigationController pushViewController:[[HLSettingsController alloc] initWithReportsFocus] animated:YES];
        }],
    ]];
    row.spacing = 10;
    row.distribution = UIStackViewDistributionFillEqually;
    return row;
}

#pragma mark - Needs attention

- (UIView *)attention:(HLInsights *)ins {
    NSMutableArray *rows = [NSMutableArray array];
    __weak typeof(self) ws = self;
    void (^add)(NSInteger, NSString *, NSString *, UIColor *, NSDictionary *) = ^(NSInteger n, NSString *key, NSString *icon, UIColor *color, NSDictionary *filter) {
        if (n <= 0) return;
        UIButtonConfiguration *c = [UIButtonConfiguration plainButtonConfiguration];
        c.image = [HLKit symbol:icon size:16];
        c.imagePadding = 12;
        c.title = [NSString stringWithFormat:HLT(key), (long)n];
        c.baseForegroundColor = [HLKit ink];
        c.imageColorTransformer = ^UIColor *(UIColor *x) { return color; };
        c.contentInsets = NSDirectionalEdgeInsetsMake(12, 14, 12, 14);
        UIButton *b = [UIButton buttonWithConfiguration:c primaryAction:[UIAction actionWithHandler:^(UIAction *a) {
            [ws openInventory:filter title:[NSString stringWithFormat:HLT(key), (long)n]];
        }]];
        b.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeading;
        UIImageView *chev = [[UIImageView alloc] initWithImage:[HLKit symbol:@"chevron.right" size:12]];
        chev.tintColor = [HLKit ash];
        chev.translatesAutoresizingMaskIntoConstraints = NO;
        [b addSubview:chev];
        [NSLayoutConstraint activateConstraints:@[[chev.trailingAnchor constraintEqualToAnchor:b.trailingAnchor constant:-14],
                                                  [chev.centerYAnchor constraintEqualToAnchor:b.centerYAnchor]]];
        [rows addObject:b];
    };
    add(ins.warrantyExpiring, @"home.attExpiring", @"clock.badge.exclamationmark", [HLKit amber], @{HLFilterWarranty: @(HLWarrantyExpiring)});
    add(ins.underRepair, @"home.attRepair", @"wrench", [HLKit amber], @{HLFilterStatus: @(HLItemStatusRepair)});
    add(ins.warrantyExpired, @"home.attExpired", @"exclamationmark.shield", [HLKit coral], @{HLFilterWarranty: @(HLWarrantyExpired)});
    add(ins.notChecked, @"home.attUnchecked", @"questionmark.circle", [HLKit ash], @{HLFilterUnchecked: @YES});
    if (rows.count == 0) return nil;
    UIView *card = [HLKit card];
    UIStackView *list = [[UIStackView alloc] initWithArrangedSubviews:rows];
    list.axis = UILayoutConstraintAxisVertical;
    list.translatesAutoresizingMaskIntoConstraints = NO;
    [card addSubview:list];
    [NSLayoutConstraint activateConstraints:@[
        [list.topAnchor constraintEqualToAnchor:card.topAnchor constant:4], [list.bottomAnchor constraintEqualToAnchor:card.bottomAnchor constant:-4],
        [list.leadingAnchor constraintEqualToAnchor:card.leadingAnchor], [list.trailingAnchor constraintEqualToAnchor:card.trailingAnchor]]];
    UIStackView *s = [[UIStackView alloc] initWithArrangedSubviews:@[[self sectionTitle:HLT(@"home.attention")], card]];
    s.axis = UILayoutConstraintAxisVertical;
    s.spacing = 10;
    return s;
}

#pragma mark - Recent & warranties

- (void)openItem:(UIButton *)b {
    NSString *iid = b.accessibilityIdentifier;
    if (iid.length) [self.navigationController pushViewController:[[HLItemController alloc] initWithItemId:iid] animated:YES];
}

- (UIView *)recent:(NSArray<HLRow *> *)items {
    UIScrollView *sv = [[UIScrollView alloc] init];
    sv.showsHorizontalScrollIndicator = NO;
    sv.clipsToBounds = NO;
    [sv.heightAnchor constraintEqualToConstant:178].active = YES;
    UIStackView *row = [[UIStackView alloc] init];
    row.spacing = 12;
    row.translatesAutoresizingMaskIntoConstraints = NO;
    [sv addSubview:row];
    [NSLayoutConstraint activateConstraints:@[
        [row.leadingAnchor constraintEqualToAnchor:sv.contentLayoutGuide.leadingAnchor], [row.trailingAnchor constraintEqualToAnchor:sv.contentLayoutGuide.trailingAnchor],
        [row.topAnchor constraintEqualToAnchor:sv.contentLayoutGuide.topAnchor], [row.bottomAnchor constraintEqualToAnchor:sv.contentLayoutGuide.bottomAnchor],
        [row.heightAnchor constraintEqualToAnchor:sv.frameLayoutGuide.heightAnchor]]];
    HLStore *store = [HLStore shared];
    for (HLRow *it in [items subarrayWithRange:NSMakeRange(0, MIN((NSUInteger)8, items.count))]) {
        UIButton *card = [UIButton buttonWithType:UIButtonTypeCustom];
        card.backgroundColor = [HLKit paper];
        card.layer.cornerRadius = 20;
        card.layer.cornerCurve = kCACornerCurveContinuous;
        card.accessibilityIdentifier = it[@"id"];
        card.accessibilityLabel = it[@"name"];
        [card addTarget:self action:@selector(openItem:) forControlEvents:UIControlEventTouchUpInside];
        [card.widthAnchor constraintEqualToConstant:136].active = YES;
        UIImageView *iv = [[UIImageView alloc] init];
        UIImage *img = [store imageNamed:it[@"photo"]];
        iv.image = img ?: [HLKit symbol:it[@"category_icon"] ?: @"shippingbox" size:30];
        iv.contentMode = img ? UIViewContentModeScaleAspectFill : UIViewContentModeCenter;
        iv.tintColor = [HLKit leafText];
        iv.backgroundColor = [HLKit mint];
        iv.clipsToBounds = YES;
        iv.layer.cornerRadius = 16;
        iv.userInteractionEnabled = NO;
        UILabel *n = [HLKit label:14 weight:UIFontWeightSemibold color:[HLKit ink]];
        n.text = it[@"name"];
        n.numberOfLines = 1;
        UILabel *where = [HLKit label:12 weight:UIFontWeightRegular color:[HLKit ash]];
        where.numberOfLines = 1;
        where.text = it[@"room_id"] ? [store nameOf:@{@"name": it[@"room_name"] ?: @"", @"builtin": it[@"room_builtin"] ?: @""}] : HLT(@"common.unassigned");
        UIStackView *s = [[UIStackView alloc] initWithArrangedSubviews:@[iv, n, where]];
        s.axis = UILayoutConstraintAxisVertical;
        s.spacing = 6;
        s.userInteractionEnabled = NO;
        s.translatesAutoresizingMaskIntoConstraints = NO;
        [card addSubview:s];
        [NSLayoutConstraint activateConstraints:@[
            [iv.heightAnchor constraintEqualToConstant:104],
            [s.topAnchor constraintEqualToAnchor:card.topAnchor constant:8], [s.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:8],
            [s.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-8]]];
        [row addArrangedSubview:card];
    }
    UIButton *all = [UIButton buttonWithType:UIButtonTypeSystem];
    [all setTitle:HLT(@"home.seeAll") forState:UIControlStateNormal];
    all.tintColor = [HLKit leafText];
    all.titleLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightSemibold];
    __weak typeof(self) ws = self;
    [all addAction:[UIAction actionWithHandler:^(UIAction *a) { [[ws dock] showTab:1]; }] forControlEvents:UIControlEventTouchUpInside];
    UIStackView *head = [[UIStackView alloc] initWithArrangedSubviews:@[[self sectionTitle:HLT(@"home.recent")], all]];
    head.alignment = UIStackViewAlignmentLastBaseline;
    UIStackView *s = [[UIStackView alloc] initWithArrangedSubviews:@[head, sv]];
    s.axis = UILayoutConstraintAxisVertical;
    s.spacing = 10;
    return s;
}

- (UIView *)warranties:(NSArray<HLRow *> *)items {
    NSMutableArray *soon = [NSMutableArray array];
    for (HLRow *it in items) {
        if (!it[@"warranty_end"] || [it[@"status"] integerValue] == HLItemStatusDisposed) continue;
        HLWarranty w = [HLKit warrantyForEnd:[HLKit dateFromStamp:[it[@"warranty_end"] doubleValue]]];
        if (w == HLWarrantyExpiring || w == HLWarrantyActive) [soon addObject:it];
    }
    if (soon.count == 0) return nil;
    [soon sortUsingDescriptors:@[[NSSortDescriptor sortDescriptorWithKey:@"warranty_end" ascending:YES]]];
    UIView *card = [HLKit card];
    UIStackView *list = [[UIStackView alloc] init];
    list.axis = UILayoutConstraintAxisVertical;
    list.translatesAutoresizingMaskIntoConstraints = NO;
    [card addSubview:list];
    NSCalendar *cal = [NSCalendar currentCalendar];
    for (HLRow *it in [soon subarrayWithRange:NSMakeRange(0, MIN((NSUInteger)4, soon.count))]) {
        NSDate *end = [HLKit dateFromStamp:[it[@"warranty_end"] doubleValue]];
        NSInteger days = [cal components:NSCalendarUnitDay fromDate:[cal startOfDayForDate:[NSDate date]] toDate:[cal startOfDayForDate:end] options:0].day;
        HLWarranty w = [HLKit warrantyForEnd:end];
        UIButtonConfiguration *c = [UIButtonConfiguration plainButtonConfiguration];
        c.title = it[@"name"];
        c.subtitle = [NSString stringWithFormat:HLT(@"home.warrantyEnds"), [HLKit day:end]];
        c.baseForegroundColor = [HLKit ink];
        c.contentInsets = NSDirectionalEdgeInsetsMake(12, 16, 12, 96);
        UIButton *b = [UIButton buttonWithConfiguration:c primaryAction:nil];
        b.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeading;
        b.accessibilityIdentifier = it[@"id"];
        [b addTarget:self action:@selector(openItem:) forControlEvents:UIControlEventTouchUpInside];
        UILabel *chip = [HLKit chip:days == 0 ? HLT(@"home.today") : [NSString stringWithFormat:HLT(@"home.daysLeft"), (long)days] color:[HLKit warrantyColor:w]];
        chip.translatesAutoresizingMaskIntoConstraints = NO;
        [b addSubview:chip];
        [NSLayoutConstraint activateConstraints:@[[chip.trailingAnchor constraintEqualToAnchor:b.trailingAnchor constant:-14],
                                                  [chip.centerYAnchor constraintEqualToAnchor:b.centerYAnchor]]];
        [list addArrangedSubview:b];
    }
    [NSLayoutConstraint activateConstraints:@[
        [list.topAnchor constraintEqualToAnchor:card.topAnchor constant:4], [list.bottomAnchor constraintEqualToAnchor:card.bottomAnchor constant:-4],
        [list.leadingAnchor constraintEqualToAnchor:card.leadingAnchor], [list.trailingAnchor constraintEqualToAnchor:card.trailingAnchor]]];
    UIStackView *s = [[UIStackView alloc] initWithArrangedSubviews:@[[self sectionTitle:HLT(@"home.warranties")], card]];
    s.axis = UILayoutConstraintAxisVertical;
    s.spacing = 10;
    return s;
}

@end
