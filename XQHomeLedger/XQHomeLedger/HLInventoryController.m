//
//  HLInventoryController.m
//  XQHomeLedger
//

#import "HLInventoryController.h"
#import "HLKit.h"
#import "HLStore.h"
#import "HLItemController.h"
#import "HLFormController.h"

NSString * const HLFilterRoom = @"room";
NSString * const HLFilterCategory = @"category";
NSString * const HLFilterStatus = @"status";
NSString * const HLFilterWarranty = @"warranty";
NSString * const HLFilterUnchecked = @"unchecked";

static NSString * const kInvSort = @"hl.inventory.sort";

@interface HLInventoryController () <UICollectionViewDataSource, UICollectionViewDelegate, UISearchResultsUpdating>
@property (nonatomic, copy, nullable) NSDictionary *fixedFilter;   // from the caller; cannot be cleared here
@property (nonatomic, strong) NSMutableDictionary *filter;         // user-chosen in this screen
@property (nonatomic) NSInteger sortMode;   // 0 updated, 1 name, 2 purchase date, 3 value
@property (nonatomic, strong) UICollectionView *grid;
@property (nonatomic, strong) UISearchController *search;
@property (nonatomic, strong) UIStackView *chips;
@property (nonatomic, copy) NSArray<HLRow *> *rows;
@property (nonatomic, strong) NSMutableSet<NSString *> *picked;
@property (nonatomic) BOOL selecting;
@property (nonatomic, strong) UIView *batchBar;
@property (nonatomic, copy) NSString *baseTitle;
@property (nonatomic, copy) NSArray<UIButton *> *batchButtons;   // need a selection
@end

@implementation HLInventoryController

- (instancetype)initWithFilter:(NSDictionary *)filter title:(NSString *)title {
    if ((self = [super initWithNibName:nil bundle:nil])) {
        _fixedFilter = [filter copy];
        _filter = [NSMutableDictionary dictionary];
        _picked = [NSMutableSet set];
        _baseTitle = [title ?: HLT(@"tab.inventory") copy];
        self.title = _baseTitle;
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [HLKit mist];
    self.sortMode = [[NSUserDefaults standardUserDefaults] integerForKey:kInvSort];
    if (self.fixedFilter) self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeNever;

    self.search = [[UISearchController alloc] initWithSearchResultsController:nil];
    self.search.searchResultsUpdater = self;
    self.search.obscuresBackgroundDuringPresentation = NO;
    self.search.searchBar.placeholder = HLT(@"inv.searchPh");
    self.search.searchBar.tintColor = [HLKit leafText];
    self.navigationItem.searchController = self.search;
    self.navigationItem.hidesSearchBarWhenScrolling = NO;
    self.definesPresentationContext = YES;
    [self updateBarButtons];

    // Filter chips scroll horizontally above the list.
    UIScrollView *chipScroll = [[UIScrollView alloc] init];
    chipScroll.showsHorizontalScrollIndicator = NO;
    chipScroll.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:chipScroll];
    self.chips = [[UIStackView alloc] init];
    self.chips.spacing = 8;
    self.chips.translatesAutoresizingMaskIntoConstraints = NO;
    [chipScroll addSubview:self.chips];

    UICollectionViewCompositionalLayout *layout = [[UICollectionViewCompositionalLayout alloc] initWithSectionProvider:
        ^NSCollectionLayoutSection *(NSInteger s, id<NSCollectionLayoutEnvironment> env) {
        NSCollectionLayoutSize *sz = [NSCollectionLayoutSize sizeWithWidthDimension:[NSCollectionLayoutDimension fractionalWidthDimension:1]
                                                                    heightDimension:[NSCollectionLayoutDimension estimatedDimension:92]];
        NSCollectionLayoutItem *it = [NSCollectionLayoutItem itemWithLayoutSize:sz];
        NSCollectionLayoutGroup *g = [NSCollectionLayoutGroup verticalGroupWithLayoutSize:sz subitems:@[it]];
        NSCollectionLayoutSection *sec = [NSCollectionLayoutSection sectionWithGroup:g];
        sec.interGroupSpacing = 10;
        sec.contentInsets = NSDirectionalEdgeInsetsMake(6, 16, 24, 16);
        return sec;
    }];
    self.grid = [[UICollectionView alloc] initWithFrame:CGRectZero collectionViewLayout:layout];
    self.grid.backgroundColor = UIColor.clearColor;
    self.grid.dataSource = self;
    self.grid.delegate = self;
    self.grid.allowsMultipleSelection = YES;
    self.grid.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;
    self.grid.translatesAutoresizingMaskIntoConstraints = NO;
    [self.grid registerClass:[UICollectionViewCell class] forCellWithReuseIdentifier:@"row"];
    [self.view addSubview:self.grid];
    [self buildBatchBar];
    [NSLayoutConstraint activateConstraints:@[
        [chipScroll.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:4],
        [chipScroll.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [chipScroll.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [chipScroll.heightAnchor constraintEqualToConstant:40],
        [self.chips.leadingAnchor constraintEqualToAnchor:chipScroll.contentLayoutGuide.leadingAnchor constant:16],
        [self.chips.trailingAnchor constraintEqualToAnchor:chipScroll.contentLayoutGuide.trailingAnchor constant:-16],
        [self.chips.topAnchor constraintEqualToAnchor:chipScroll.contentLayoutGuide.topAnchor],
        [self.chips.bottomAnchor constraintEqualToAnchor:chipScroll.contentLayoutGuide.bottomAnchor],
        [self.chips.heightAnchor constraintEqualToAnchor:chipScroll.frameLayoutGuide.heightAnchor],
        [self.grid.topAnchor constraintEqualToAnchor:chipScroll.bottomAnchor constant:4],
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

#pragma mark - Bar & menus

- (void)updateBarButtons {
    __weak typeof(self) ws = self;
    if (self.selecting) {
        self.navigationItem.rightBarButtonItems = @[[[UIBarButtonItem alloc] initWithTitle:HLT(@"common.done") style:UIBarButtonItemStyleDone
                                                                                    target:self action:@selector(toggleSelect)]];
        return;
    }
    NSArray *titles = @[HLT(@"sort.updated"), HLT(@"sort.name"), HLT(@"sort.purchase"), HLT(@"sort.value")];
    NSMutableArray *acts = [NSMutableArray array];
    [titles enumerateObjectsUsingBlock:^(NSString *t, NSUInteger i, BOOL *stop) {
        UIAction *a = [UIAction actionWithTitle:t image:nil identifier:nil handler:^(UIAction *x) {
            ws.sortMode = (NSInteger)i;
            [[NSUserDefaults standardUserDefaults] setInteger:(NSInteger)i forKey:kInvSort];
            [ws updateBarButtons];
            [ws reload];
        }];
        a.state = self.sortMode == (NSInteger)i ? UIMenuElementStateOn : UIMenuElementStateOff;
        [acts addObject:a];
    }];
    UIBarButtonItem *sort = [[UIBarButtonItem alloc] initWithImage:[HLKit symbol:@"arrow.up.arrow.down" size:16] menu:[UIMenu menuWithTitle:HLT(@"inv.sortBy") children:acts]];
    sort.accessibilityLabel = HLT(@"inv.sortBy");
    UIBarButtonItem *sel = [[UIBarButtonItem alloc] initWithTitle:HLT(@"inv.select") style:UIBarButtonItemStylePlain target:self action:@selector(toggleSelect)];
    self.navigationItem.rightBarButtonItems = @[sel, sort];
}

- (UIButton *)chipButton:(NSString *)title active:(BOOL)active menu:(UIMenu *)menu {
    UIButtonConfiguration *c = [UIButtonConfiguration filledButtonConfiguration];
    c.title = title;
    c.image = [HLKit symbol:@"chevron.down" size:10];
    c.imagePlacement = NSDirectionalRectEdgeTrailing;
    c.imagePadding = 4;
    c.cornerStyle = UIButtonConfigurationCornerStyleCapsule;
    c.baseBackgroundColor = active ? [HLKit leaf] : [HLKit paper];
    c.baseForegroundColor = active ? UIColor.whiteColor : [HLKit ink];
    c.contentInsets = NSDirectionalEdgeInsetsMake(7, 14, 7, 12);
    c.titleTextAttributesTransformer = ^NSDictionary<NSAttributedStringKey, id> *(NSDictionary<NSAttributedStringKey, id> *a) {
        NSMutableDictionary *m = [a mutableCopy];
        m[NSFontAttributeName] = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
        return m;
    };
    UIButton *b = [UIButton buttonWithConfiguration:c primaryAction:nil];
    b.menu = menu;
    b.showsMenuAsPrimaryAction = YES;
    return b;
}

- (UIMenu *)pickMenu:(NSString *)key titles:(NSArray *)titles values:(NSArray *)values {
    __weak typeof(self) ws = self;
    NSMutableArray *acts = [NSMutableArray array];
    UIAction *any = [UIAction actionWithTitle:HLT(@"inv.any") image:nil identifier:nil handler:^(UIAction *x) { [ws.filter removeObjectForKey:key]; [ws reload]; }];
    any.state = self.filter[key] ? UIMenuElementStateOff : UIMenuElementStateOn;
    [acts addObject:any];
    [titles enumerateObjectsUsingBlock:^(NSString *t, NSUInteger i, BOOL *stop) {
        id v = values[i];
        UIAction *a = [UIAction actionWithTitle:t image:nil identifier:nil handler:^(UIAction *x) { ws.filter[key] = v; [ws reload]; }];
        a.state = [self.filter[key] isEqual:v] ? UIMenuElementStateOn : UIMenuElementStateOff;
        [acts addObject:a];
    }];
    return [UIMenu menuWithTitle:@"" children:acts];
}

- (NSString *)chipTitle:(NSString *)base key:(NSString *)key titles:(NSArray *)titles values:(NSArray *)values {
    if (!self.filter[key]) return base;
    NSUInteger i = [values indexOfObject:self.filter[key]];
    return i == NSNotFound ? base : titles[i];
}

- (void)rebuildChips {
    for (UIView *v in self.chips.arrangedSubviews) [v removeFromSuperview];
    HLStore *store = [HLStore shared];
    NSMutableArray *rt = [NSMutableArray array], *rv = [NSMutableArray array];
    for (HLRow *r in [store rooms]) { [rt addObject:[store nameOf:r]]; [rv addObject:r[@"id"]]; }
    [rt addObject:HLT(@"common.unassigned")]; [rv addObject:@""];
    NSMutableArray *ct = [NSMutableArray array], *cv = [NSMutableArray array];
    for (HLRow *c in [store categories]) { [ct addObject:[store nameOf:c]]; [cv addObject:c[@"id"]]; }
    [ct addObject:HLT(@"common.unassigned")]; [cv addObject:@""];
    NSArray *st = @[[HLKit statusName:0], [HLKit statusName:1], [HLKit statusName:2], [HLKit statusName:3]], *sv = @[@0, @1, @2, @3];
    NSArray *wt = @[[HLKit warrantyName:HLWarrantyActive], [HLKit warrantyName:HLWarrantyExpiring], [HLKit warrantyName:HLWarrantyExpired], [HLKit warrantyName:HLWarrantyNone]];
    NSArray *wv = @[@(HLWarrantyActive), @(HLWarrantyExpiring), @(HLWarrantyExpired), @(HLWarrantyNone)];
    NSArray *chk = @[HLT(@"check.not"), HLT(@"check.done")], *chkv = @[@YES, @NO];
    NSArray *specs = @[@[HLFilterRoom, HLT(@"field.room"), rt, rv], @[HLFilterCategory, HLT(@"field.category"), ct, cv],
                       @[HLFilterStatus, HLT(@"field.status"), st, sv], @[HLFilterWarranty, HLT(@"field.warranty"), wt, wv],
                       @[HLFilterUnchecked, HLT(@"field.check"), chk, chkv]];
    for (NSArray *sp in specs) {
        if (self.fixedFilter[sp[0]]) continue;   // already fixed by the screen that opened this list
        [self.chips addArrangedSubview:[self chipButton:[self chipTitle:sp[1] key:sp[0] titles:sp[2] values:sp[3]]
                                                 active:self.filter[sp[0]] != nil
                                                   menu:[self pickMenu:sp[0] titles:sp[2] values:sp[3]]]];
    }
    if (self.filter.count) {
        UIButton *clear = [UIButton buttonWithType:UIButtonTypeSystem];
        [clear setTitle:HLT(@"inv.clearFilters") forState:UIControlStateNormal];
        clear.tintColor = [HLKit coral];
        clear.titleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
        __weak typeof(self) ws = self;
        [clear addAction:[UIAction actionWithHandler:^(UIAction *a) { [ws.filter removeAllObjects]; [ws reload]; }] forControlEvents:UIControlEventTouchUpInside];
        [self.chips addArrangedSubview:clear];
    }
}

#pragma mark - Data

- (NSString *)roomNameOf:(HLRow *)r {
    return r[@"room_id"] ? [[HLStore shared] nameOf:@{@"name": r[@"room_name"] ?: @"", @"builtin": r[@"room_builtin"] ?: @""}] : HLT(@"common.unassigned");
}

- (BOOL)row:(HLRow *)r matches:(NSDictionary *)f query:(NSString *)q {
    if (f[HLFilterRoom] && ![(r[@"room_id"] ?: @"") isEqualToString:f[HLFilterRoom]]) return NO;
    if (f[HLFilterCategory] && ![(r[@"category_id"] ?: @"") isEqualToString:f[HLFilterCategory]]) return NO;
    if (f[HLFilterStatus] && [r[@"status"] integerValue] != [f[HLFilterStatus] integerValue]) return NO;
    if (f[HLFilterWarranty]) {
        HLWarranty w = [HLKit warrantyForEnd:r[@"warranty_end"] ? [HLKit dateFromStamp:[r[@"warranty_end"] doubleValue]] : nil];
        if (w != [f[HLFilterWarranty] integerValue]) return NO;
    }
    if (f[HLFilterUnchecked]) {
        BOOL unchecked = [r[@"check_state"] integerValue] == 0;
        if (unchecked != [f[HLFilterUnchecked] boolValue]) return NO;
    }
    if (q.length) {
        NSArray *hay = @[r[@"name"] ?: @"", r[@"brand"] ?: @"", r[@"model"] ?: @"", r[@"serial"] ?: @"", r[@"tags"] ?: @"",
                         r[@"spot"] ?: @"", [self roomNameOf:r]];
        BOOL hit = NO;
        for (NSString *h in hay) if ([h rangeOfString:q options:NSCaseInsensitiveSearch | NSDiacriticInsensitiveSearch].location != NSNotFound) { hit = YES; break; }
        if (!hit) return NO;
    }
    return YES;
}

- (void)reload {
    if (!self.isViewLoaded) return;
    NSMutableDictionary *f = [NSMutableDictionary dictionaryWithDictionary:self.fixedFilter ?: @{}];
    [f addEntriesFromDictionary:self.filter];
    NSString *q = [HLKit trim:self.search.searchBar.text];
    NSMutableArray *out = [NSMutableArray array];
    NSArray *all = [[HLStore shared] allItems];
    for (HLRow *r in all) if ([self row:r matches:f query:q]) [out addObject:r];
    NSArray *sort;
    switch (self.sortMode) {
        case 1: sort = @[[NSSortDescriptor sortDescriptorWithKey:@"name" ascending:YES selector:@selector(localizedStandardCompare:)]]; break;
        case 2: sort = @[[NSSortDescriptor sortDescriptorWithKey:@"purchase_date" ascending:NO]]; break;
        case 3: sort = @[[NSSortDescriptor sortDescriptorWithKey:@"value" ascending:NO]]; break;
        default: sort = @[[NSSortDescriptor sortDescriptorWithKey:@"updated" ascending:NO]]; break;
    }
    [out sortUsingDescriptors:sort];
    if (self.sortMode == 2 || self.sortMode == 3) {
        // Items without that field go last instead of looking like the smallest value.
        NSString *k = self.sortMode == 2 ? @"purchase_date" : @"value";
        NSArray *with = [out filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"%K != nil", k]];
        NSArray *without = [out filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"%K == nil", k]];
        out = [[with arrayByAddingObjectsFromArray:without] mutableCopy];
    }
    self.rows = out;
    // Drop selections that are no longer visible.
    NSSet *ids = [NSSet setWithArray:[out valueForKey:@"id"]];
    [self.picked intersectSet:ids];
    [self rebuildChips];
    if (out.count == 0) {
        __weak typeof(self) ws = self;
        self.grid.backgroundView = all.count == 0
            ? [HLKit emptyWithIcon:@"shippingbox" title:HLT(@"inv.emptyTitle") message:HLT(@"inv.emptyMsg") action:HLT(@"item.new")
                           handler:^{ [HLFormController presentItemFormFor:nil from:ws]; }]
            : [HLKit emptyWithIcon:@"magnifyingglass" title:HLT(@"common.noResults") message:HLT(@"common.noResultsMsg") action:nil handler:nil];
    } else {
        self.grid.backgroundView = nil;
    }
    [self.grid reloadData];
    [self updateBatchBar];
}

- (void)updateSearchResultsForSearchController:(UISearchController *)searchController {
    [self reload];
}

#pragma mark - Cells

- (NSInteger)collectionView:(UICollectionView *)cv numberOfItemsInSection:(NSInteger)section {
    return self.rows.count;
}

- (UICollectionViewCell *)collectionView:(UICollectionView *)cv cellForItemAtIndexPath:(NSIndexPath *)ip {
    UICollectionViewCell *cell = [cv dequeueReusableCellWithReuseIdentifier:@"row" forIndexPath:ip];
    for (UIView *v in cell.contentView.subviews) [v removeFromSuperview];
    HLRow *r = self.rows[ip.item];
    BOOL on = [self.picked containsObject:r[@"id"]];
    cell.contentView.backgroundColor = [HLKit paper];
    cell.contentView.layer.cornerRadius = 20;
    cell.contentView.layer.cornerCurve = kCACornerCurveContinuous;
    cell.contentView.layer.borderWidth = on ? 2 : 0;
    cell.contentView.layer.borderColor = [HLKit leaf].CGColor;

    UIImageView *thumb = [[UIImageView alloc] init];
    UIImage *img = [[HLStore shared] imageNamed:r[@"photo"]];
    thumb.image = img ?: [HLKit symbol:r[@"category_icon"] ?: @"shippingbox" size:22];
    thumb.contentMode = img ? UIViewContentModeScaleAspectFill : UIViewContentModeCenter;
    thumb.tintColor = [HLKit leafText];
    thumb.backgroundColor = [HLKit mint];
    thumb.clipsToBounds = YES;
    thumb.layer.cornerRadius = 14;
    [thumb.widthAnchor constraintEqualToConstant:60].active = YES;
    [thumb.heightAnchor constraintEqualToConstant:60].active = YES;

    UILabel *name = [HLKit label:16 weight:UIFontWeightSemibold color:[HLKit ink]];
    name.text = r[@"name"];
    name.numberOfLines = 2;
    UILabel *where = [HLKit label:12 weight:UIFontWeightRegular color:[HLKit ash]];
    NSMutableArray *bits = [NSMutableArray arrayWithObject:[self roomNameOf:r]];
    if ([HLKit trim:r[@"spot"]].length) [bits addObject:r[@"spot"]];
    if ([HLKit trim:r[@"brand"]].length) [bits addObject:r[@"brand"]];
    where.text = [bits componentsJoinedByString:@" · "];
    NSInteger st = [r[@"status"] integerValue];
    UIStackView *chips = [[UIStackView alloc] initWithArrangedSubviews:@[[HLKit chip:[HLKit statusName:st] color:[HLKit statusColor:st]]]];
    chips.spacing = 6;
    HLWarranty w = [HLKit warrantyForEnd:r[@"warranty_end"] ? [HLKit dateFromStamp:[r[@"warranty_end"] doubleValue]] : nil];
    if (w == HLWarrantyExpiring || w == HLWarrantyExpired) [chips addArrangedSubview:[HLKit chip:[HLKit warrantyName:w] color:[HLKit warrantyColor:w]]];
    [chips addArrangedSubview:[[UIView alloc] init]];
    UIStackView *mid = [[UIStackView alloc] initWithArrangedSubviews:@[name, where, chips]];
    mid.axis = UILayoutConstraintAxisVertical;
    mid.spacing = 4;

    UILabel *val = [HLKit label:15 weight:UIFontWeightBold color:[HLKit ink]];
    val.font = [HLKit rounded:15 weight:UIFontWeightBold];
    val.numberOfLines = 1;
    val.textAlignment = NSTextAlignmentRight;
    val.text = r[@"value"] ? [HLKit money:[r[@"value"] longLongValue] currency:r[@"value_cur"] ?: [HLKit defaultCurrency]] : @"";
    [val setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    UIImageView *mark = [[UIImageView alloc] initWithImage:[HLKit symbol:on ? @"checkmark.circle.fill" : @"circle" size:20]];
    mark.tintColor = on ? [HLKit leaf] : [HLKit hair];
    mark.hidden = !self.selecting;
    UIStackView *row = [[UIStackView alloc] initWithArrangedSubviews:self.selecting ? @[mark, thumb, mid, val] : @[thumb, mid, val]];
    row.spacing = 12;
    row.alignment = UIStackViewAlignmentCenter;
    row.translatesAutoresizingMaskIntoConstraints = NO;
    [cell.contentView addSubview:row];
    [NSLayoutConstraint activateConstraints:@[
        [row.topAnchor constraintEqualToAnchor:cell.contentView.topAnchor constant:12],
        [row.bottomAnchor constraintEqualToAnchor:cell.contentView.bottomAnchor constant:-12],
        [row.leadingAnchor constraintEqualToAnchor:cell.contentView.leadingAnchor constant:12],
        [row.trailingAnchor constraintEqualToAnchor:cell.contentView.trailingAnchor constant:-14]]];
    cell.isAccessibilityElement = YES;
    cell.accessibilityLabel = [NSString stringWithFormat:@"%@, %@, %@", r[@"name"], where.text, [HLKit statusName:st]];
    cell.accessibilityTraits = on ? UIAccessibilityTraitSelected | UIAccessibilityTraitButton : UIAccessibilityTraitButton;
    return cell;
}

- (void)collectionView:(UICollectionView *)cv didSelectItemAtIndexPath:(NSIndexPath *)ip {
    [cv deselectItemAtIndexPath:ip animated:NO];
    HLRow *r = self.rows[ip.item];
    if (self.selecting) {
        if ([self.picked containsObject:r[@"id"]]) [self.picked removeObject:r[@"id"]]; else [self.picked addObject:r[@"id"]];
        [cv reloadItemsAtIndexPaths:@[ip]];
        [self updateBatchBar];
        return;
    }
    [self.navigationController pushViewController:[[HLItemController alloc] initWithItemId:r[@"id"]] animated:YES];
}

- (UIContextMenuConfiguration *)collectionView:(UICollectionView *)cv contextMenuConfigurationForItemAtIndexPath:(NSIndexPath *)ip point:(CGPoint)point {
    if (self.selecting) return nil;
    HLRow *r = self.rows[ip.item];
    __weak typeof(self) ws = self;
    return [UIContextMenuConfiguration configurationWithIdentifier:nil previewProvider:nil actionProvider:^UIMenu *(NSArray *s) {
        UIAction *edit = [UIAction actionWithTitle:HLT(@"common.edit") image:[HLKit symbol:@"pencil" size:14] identifier:nil handler:^(UIAction *a) {
            [HLFormController presentItemFormFor:[[HLStore shared] itemWithId:r[@"id"]] from:ws];
        }];
        UIAction *dup = [UIAction actionWithTitle:HLT(@"item.duplicate") image:[HLKit symbol:@"plus.square.on.square" size:14] identifier:nil handler:^(UIAction *a) {
            NSString *err = nil;
            if (![[HLStore shared] duplicateItem:r[@"id"] error:&err]) [HLKit tell:ws title:HLT(@"common.error") message:err];
        }];
        UIAction *del = [UIAction actionWithTitle:HLT(@"common.delete") image:[HLKit symbol:@"trash" size:14] identifier:nil handler:^(UIAction *a) {
            [ws confirmDelete:@[r[@"id"]]];
        }];
        del.attributes = UIMenuElementAttributesDestructive;
        return [UIMenu menuWithTitle:r[@"name"] ?: @"" children:@[edit, dup, del]];
    }];
}

#pragma mark - Batch

- (void)toggleSelect {
    self.selecting = !self.selecting;
    [self.picked removeAllObjects];
    [self updateBarButtons];
    [self.grid reloadData];
    [self updateBatchBar];
}

- (void)buildBatchBar {
    UIView *bar = [HLKit card];
    bar.translatesAutoresizingMaskIntoConstraints = NO;
    bar.hidden = YES;
    [self.view addSubview:bar];
    self.batchBar = bar;
    __weak typeof(self) ws = self;
    UIButton *all = [self barButton:@"checklist" title:HLT(@"inv.selectAll") handler:^(UIView *src) {
        if (ws.picked.count == ws.rows.count) [ws.picked removeAllObjects];
        else [ws.picked addObjectsFromArray:[ws.rows valueForKey:@"id"]];
        [ws.grid reloadData];
        [ws updateBatchBar];
    }];
    UIButton *move = [self barButton:@"arrow.right.square" title:HLT(@"inv.move") handler:^(UIView *src) { [ws batchMove:src]; }];
    UIButton *status = [self barButton:@"flag" title:HLT(@"field.status") handler:^(UIView *src) { [ws batchStatus:src]; }];
    UIButton *del = [self barButton:@"trash" title:HLT(@"common.delete") handler:^(UIView *src) { [ws confirmDelete:ws.picked.allObjects]; }];
    del.tintColor = [HLKit coral];
    self.batchButtons = @[move, status, del];
    UIStackView *row = [[UIStackView alloc] initWithArrangedSubviews:@[all, move, status, del]];
    row.distribution = UIStackViewDistributionFillEqually;
    row.translatesAutoresizingMaskIntoConstraints = NO;
    [bar addSubview:row];
    [NSLayoutConstraint activateConstraints:@[
        [bar.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:16],
        [bar.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-16],
        [bar.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor constant:-8],
        [bar.heightAnchor constraintEqualToConstant:64],
        [row.topAnchor constraintEqualToAnchor:bar.topAnchor], [row.bottomAnchor constraintEqualToAnchor:bar.bottomAnchor],
        [row.leadingAnchor constraintEqualToAnchor:bar.leadingAnchor constant:6], [row.trailingAnchor constraintEqualToAnchor:bar.trailingAnchor constant:-6]]];
}

- (UIButton *)barButton:(NSString *)icon title:(NSString *)title handler:(void (^)(UIView *src))handler {
    UIButtonConfiguration *c = [UIButtonConfiguration plainButtonConfiguration];
    c.image = [HLKit symbol:icon size:17];
    c.title = title;
    c.imagePlacement = NSDirectionalRectEdgeTop;
    c.imagePadding = 3;
    c.titleTextAttributesTransformer = ^NSDictionary<NSAttributedStringKey, id> *(NSDictionary<NSAttributedStringKey, id> *a) {
        NSMutableDictionary *m = [a mutableCopy];
        m[NSFontAttributeName] = [UIFont systemFontOfSize:11 weight:UIFontWeightSemibold];
        return m;
    };
    UIButton *b = [UIButton buttonWithConfiguration:c primaryAction:nil];
    b.tintColor = [HLKit leafText];
    __weak UIButton *wb = b;
    [b addAction:[UIAction actionWithHandler:^(UIAction *a) { handler(wb); }] forControlEvents:UIControlEventTouchUpInside];
    return b;
}

- (void)updateBatchBar {
    self.batchBar.hidden = !self.selecting;
    [self.view bringSubviewToFront:self.batchBar];
    self.grid.contentInset = UIEdgeInsetsMake(0, 0, self.selecting ? 80 : 0, 0);
    self.title = self.selecting ? [NSString stringWithFormat:HLT(@"inv.selectedN"), (long)self.picked.count] : self.baseTitle;
    for (UIButton *b in self.batchButtons) b.enabled = self.picked.count > 0;
}

- (void)sheet:(NSString *)title options:(NSArray<NSString *> *)opts from:(UIView *)src pick:(void (^)(NSInteger))pick {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:title message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    [opts enumerateObjectsUsingBlock:^(NSString *o, NSUInteger i, BOOL *stop) {
        [a addAction:[UIAlertAction actionWithTitle:o style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) { pick((NSInteger)i); }]];
    }];
    [a addAction:[UIAlertAction actionWithTitle:HLT(@"common.cancel") style:UIAlertActionStyleCancel handler:nil]];
    a.popoverPresentationController.sourceView = src;
    a.popoverPresentationController.sourceRect = src.bounds;
    [self presentViewController:a animated:YES completion:nil];
}

- (void)batchMove:(UIView *)src {
    HLStore *store = [HLStore shared];
    NSArray *rooms = [store rooms];
    NSMutableArray *titles = [NSMutableArray array];
    for (HLRow *r in rooms) [titles addObject:[store nameOf:r]];
    [titles addObject:HLT(@"common.unassigned")];
    [self sheet:[NSString stringWithFormat:HLT(@"inv.moveN"), (long)self.picked.count] options:titles from:src pick:^(NSInteger i) {
        NSString *err = nil;
        NSString *rid = i < (NSInteger)rooms.count ? rooms[i][@"id"] : nil;
        if (![store moveItems:self.picked.allObjects toRoom:rid error:&err]) [HLKit tell:self title:HLT(@"common.error") message:err];
    }];
}

- (void)batchStatus:(UIView *)src {
    [self sheet:HLT(@"field.status") options:@[[HLKit statusName:0], [HLKit statusName:1], [HLKit statusName:2], [HLKit statusName:3]] from:src pick:^(NSInteger i) {
        NSString *err = nil;
        if (![[HLStore shared] setStatus:i forItems:self.picked.allObjects error:&err]) [HLKit tell:self title:HLT(@"common.error") message:err];
    }];
}

- (void)confirmDelete:(NSArray<NSString *> *)ids {
    if (ids.count == 0) return;
    NSInteger m = 0;
    for (NSString *iid in ids) m += [[HLStore shared] scalar:@"SELECT COUNT(*) FROM maintenance WHERE item_id = ?" args:@[iid]];
    NSString *msg = [NSString stringWithFormat:HLT(@"inv.deleteMsg"), (long)ids.count, (long)m];
    [HLKit ask:self title:[NSString stringWithFormat:HLT(@"inv.deleteTitle"), (long)ids.count] message:msg action:HLT(@"common.delete") destructive:YES then:^{
        NSString *err = nil;
        if (![[HLStore shared] deleteItems:ids error:&err]) { [HLKit tell:self title:HLT(@"common.error") message:err]; return; }
        [self.picked minusSet:[NSSet setWithArray:ids]];
    }];
}

@end
