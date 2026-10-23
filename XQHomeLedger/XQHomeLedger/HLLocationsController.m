//
//  HLLocationsController.m
//  XQHomeLedger
//

#import "HLLocationsController.h"
#import "HLKit.h"
#import "HLStore.h"
#import "HLInsights.h"
#import "HLInventoryController.h"
#import "HLStocktakeController.h"

@interface HLLocationsController () <UICollectionViewDataSource, UICollectionViewDelegate>
@property (nonatomic, strong) UISegmentedControl *mode;   // 0 rooms, 1 categories
@property (nonatomic, strong) UICollectionView *grid;
@property (nonatomic, copy) NSArray<HLRow *> *groups;
@property (nonatomic) NSInteger unassigned;
@property (nonatomic, copy) NSDictionary<NSString *, NSDictionary *> *stats;   // id -> bucket from HLInsights
@end

@implementation HLLocationsController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = HLT(@"tab.locations");
    self.view.backgroundColor = [HLKit mist];
    UIBarButtonItem *add = [[UIBarButtonItem alloc] initWithImage:[HLKit symbol:@"plus" size:17] style:UIBarButtonItemStylePlain
                                                           target:self action:@selector(addGroup)];
    add.accessibilityLabel = HLT(@"loc.add");
    add.tintColor = [HLKit leafText];
    self.navigationItem.rightBarButtonItem = add;

    self.mode = [[UISegmentedControl alloc] initWithItems:@[HLT(@"loc.rooms"), HLT(@"loc.categories")]];
    self.mode.selectedSegmentIndex = 0;
    self.mode.selectedSegmentTintColor = [HLKit paper];
    [self.mode setTitleTextAttributes:@{NSForegroundColorAttributeName: [HLKit ink], NSFontAttributeName: [UIFont systemFontOfSize:14 weight:UIFontWeightSemibold]}
                             forState:UIControlStateSelected];
    self.mode.backgroundColor = [HLKit mint];
    [self.mode addTarget:self action:@selector(reload) forControlEvents:UIControlEventValueChanged];
    self.mode.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.mode];

    UICollectionViewCompositionalLayout *layout = [[UICollectionViewCompositionalLayout alloc] initWithSectionProvider:
        ^NSCollectionLayoutSection *(NSInteger s, id<NSCollectionLayoutEnvironment> env) {
        NSCollectionLayoutItem *it = [NSCollectionLayoutItem itemWithLayoutSize:
            [NSCollectionLayoutSize sizeWithWidthDimension:[NSCollectionLayoutDimension fractionalWidthDimension:0.5]
                                           heightDimension:[NSCollectionLayoutDimension fractionalHeightDimension:1]]];
        it.contentInsets = NSDirectionalEdgeInsetsMake(6, 6, 6, 6);
        NSCollectionLayoutGroup *g = [NSCollectionLayoutGroup horizontalGroupWithLayoutSize:
            [NSCollectionLayoutSize sizeWithWidthDimension:[NSCollectionLayoutDimension fractionalWidthDimension:1]
                                           heightDimension:[NSCollectionLayoutDimension absoluteDimension:150]] subitems:@[it, it]];
        NSCollectionLayoutSection *sec = [NSCollectionLayoutSection sectionWithGroup:g];
        sec.contentInsets = NSDirectionalEdgeInsetsMake(6, 10, 24, 10);
        return sec;
    }];
    self.grid = [[UICollectionView alloc] initWithFrame:CGRectZero collectionViewLayout:layout];
    self.grid.backgroundColor = UIColor.clearColor;
    self.grid.dataSource = self;
    self.grid.delegate = self;
    self.grid.translatesAutoresizingMaskIntoConstraints = NO;
    [self.grid registerClass:[UICollectionViewCell class] forCellWithReuseIdentifier:@"tile"];
    [self.view addSubview:self.grid];
    [NSLayoutConstraint activateConstraints:@[
        [self.mode.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:6],
        [self.mode.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:16],
        [self.mode.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-16],
        [self.mode.heightAnchor constraintEqualToConstant:36],
        [self.grid.topAnchor constraintEqualToAnchor:self.mode.bottomAnchor constant:6],
        [self.grid.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.grid.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.grid.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
    ]];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(reload) name:HLDataChangedNotification object:nil];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self reload];
}

- (BOOL)rooms {
    return self.mode.selectedSegmentIndex == 0;
}

- (void)reload {
    if (!self.isViewLoaded) return;
    HLStore *store = [HLStore shared];
    self.groups = [self rooms] ? [store rooms] : [store categories];
    HLInsights *ins = [[HLInsights alloc] initWithItems:[store allItems]];
    NSMutableDictionary *m = [NSMutableDictionary dictionary];
    for (NSDictionary *b in [self rooms] ? ins.byRoom : ins.byCategory) m[b[@"key"]] = b;
    self.stats = m;
    self.unassigned = [m[@""][@"count"] integerValue];
    [self.grid reloadData];
}

#pragma mark - Grid

- (NSInteger)collectionView:(UICollectionView *)cv numberOfItemsInSection:(NSInteger)s {
    // Groups, then "Unassigned" when it has items, then the add tile.
    return self.groups.count + (self.unassigned ? 1 : 0) + 1;
}

- (UICollectionViewCell *)collectionView:(UICollectionView *)cv cellForItemAtIndexPath:(NSIndexPath *)ip {
    UICollectionViewCell *c = [cv dequeueReusableCellWithReuseIdentifier:@"tile" forIndexPath:ip];
    for (UIView *v in c.contentView.subviews) [v removeFromSuperview];
    c.contentView.layer.cornerRadius = 24;
    c.contentView.layer.cornerCurve = kCACornerCurveContinuous;
    NSInteger n = (NSInteger)self.groups.count;
    BOOL isAdd = ip.item == n + (self.unassigned ? 1 : 0);
    if (isAdd) {
        c.contentView.backgroundColor = UIColor.clearColor;
        c.contentView.layer.borderWidth = 1.5;
        c.contentView.layer.borderColor = [[HLKit leaf] colorWithAlphaComponent:0.45].CGColor;
        UIImageView *iv = [[UIImageView alloc] initWithImage:[HLKit symbol:@"plus" size:24]];
        iv.tintColor = [HLKit leafText];
        UILabel *l = [HLKit label:14 weight:UIFontWeightSemibold color:[HLKit leafText]];
        l.text = [self rooms] ? HLT(@"loc.newRoom") : HLT(@"loc.newCategory");
        l.textAlignment = NSTextAlignmentCenter;
        UIStackView *s = [[UIStackView alloc] initWithArrangedSubviews:@[iv, l]];
        s.axis = UILayoutConstraintAxisVertical;
        s.alignment = UIStackViewAlignmentCenter;
        s.spacing = 8;
        s.translatesAutoresizingMaskIntoConstraints = NO;
        [c.contentView addSubview:s];
        [NSLayoutConstraint activateConstraints:@[[s.centerXAnchor constraintEqualToAnchor:c.contentView.centerXAnchor],
                                                  [s.centerYAnchor constraintEqualToAnchor:c.contentView.centerYAnchor],
                                                  [s.leadingAnchor constraintGreaterThanOrEqualToAnchor:c.contentView.leadingAnchor constant:8]]];
        c.accessibilityLabel = l.text;
        c.isAccessibilityElement = YES;
        return c;
    }
    BOOL un = ip.item == n;
    HLRow *g = un ? nil : self.groups[ip.item];
    NSDictionary *st = self.stats[un ? @"" : g[@"id"]];
    NSInteger count = [st[@"count"] integerValue];
    c.contentView.layer.borderWidth = 0;
    // Alternate soft tones so the wall reads as distinct spaces; text colour stays the same.
    NSArray *tones = @[[HLKit paper], [HLKit mint]];
    c.contentView.backgroundColor = un ? [HLKit mist] : tones[(ip.item / 2 + ip.item) % 2];
    UIView *badge = [[UIView alloc] init];
    badge.backgroundColor = c.contentView.backgroundColor == [HLKit paper] ? [HLKit mint] : [HLKit paper];
    badge.layer.cornerRadius = 16;
    [badge.widthAnchor constraintEqualToConstant:44].active = YES;
    [badge.heightAnchor constraintEqualToConstant:44].active = YES;
    UIImageView *iv = [[UIImageView alloc] initWithImage:[HLKit symbol:un ? @"questionmark.square.dashed" : (g[@"icon"] ?: @"square.grid.2x2") size:20]];
    iv.tintColor = [HLKit leafText];
    iv.translatesAutoresizingMaskIntoConstraints = NO;
    [badge addSubview:iv];
    [NSLayoutConstraint activateConstraints:@[[iv.centerXAnchor constraintEqualToAnchor:badge.centerXAnchor], [iv.centerYAnchor constraintEqualToAnchor:badge.centerYAnchor]]];
    UILabel *name = [HLKit label:16 weight:UIFontWeightBold color:[HLKit ink]];
    name.font = [HLKit rounded:16 weight:UIFontWeightBold];
    name.text = un ? HLT(@"common.unassigned") : [[HLStore shared] nameOf:g];
    name.numberOfLines = 2;
    UILabel *cnt = [HLKit label:12 weight:UIFontWeightMedium color:[HLKit ash]];
    cnt.text = [NSString stringWithFormat:HLT(@"loc.itemsN"), (long)count];
    UILabel *val = [HLKit label:13 weight:UIFontWeightSemibold color:[HLKit leafText]];
    val.font = [HLKit rounded:13 weight:UIFontWeightSemibold];
    val.numberOfLines = 1;
    val.adjustsFontSizeToFitWidth = YES;
    val.minimumScaleFactor = 0.7;
    HLMoneyBag *bag = st[@"value"];
    val.text = bag.count ? [HLInsights describe:bag] : @" ";
    UIView *spacer = [[UIView alloc] init];
    UIStackView *s = [[UIStackView alloc] initWithArrangedSubviews:@[badge, spacer, name, cnt, val]];
    s.axis = UILayoutConstraintAxisVertical;
    s.alignment = UIStackViewAlignmentLeading;
    s.spacing = 2;
    s.translatesAutoresizingMaskIntoConstraints = NO;
    [c.contentView addSubview:s];
    [NSLayoutConstraint activateConstraints:@[
        [s.topAnchor constraintEqualToAnchor:c.contentView.topAnchor constant:14], [s.bottomAnchor constraintEqualToAnchor:c.contentView.bottomAnchor constant:-14],
        [s.leadingAnchor constraintEqualToAnchor:c.contentView.leadingAnchor constant:14], [s.trailingAnchor constraintEqualToAnchor:c.contentView.trailingAnchor constant:-12]]];
    c.isAccessibilityElement = YES;
    c.accessibilityLabel = [NSString stringWithFormat:@"%@, %@", name.text, cnt.text];
    return c;
}

- (void)collectionView:(UICollectionView *)cv didSelectItemAtIndexPath:(NSIndexPath *)ip {
    NSInteger n = (NSInteger)self.groups.count;
    if (ip.item == n + (self.unassigned ? 1 : 0)) { [self addGroup]; return; }
    BOOL un = ip.item == n;
    HLRow *g = un ? nil : self.groups[ip.item];
    NSString *key = [self rooms] ? HLFilterRoom : HLFilterCategory;
    NSString *title = un ? HLT(@"common.unassigned") : [[HLStore shared] nameOf:g];
    [self.navigationController pushViewController:[[HLInventoryController alloc] initWithFilter:@{key: un ? @"" : g[@"id"]} title:title] animated:YES];
}

- (UIContextMenuConfiguration *)collectionView:(UICollectionView *)cv contextMenuConfigurationForItemAtIndexPath:(NSIndexPath *)ip point:(CGPoint)point {
    if (ip.item >= (NSInteger)self.groups.count) return nil;
    HLRow *g = self.groups[ip.item];
    __weak typeof(self) ws = self;
    return [UIContextMenuConfiguration configurationWithIdentifier:nil previewProvider:nil actionProvider:^UIMenu *(NSArray *s) {
        UIAction *stock = [UIAction actionWithTitle:HLT(@"loc.stocktake") image:[HLKit symbol:@"checklist" size:14] identifier:nil handler:^(UIAction *a) {
            [ws startStocktake:g];
        }];
        UIAction *rename = [UIAction actionWithTitle:HLT(@"loc.rename") image:[HLKit symbol:@"pencil" size:14] identifier:nil handler:^(UIAction *a) {
            [ws editGroup:g];
        }];
        UIAction *del = [UIAction actionWithTitle:HLT(@"common.delete") image:[HLKit symbol:@"trash" size:14] identifier:nil handler:^(UIAction *a) {
            [ws deleteGroup:g];
        }];
        del.attributes = UIMenuElementAttributesDestructive;
        return [UIMenu menuWithTitle:[[HLStore shared] nameOf:g] children:@[stock, rename, del]];
    }];
}

#pragma mark - Actions

- (void)startStocktake:(HLRow *)g {
    HLStore *store = [HLStore shared];
    HLRow *open = [store openStocktake];
    if (open) {
        // Only one session at a time keeps "Not Checked" meaningful.
        [HLKit ask:self title:HLT(@"stock.openTitle") message:HLT(@"stock.openMsg") action:HLT(@"stock.continue") destructive:NO then:^{
            [self.navigationController pushViewController:[[HLStocktakeController alloc] initWithSession:open[@"id"]] animated:YES];
        }];
        return;
    }
    NSString *err = nil;
    NSString *sid = [store startStocktakeScope:[self rooms] ? @"room" : @"category" value:g[@"id"] error:&err];
    if (!sid) { [HLKit tell:self title:HLT(@"common.error") message:err]; return; }
    [self.navigationController pushViewController:[[HLStocktakeController alloc] initWithSession:sid] animated:YES];
}

- (void)addGroup {
    [self editGroup:nil];
}

- (void)editGroup:(HLRow *)g {
    BOOL rooms = [self rooms];
    NSString *title = g ? HLT(@"loc.rename") : (rooms ? HLT(@"loc.newRoom") : HLT(@"loc.newCategory"));
    UIAlertController *a = [UIAlertController alertControllerWithTitle:title message:nil preferredStyle:UIAlertControllerStyleAlert];
    [a addTextFieldWithConfigurationHandler:^(UITextField *t) {
        t.placeholder = rooms ? HLT(@"loc.roomPh") : HLT(@"loc.categoryPh");
        t.text = g ? [[HLStore shared] nameOf:g] : nil;
        t.autocapitalizationType = UITextAutocapitalizationTypeWords;
    }];
    [a addAction:[UIAlertAction actionWithTitle:HLT(@"common.cancel") style:UIAlertActionStyleCancel handler:nil]];
    [a addAction:[UIAlertAction actionWithTitle:HLT(@"common.save") style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) {
        NSString *name = a.textFields.firstObject.text;
        NSString *icon = g[@"icon"] ?: (rooms ? @"house" : @"tag");
        NSString *err = nil;
        NSString *rid = rooms ? [[HLStore shared] saveRoom:g[@"id"] name:name icon:icon error:&err]
                              : [[HLStore shared] saveCategory:g[@"id"] name:name icon:icon error:&err];
        if (!rid) [HLKit tell:self title:HLT(@"common.checkInput") message:err];
    }]];
    [self presentViewController:a animated:YES completion:nil];
}

- (void)deleteGroup:(HLRow *)g {
    NSInteger n = [self.stats[g[@"id"]][@"count"] integerValue];
    NSString *msg = n ? [NSString stringWithFormat:HLT(@"loc.deleteMsgN"), (long)n] : HLT(@"loc.deleteMsg");
    [HLKit ask:self title:[NSString stringWithFormat:HLT(@"loc.deleteTitle"), [[HLStore shared] nameOf:g]] message:msg
        action:HLT(@"common.delete") destructive:YES then:^{
        NSString *err = nil;
        BOOL ok = [self rooms] ? [[HLStore shared] deleteRoom:g[@"id"] error:&err] : [[HLStore shared] deleteCategory:g[@"id"] error:&err];
        if (!ok) [HLKit tell:self title:HLT(@"common.error") message:err];
    }];
}

@end
