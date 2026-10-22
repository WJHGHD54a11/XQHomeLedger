//
//  HLDockController.m
//  XQHomeLedger
//

#import "HLDockController.h"
#import "HLKit.h"
#import "HLHomeController.h"
#import "HLInventoryController.h"
#import "HLLocationsController.h"
#import "HLStatsController.h"
#import "HLFormController.h"

static const CGFloat kDockHeight = 66;
static const CGFloat kDockInset = 18;

@interface HLDockController () <UINavigationControllerDelegate>
@property (nonatomic, strong) UIView *dock;
@property (nonatomic, strong) NSArray<UIButton *> *slots;
@property (nonatomic, strong) UIButton *addButton;
@property (nonatomic, strong) NSLayoutConstraint *dockBottom;
@property (nonatomic) BOOL dockHidden;
@end

@implementation HLDockController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [HLKit mist];
    // The system bar stays in the hierarchy for UITabBarController bookkeeping but is never shown.
    self.tabBar.hidden = YES;

    NSArray *roots = @[[[HLHomeController alloc] init], [[HLInventoryController alloc] initWithFilter:nil title:nil],
                       [[HLLocationsController alloc] init], [[HLStatsController alloc] init]];
    NSMutableArray *navs = [NSMutableArray array];
    for (UIViewController *vc in roots) {
        UINavigationController *n = [[UINavigationController alloc] initWithRootViewController:vc];
        n.delegate = self;
        n.navigationBar.prefersLargeTitles = YES;
        // Content scrolls above the floating dock instead of underneath it.
        n.additionalSafeAreaInsets = UIEdgeInsetsMake(0, 0, kDockHeight + 10, 0);
        [navs addObject:n];
    }
    self.viewControllers = navs;
    [self buildDock];
    [self activateSlot:0];
}

#pragma mark - Dock

- (void)buildDock {
    UIView *dock = [[UIView alloc] init];
    dock.translatesAutoresizingMaskIntoConstraints = NO;
    dock.backgroundColor = [HLKit paper];
    dock.layer.cornerRadius = kDockHeight / 2;
    dock.layer.cornerCurve = kCACornerCurveContinuous;
    dock.layer.shadowColor = [UIColor colorWithRed:0.08 green:0.25 blue:0.12 alpha:1].CGColor;
    dock.layer.shadowOpacity = 0.14;
    dock.layer.shadowRadius = 22;
    dock.layer.shadowOffset = CGSizeMake(0, 10);
    dock.layer.borderWidth = 0.5;
    dock.layer.borderColor = [HLKit hair].CGColor;
    [self.view addSubview:dock];
    self.dock = dock;

    NSArray *titles = @[HLT(@"tab.home"), HLT(@"tab.inventory"), HLT(@"tab.locations"), HLT(@"tab.insights")];
    NSArray *icons = @[@"house", @"shippingbox", @"square.grid.2x2", @"chart.pie"];
    NSMutableArray *slots = [NSMutableArray array];
    for (NSUInteger i = 0; i < titles.count; i++) {
        UIButtonConfiguration *c = [UIButtonConfiguration plainButtonConfiguration];
        c.image = [HLKit symbol:icons[i] size:19];
        c.title = titles[i];
        c.imagePlacement = NSDirectionalRectEdgeTop;
        c.imagePadding = 3;
        c.contentInsets = NSDirectionalEdgeInsetsMake(6, 2, 6, 2);
        c.titleTextAttributesTransformer = ^NSDictionary<NSAttributedStringKey, id> *(NSDictionary<NSAttributedStringKey, id> *a) {
            NSMutableDictionary *m = [a mutableCopy];
            m[NSFontAttributeName] = [UIFont systemFontOfSize:10.5 weight:UIFontWeightSemibold];
            return m;
        };
        UIButton *b = [UIButton buttonWithConfiguration:c primaryAction:nil];
        b.tag = (NSInteger)i;
        b.titleLabel.adjustsFontSizeToFitWidth = YES;
        b.accessibilityLabel = titles[i];
        [b addTarget:self action:@selector(slotTapped:) forControlEvents:UIControlEventTouchUpInside];
        [slots addObject:b];
    }
    self.slots = slots;

    // Raised center action: always one tap away from adding an item.
    UIButtonConfiguration *ac = [UIButtonConfiguration filledButtonConfiguration];
    ac.image = [HLKit symbol:@"plus" size:24];
    ac.baseBackgroundColor = [HLKit leaf];
    ac.baseForegroundColor = UIColor.whiteColor;
    ac.cornerStyle = UIButtonConfigurationCornerStyleCapsule;
    UIButton *add = [UIButton buttonWithConfiguration:ac primaryAction:nil];
    add.translatesAutoresizingMaskIntoConstraints = NO;
    add.accessibilityLabel = HLT(@"item.new");
    add.layer.shadowColor = [HLKit leaf].CGColor;
    add.layer.shadowOpacity = 0.45;
    add.layer.shadowRadius = 12;
    add.layer.shadowOffset = CGSizeMake(0, 6);
    [add addTarget:self action:@selector(presentQuickAdd) forControlEvents:UIControlEventTouchUpInside];
    self.addButton = add;

    UIView *gap = [[UIView alloc] init];
    UIStackView *row = [[UIStackView alloc] initWithArrangedSubviews:@[slots[0], slots[1], gap, slots[2], slots[3]]];
    row.distribution = UIStackViewDistributionFillEqually;
    row.translatesAutoresizingMaskIntoConstraints = NO;
    [dock addSubview:row];
    [dock addSubview:add];

    self.dockBottom = [dock.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor constant:-8];
    [NSLayoutConstraint activateConstraints:@[
        [dock.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:kDockInset],
        [dock.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-kDockInset],
        [dock.heightAnchor constraintEqualToConstant:kDockHeight],
        self.dockBottom,
        [row.leadingAnchor constraintEqualToAnchor:dock.leadingAnchor constant:8],
        [row.trailingAnchor constraintEqualToAnchor:dock.trailingAnchor constant:-8],
        [row.topAnchor constraintEqualToAnchor:dock.topAnchor],
        [row.bottomAnchor constraintEqualToAnchor:dock.bottomAnchor],
        [add.centerXAnchor constraintEqualToAnchor:dock.centerXAnchor],
        [add.centerYAnchor constraintEqualToAnchor:dock.topAnchor constant:6],
        [add.widthAnchor constraintEqualToConstant:58],
        [add.heightAnchor constraintEqualToConstant:58],
    ]];
}

- (void)slotTapped:(UIButton *)b {
    if ((NSInteger)self.selectedIndex == b.tag) {
        // Second tap returns to the root of that section.
        [(UINavigationController *)self.selectedViewController popToRootViewControllerAnimated:YES];
        return;
    }
    [self activateSlot:b.tag];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    // Child views are re-inserted on tab changes; keep the dock above them.
    [self.view bringSubviewToFront:self.dock];
}

- (void)activateSlot:(NSInteger)index {
    self.selectedIndex = (NSUInteger)index;
    [self.view bringSubviewToFront:self.dock];
    UINavigationController *nav = (UINavigationController *)self.selectedViewController;
    [self setDockHidden:nav.viewControllers.count > 1 animated:NO];
    for (UIButton *b in self.slots) {
        BOOL on = b.tag == index;
        UIButtonConfiguration *c = b.configuration;
        c.baseForegroundColor = on ? [HLKit leafText] : [HLKit ash];
        c.background.backgroundColor = on ? [HLKit mint] : UIColor.clearColor;
        c.background.cornerRadius = 18;
        b.configuration = c;
        b.accessibilityTraits = on ? (UIAccessibilityTraitButton | UIAccessibilityTraitSelected) : UIAccessibilityTraitButton;
    }
}

- (void)showTab:(NSInteger)index {
    if (index < 0 || index >= (NSInteger)self.viewControllers.count) return;
    [self activateSlot:index];
}

- (void)setDockHidden:(BOOL)hidden animated:(BOOL)animated {
    if (self.dockHidden == hidden) return;
    self.dockHidden = hidden;
    self.dockBottom.constant = hidden ? kDockHeight + 60 : -8;
    for (UINavigationController *n in self.viewControllers) {
        n.additionalSafeAreaInsets = UIEdgeInsetsMake(0, 0, hidden ? 0 : kDockHeight + 10, 0);
    }
    void (^change)(void) = ^{ [self.view layoutIfNeeded]; self.dock.alpha = hidden ? 0 : 1; };
    if (animated) [UIView animateWithDuration:0.28 delay:0 usingSpringWithDamping:0.9 initialSpringVelocity:0.4 options:0 animations:change completion:nil];
    else change();
}

- (void)navigationController:(UINavigationController *)nav willShowViewController:(UIViewController *)vc animated:(BOOL)animated {
    // Detail screens get the full height; the dock returns on the root screens.
    [self setDockHidden:nav.viewControllers.count > 1 animated:animated];
}

- (void)presentQuickAdd {
    [HLFormController presentItemFormFor:nil from:self];
}

@end
