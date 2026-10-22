//
//  HLStatsController.m
//  XQHomeLedger
//

#import "HLStatsController.h"
#import "HLKit.h"
#import "HLStore.h"
#import "HLInsights.h"
#import "HLInventoryController.h"

@interface HLStatsController ()
@property (nonatomic, strong) UIStackView *stack;
@property (nonatomic) BOOL includeDisposed;
@end

@implementation HLStatsController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = HLT(@"tab.insights");
    self.view.backgroundColor = [HLKit mist];
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
        [sv.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor],
        [sv.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [sv.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.stack.topAnchor constraintEqualToAnchor:sv.contentLayoutGuide.topAnchor constant:6],
        [self.stack.bottomAnchor constraintEqualToAnchor:sv.contentLayoutGuide.bottomAnchor constant:-24],
        [self.stack.leadingAnchor constraintEqualToAnchor:sv.frameLayoutGuide.leadingAnchor constant:16],
        [self.stack.trailingAnchor constraintEqualToAnchor:sv.frameLayoutGuide.trailingAnchor constant:-16],
    ]];
    [self updateToggle];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(rebuild) name:HLDataChangedNotification object:nil];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self rebuild];
}

- (void)updateToggle {
    __weak typeof(self) ws = self;
    UIAction *a = [UIAction actionWithTitle:HLT(@"insights.includeDisposed") image:nil identifier:nil handler:^(UIAction *x) {
        ws.includeDisposed = !ws.includeDisposed;
        [ws updateToggle];
        [ws rebuild];
    }];
    a.state = self.includeDisposed ? UIMenuElementStateOn : UIMenuElementStateOff;
    UIBarButtonItem *b = [[UIBarButtonItem alloc] initWithImage:[HLKit symbol:@"slider.horizontal.3" size:16] menu:[UIMenu menuWithTitle:@"" children:@[a]]];
    b.tintColor = [HLKit ink];
    b.accessibilityLabel = HLT(@"insights.options");
    self.navigationItem.rightBarButtonItem = b;
}

#pragma mark - Build

- (UIView *)card:(NSString *)title subtitle:(NSString *)subtitle body:(UIView *)body {
    UIView *card = [HLKit card];
    UILabel *t = [HLKit label:17 weight:UIFontWeightBold color:[HLKit ink]];
    t.font = [HLKit rounded:17 weight:UIFontWeightBold];
    t.text = title;
    t.accessibilityTraits = UIAccessibilityTraitHeader;
    NSMutableArray *views = [NSMutableArray arrayWithObject:t];
    if (subtitle.length) {
        UILabel *s = [HLKit label:12 weight:UIFontWeightRegular color:[HLKit ash]];
        s.text = subtitle;
        [views addObject:s];
    }
    [views addObject:body];
    UIStackView *s = [[UIStackView alloc] initWithArrangedSubviews:views];
    s.axis = UILayoutConstraintAxisVertical;
    s.spacing = 6;
    [s setCustomSpacing:14 afterView:views[views.count - 2]];
    s.translatesAutoresizingMaskIntoConstraints = NO;
    [card addSubview:s];
    [NSLayoutConstraint activateConstraints:@[
        [s.topAnchor constraintEqualToAnchor:card.topAnchor constant:18], [s.bottomAnchor constraintEqualToAnchor:card.bottomAnchor constant:-18],
        [s.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:18], [s.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-18]]];
    return card;
}

- (void)rebuild {
    if (!self.isViewLoaded) return;
    for (UIView *v in self.stack.arrangedSubviews) [v removeFromSuperview];
    NSArray *all = [[HLStore shared] allItems];
    NSArray *rows = self.includeDisposed ? all : [all filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"status != 3"]];
    if (rows.count == 0) {
        UIView *e = [HLKit emptyWithIcon:@"chart.pie" title:HLT(@"insights.emptyTitle") message:HLT(@"insights.emptyMsg") action:nil handler:nil];
        [e.heightAnchor constraintEqualToConstant:420].active = YES;
        [self.stack addArrangedSubview:e];
        return;
    }
    HLInsights *ins = [[HLInsights alloc] initWithItems:rows];
    UILabel *basis = [HLKit label:12 weight:UIFontWeightRegular color:[HLKit ash]];
    basis.text = [NSString stringWithFormat:HLT(@"insights.basis"), (long)ins.itemCount];
    [self.stack addArrangedSubview:basis];
    [self.stack addArrangedSubview:[self money:ins]];
    [self.stack addArrangedSubview:[self donut:ins]];
    [self.stack addArrangedSubview:[self rooms:ins]];
    [self.stack addArrangedSubview:[self warranty:ins]];
    [self.stack addArrangedSubview:[self repairs:ins]];
}

#pragma mark - Money

- (UIView *)figure:(NSString *)caption bag:(HLMoneyBag *)bag foot:(NSString *)foot tint:(UIColor *)tint {
    UILabel *c = [HLKit label:12 weight:UIFontWeightSemibold color:[HLKit ash]];
    c.text = caption;
    UILabel *v = [HLKit label:22 weight:UIFontWeightHeavy color:tint];
    v.font = [HLKit rounded:22 weight:UIFontWeightHeavy];
    // One line per currency; different currencies are never added together.
    v.text = bag.count ? [[HLInsights describe:bag] stringByReplacingOccurrencesOfString:@"  ·  " withString:@"\n"] : @"—";
    UILabel *f = [HLKit label:11 weight:UIFontWeightRegular color:[HLKit ash]];
    f.text = foot;
    UIStackView *s = [[UIStackView alloc] initWithArrangedSubviews:@[c, v, f]];
    s.axis = UILayoutConstraintAxisVertical;
    s.spacing = 3;
    return s;
}

- (UIView *)money:(HLInsights *)ins {
    UIView *a = [self figure:HLT(@"insights.purchase") bag:ins.purchaseTotals
                        foot:[NSString stringWithFormat:HLT(@"home.basedOn"), (long)ins.pricedCount] tint:[HLKit ink]];
    UIView *b = [self figure:HLT(@"insights.value") bag:ins.valueTotals
                        foot:[NSString stringWithFormat:HLT(@"home.basedOn"), (long)ins.valuedCount] tint:[HLKit leafText]];
    UIStackView *row = [[UIStackView alloc] initWithArrangedSubviews:@[a, b]];
    row.distribution = UIStackViewDistributionFillEqually;
    row.alignment = UIStackViewAlignmentTop;
    row.spacing = 14;
    UILabel *note = [HLKit label:11 weight:UIFontWeightRegular color:[HLKit ash]];
    note.text = HLT(@"insights.moneyNote");
    UIStackView *s = [[UIStackView alloc] initWithArrangedSubviews:@[row, note]];
    s.axis = UILayoutConstraintAxisVertical;
    s.spacing = 12;
    return [self card:HLT(@"insights.moneyTitle") subtitle:nil body:s];
}

#pragma mark - Category donut

+ (NSArray<UIColor *> *)series {
    return @[[HLKit leaf], [UIColor colorWithRed:0.29 green:0.47 blue:0.78 alpha:1], [HLKit amber], [UIColor colorWithRed:0.55 green:0.40 blue:0.78 alpha:1],
             [HLKit coral], [UIColor colorWithRed:0.16 green:0.62 blue:0.64 alpha:1], [HLKit ash]];
}

- (UIView *)donut:(HLInsights *)ins {
    NSArray *cats = ins.byCategory;
    NSArray *colors = [HLStatsController series];
    // Top six categories, the rest grouped as "Other" so the legend stays readable.
    NSMutableArray *slices = [NSMutableArray array];
    NSInteger rest = 0;
    for (NSUInteger i = 0; i < cats.count; i++) {
        if (i < 6) [slices addObject:@{@"name": cats[i][@"name"], @"count": cats[i][@"count"]}];
        else rest += [cats[i][@"count"] integerValue];
    }
    if (rest) [slices addObject:@{@"name": HLT(@"insights.otherSlice"), @"count": @(rest)}];
    CGFloat d = 150, line = 22;
    UIView *chart = [[UIView alloc] init];
    [chart.widthAnchor constraintEqualToConstant:d].active = YES;
    [chart.heightAnchor constraintEqualToConstant:d].active = YES;
    CGFloat total = MAX(1, ins.itemCount), start = -M_PI_2;
    CGPoint center = CGPointMake(d / 2, d / 2);
    for (NSUInteger i = 0; i < slices.count; i++) {
        CGFloat frac = [slices[i][@"count"] floatValue] / total;
        CGFloat end = start + frac * 2 * M_PI;
        CAShapeLayer *arc = [CAShapeLayer layer];
        // A hairline gap between slices keeps adjacent colours distinguishable.
        CGFloat gap = slices.count > 1 ? 0.025 : 0;
        arc.path = [UIBezierPath bezierPathWithArcCenter:center radius:(d - line) / 2 startAngle:start + gap endAngle:MAX(start + gap, end - gap) clockwise:YES].CGPath;
        arc.strokeColor = ((UIColor *)colors[i % colors.count]).CGColor;
        arc.fillColor = UIColor.clearColor.CGColor;
        arc.lineWidth = line;
        [chart.layer addSublayer:arc];
        start = end;
    }
    UILabel *mid = [HLKit label:26 weight:UIFontWeightHeavy color:[HLKit ink]];
    mid.font = [HLKit rounded:26 weight:UIFontWeightHeavy];
    mid.text = [NSString stringWithFormat:@"%ld", (long)ins.itemCount];
    mid.textAlignment = NSTextAlignmentCenter;
    mid.translatesAutoresizingMaskIntoConstraints = NO;
    [chart addSubview:mid];
    [NSLayoutConstraint activateConstraints:@[[mid.centerXAnchor constraintEqualToAnchor:chart.centerXAnchor], [mid.centerYAnchor constraintEqualToAnchor:chart.centerYAnchor]]];
    UIStackView *legend = [[UIStackView alloc] init];
    legend.axis = UILayoutConstraintAxisVertical;
    legend.spacing = 7;
    NSMutableArray *spoken = [NSMutableArray array];
    for (NSUInteger i = 0; i < slices.count; i++) {
        UIView *dot = [[UIView alloc] init];
        dot.backgroundColor = colors[i % colors.count];
        dot.layer.cornerRadius = 5;
        [dot.widthAnchor constraintEqualToConstant:10].active = YES;
        [dot.heightAnchor constraintEqualToConstant:10].active = YES;
        UILabel *l = [HLKit label:13 weight:UIFontWeightMedium color:[HLKit ink]];
        l.numberOfLines = 1;
        l.text = [NSString stringWithFormat:@"%@  %@", slices[i][@"name"], slices[i][@"count"]];
        [spoken addObject:l.text];
        UIStackView *r = [[UIStackView alloc] initWithArrangedSubviews:@[dot, l]];
        r.spacing = 8;
        r.alignment = UIStackViewAlignmentCenter;
        [legend addArrangedSubview:r];
    }
    chart.isAccessibilityElement = YES;
    chart.accessibilityLabel = [spoken componentsJoinedByString:@", "];
    UIStackView *row = [[UIStackView alloc] initWithArrangedSubviews:@[chart, legend]];
    row.spacing = 18;
    row.alignment = UIStackViewAlignmentCenter;
    return [self card:HLT(@"insights.byCategory") subtitle:HLT(@"insights.byCategorySub") body:row];
}

#pragma mark - Rooms

- (UIView *)bar:(CGFloat)fraction color:(UIColor *)color {
    UIView *track = [[UIView alloc] init];
    track.backgroundColor = [HLKit mist];
    track.layer.cornerRadius = 5;
    [track.heightAnchor constraintEqualToConstant:10].active = YES;
    UIView *fill = [[UIView alloc] init];
    fill.backgroundColor = color;
    fill.layer.cornerRadius = 5;
    fill.translatesAutoresizingMaskIntoConstraints = NO;
    [track addSubview:fill];
    [NSLayoutConstraint activateConstraints:@[
        [fill.leadingAnchor constraintEqualToAnchor:track.leadingAnchor], [fill.topAnchor constraintEqualToAnchor:track.topAnchor],
        [fill.bottomAnchor constraintEqualToAnchor:track.bottomAnchor],
        [fill.widthAnchor constraintEqualToAnchor:track.widthAnchor multiplier:MAX(0.02, MIN(1, fraction))]]];
    return track;
}

- (UIView *)rooms:(HLInsights *)ins {
    UIStackView *list = [[UIStackView alloc] init];
    list.axis = UILayoutConstraintAxisVertical;
    list.spacing = 12;
    NSInteger maxCount = MAX(1, [ins.byRoom.firstObject[@"count"] integerValue]);
    for (NSDictionary *b in ins.byRoom) {
        UILabel *n = [HLKit label:14 weight:UIFontWeightSemibold color:[HLKit ink]];
        n.text = b[@"name"];
        n.numberOfLines = 1;
        UILabel *c = [HLKit label:13 weight:UIFontWeightBold color:[HLKit ink]];
        c.font = [HLKit rounded:13 weight:UIFontWeightBold];
        c.text = [NSString stringWithFormat:@"%@", b[@"count"]];
        [c setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
        UIStackView *head = [[UIStackView alloc] initWithArrangedSubviews:@[n, c]];
        UILabel *v = [HLKit label:11 weight:UIFontWeightRegular color:[HLKit ash]];
        HLMoneyBag *bag = b[@"value"];
        v.text = bag.count ? [NSString stringWithFormat:HLT(@"insights.roomValue"), [HLInsights describe:bag]] : HLT(@"insights.noValue");
        UIStackView *e = [[UIStackView alloc] initWithArrangedSubviews:@[head, [self bar:[b[@"count"] floatValue] / maxCount color:[HLKit leaf]], v]];
        e.axis = UILayoutConstraintAxisVertical;
        e.spacing = 5;
        e.isAccessibilityElement = YES;
        e.accessibilityLabel = [NSString stringWithFormat:@"%@, %@, %@", n.text, c.text, v.text];
        [list addArrangedSubview:e];
    }
    return [self card:HLT(@"insights.byRoom") subtitle:nil body:list];
}

#pragma mark - Warranty

- (UIView *)warranty:(HLInsights *)ins {
    NSArray *parts = @[@[@(ins.warrantyActive), @(HLWarrantyActive)], @[@(ins.warrantyExpiring), @(HLWarrantyExpiring)],
                       @[@(ins.warrantyExpired), @(HLWarrantyExpired)], @[@(ins.warrantyNone), @(HLWarrantyNone)]];
    UIStackView *stripe = [[UIStackView alloc] init];
    stripe.spacing = 3;
    stripe.layer.cornerRadius = 7;
    stripe.clipsToBounds = YES;
    [stripe.heightAnchor constraintEqualToConstant:14].active = YES;
    UIStackView *legend = [[UIStackView alloc] init];
    legend.axis = UILayoutConstraintAxisVertical;
    legend.spacing = 2;
    __weak typeof(self) ws = self;
    UIView *firstSeg = nil;
    CGFloat firstFrac = 0;
    for (NSArray *p in parts) {
        NSInteger n = [p[0] integerValue];
        HLWarranty w = [p[1] integerValue];
        UIColor *color = w == HLWarrantyNone ? [HLKit hair] : [HLKit warrantyColor:w];
        if (n > 0) {
            UIView *seg = [[UIView alloc] init];
            seg.backgroundColor = color;
            [stripe addArrangedSubview:seg];
            CGFloat frac = (CGFloat)n / MAX(1, ins.itemCount);
            if (!firstSeg) { firstSeg = seg; firstFrac = frac; }
            else [seg.widthAnchor constraintEqualToAnchor:firstSeg.widthAnchor multiplier:frac / firstFrac].active = YES;
        }
        UIButtonConfiguration *c = [UIButtonConfiguration plainButtonConfiguration];
        c.title = [NSString stringWithFormat:@"%@  %ld", [HLKit warrantyName:w], (long)n];
        c.image = [HLKit symbol:@"circle.fill" size:9];
        c.imagePadding = 8;
        c.baseForegroundColor = [HLKit ink];
        c.imageColorTransformer = ^UIColor *(UIColor *x) { return w == HLWarrantyNone ? [HLKit ash] : color; };
        c.contentInsets = NSDirectionalEdgeInsetsMake(6, 0, 6, 0);
        UIButton *b = [UIButton buttonWithConfiguration:c primaryAction:[UIAction actionWithHandler:^(UIAction *a) {
            [ws.navigationController pushViewController:[[HLInventoryController alloc] initWithFilter:@{HLFilterWarranty: @(w)} title:[HLKit warrantyName:w]] animated:YES];
        }]];
        b.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeading;
        b.enabled = n > 0;
        [legend addArrangedSubview:b];
    }
    UILabel *note = [HLKit label:11 weight:UIFontWeightRegular color:[HLKit ash]];
    note.text = HLT(@"insights.warrantyNote");
    UIStackView *s = [[UIStackView alloc] initWithArrangedSubviews:@[stripe, legend, note]];
    s.axis = UILayoutConstraintAxisVertical;
    s.spacing = 10;
    return [self card:HLT(@"insights.warranty") subtitle:nil body:s];
}

#pragma mark - Repairs

- (UIView *)repairs:(HLInsights *)ins {
    UIStackView *s = [[UIStackView alloc] init];
    s.axis = UILayoutConstraintAxisVertical;
    s.spacing = 10;
    UILabel *total = [HLKit label:22 weight:UIFontWeightHeavy color:[HLKit amber]];
    total.font = [HLKit rounded:22 weight:UIFontWeightHeavy];
    total.text = ins.repairTotals.count ? [[HLInsights describe:ins.repairTotals] stringByReplacingOccurrencesOfString:@"  ·  " withString:@"\n"] : @"—";
    [s addArrangedSubview:total];
    for (NSDictionary *b in ins.repairByCategory) {
        UILabel *n = [HLKit label:14 weight:UIFontWeightMedium color:[HLKit ink]];
        n.text = [NSString stringWithFormat:HLT(@"insights.repairRow"), b[@"name"], (long)[b[@"count"] integerValue]];
        UILabel *v = [HLKit label:13 weight:UIFontWeightSemibold color:[HLKit ash]];
        v.text = [b[@"cost"] count] ? [HLInsights describe:b[@"cost"]] : HLT(@"insights.noCost");
        v.textAlignment = NSTextAlignmentRight;
        UIStackView *r = [[UIStackView alloc] initWithArrangedSubviews:@[n, v]];
        r.spacing = 8;
        [s addArrangedSubview:r];
    }
    NSString *sub = [NSString stringWithFormat:HLT(@"insights.repairSub"), (long)ins.repairCount, (long)ins.underRepair];
    return [self card:HLT(@"insights.repairs") subtitle:sub body:s];
}

@end
