//
//  HLSettingsController.m
//  XQHomeLedger
//

#import "HLSettingsController.h"
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import <UserNotifications/UserNotifications.h>
#import "HLKit.h"
#import "HLStore.h"
#import "HLArchive.h"
#import "HLInsights.h"
#import "HLStocktakeController.h"

typedef NS_ENUM(NSInteger, HLSet) {
    HLSetHousehold = 0,
    HLSetPreferences,
    HLSetReports,
    HLSetData,
    HLSetPrivacy,
    HLSetCount,
};

@interface HLSettingsController () <UIDocumentPickerDelegate>
@property (nonatomic) BOOL focusReports;
@property (nonatomic, copy) NSString *notificationState;
@end

@implementation HLSettingsController

- (instancetype)init {
    return [super initWithStyle:UITableViewStyleInsetGrouped];
}

- (instancetype)initWithReportsFocus {
    if ((self = [self init])) _focusReports = YES;
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = HLT(@"settings.title");
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeNever;
    self.tableView.backgroundColor = [HLKit mist];
    self.tableView.separatorColor = [HLKit hair];
    self.notificationState = @"";
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(reload) name:HLDataChangedNotification object:nil];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self reload];
    [[UNUserNotificationCenter currentNotificationCenter] getNotificationSettingsWithCompletionHandler:^(UNNotificationSettings *s) {
        NSString *state = s.authorizationStatus == UNAuthorizationStatusAuthorized ? HLT(@"rem.allowed")
                        : (s.authorizationStatus == UNAuthorizationStatusDenied ? HLT(@"rem.denied") : HLT(@"rem.notAsked"));
        dispatch_async(dispatch_get_main_queue(), ^{ self.notificationState = state; [self.tableView reloadData]; });
    }];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    if (self.focusReports) {
        self.focusReports = NO;
        [self.tableView scrollToRowAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:HLSetReports] atScrollPosition:UITableViewScrollPositionTop animated:YES];
    }
}

- (void)reload {
    if (self.isViewLoaded) [self.tableView reloadData];
}

#pragma mark - Rows

/// Each row: @[title, detail, icon, action id, style ("" | "danger")]
- (NSArray<NSArray *> *)rows:(NSInteger)section {
    HLStore *store = [HLStore shared];
    switch (section) {
        case HLSetHousehold: {
            NSString *n = [HLKit trim:[store household][@"name"]];
            return @[@[HLT(@"settings.household"), n.length ? n : HLT(@"home.defaultName"), @"house", @"household", @""],
                     @[HLT(@"stock.title"), HLT(@"settings.stocktakeDetail"), @"checklist", @"stocktake", @""]];
        }
        case HLSetPreferences:
            return @[@[HLT(@"settings.language"), [[HLKit languageCode] isEqualToString:@"zh-Hans"] ? @"简体中文" : @"English", @"globe", @"language", @""],
                     @[HLT(@"settings.currency"), [HLKit defaultCurrency], @"dollarsign.circle", @"currency", @""],
                     @[HLT(@"settings.notifications"), self.notificationState, @"bell", @"notifications", @""]];
        case HLSetReports:
            return @[@[HLT(@"settings.pdf"), HLT(@"settings.pdfDetail"), @"doc.richtext", @"pdf", @""],
                     @[HLT(@"settings.csv"), HLT(@"settings.csvDetail"), @"tablecells", @"csv", @""],
                     @[HLT(@"settings.backup"), HLT(@"settings.backupDetail"), @"externaldrive.badge.plus", @"backup", @""],
                     @[HLT(@"settings.restore"), HLT(@"settings.restoreDetail"), @"arrow.counterclockwise", @"restore", @""]];
        case HLSetData: {
            NSMutableArray *a = [NSMutableArray array];
            if ([store hasSampleData]) [a addObject:@[HLT(@"settings.removeSample"), HLT(@"settings.removeSampleDetail"), @"sparkles", @"removeSample", @""]];
            else [a addObject:@[HLT(@"settings.loadSample"), HLT(@"settings.loadSampleDetail"), @"sparkles", @"loadSample", @""]];
            [a addObject:@[HLT(@"settings.erase"), HLT(@"settings.eraseDetail"), @"trash", @"erase", @"danger"]];
            return a;
        }
        default: {
            NSString *v = [NSBundle mainBundle].infoDictionary[@"CFBundleShortVersionString"] ?: @"";
            return @[@[HLT(@"settings.privacy"), HLT(@"settings.privacyDetail"), @"lock.shield", @"privacy", @""],
                     @[@"HomeLedger", [NSString stringWithFormat:HLT(@"settings.version"), v], @"info.circle", @"", @""]];
        }
    }
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return HLSetCount;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return @[HLT(@"settings.secHome"), HLT(@"settings.secPrefs"), HLT(@"settings.secReports"), HLT(@"settings.secData"), HLT(@"settings.secAbout")][section];
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (section == HLSetPreferences) return HLT(@"settings.currencyFooter");
    if (section == HLSetReports) return HLT(@"settings.reportsFooter");
    return nil;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return [self rows:section].count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)ip {
    UITableViewCell *c = [tableView dequeueReusableCellWithIdentifier:@"set"] ?: [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"set"];
    NSArray *r = [self rows:ip.section][ip.row];
    BOOL danger = [r[4] isEqualToString:@"danger"];
    c.backgroundColor = [HLKit paper];
    c.textLabel.text = r[0];
    c.textLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightSemibold];
    c.textLabel.textColor = danger ? [HLKit coral] : [HLKit ink];
    c.detailTextLabel.text = r[1];
    c.detailTextLabel.textColor = [HLKit ash];
    c.detailTextLabel.numberOfLines = 0;
    c.imageView.image = [HLKit symbol:r[2] size:17];
    c.imageView.tintColor = danger ? [HLKit coral] : [HLKit leafText];
    c.accessoryType = [r[3] length] ? UITableViewCellAccessoryDisclosureIndicator : UITableViewCellAccessoryNone;
    c.selectionStyle = [r[3] length] ? UITableViewCellSelectionStyleDefault : UITableViewCellSelectionStyleNone;
    return c;
}

#pragma mark - Actions

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [tableView deselectRowAtIndexPath:ip animated:YES];
    NSString *a = [self rows:ip.section][ip.row][3];
    UIView *src = [tableView cellForRowAtIndexPath:ip] ?: self.view;
    if ([a isEqualToString:@"household"]) [self renameHousehold];
    else if ([a isEqualToString:@"stocktake"]) [self.navigationController pushViewController:[[HLStocktakeController alloc] initWithSession:nil] animated:YES];
    else if ([a isEqualToString:@"language"]) [self pickLanguage:src];
    else if ([a isEqualToString:@"currency"]) [self pickCurrency:src];
    else if ([a isEqualToString:@"notifications"]) [self notifications];
    else if ([a isEqualToString:@"pdf"] || [a isEqualToString:@"csv"]) [self pickScopeFor:a src:src];
    else if ([a isEqualToString:@"backup"]) [self makeBackup:src];
    else if ([a isEqualToString:@"restore"]) [self pickBackup];
    else if ([a isEqualToString:@"loadSample"]) [self sample:YES];
    else if ([a isEqualToString:@"removeSample"]) [self sample:NO];
    else if ([a isEqualToString:@"erase"]) [self erase];
    else if ([a isEqualToString:@"privacy"]) [self privacy];
}

- (void)sheet:(NSString *)title options:(NSArray<NSString *> *)opts src:(UIView *)src pick:(void (^)(NSInteger))pick {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:title message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    [opts enumerateObjectsUsingBlock:^(NSString *o, NSUInteger i, BOOL *stop) {
        [a addAction:[UIAlertAction actionWithTitle:o style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) { pick((NSInteger)i); }]];
    }];
    [a addAction:[UIAlertAction actionWithTitle:HLT(@"common.cancel") style:UIAlertActionStyleCancel handler:nil]];
    a.popoverPresentationController.sourceView = src;
    a.popoverPresentationController.sourceRect = src.bounds;
    [self presentViewController:a animated:YES completion:nil];
}

- (void)renameHousehold {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:HLT(@"settings.household") message:nil preferredStyle:UIAlertControllerStyleAlert];
    [a addTextFieldWithConfigurationHandler:^(UITextField *t) {
        t.placeholder = HLT(@"home.defaultName");
        t.text = [[HLStore shared] household][@"name"];
        t.autocapitalizationType = UITextAutocapitalizationTypeWords;
    }];
    [a addAction:[UIAlertAction actionWithTitle:HLT(@"common.cancel") style:UIAlertActionStyleCancel handler:nil]];
    [a addAction:[UIAlertAction actionWithTitle:HLT(@"common.save") style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) {
        NSString *err = nil;
        if (![[HLStore shared] renameHousehold:a.textFields.firstObject.text error:&err]) [HLKit tell:self title:HLT(@"common.error") message:err];
    }]];
    [self presentViewController:a animated:YES completion:nil];
}

- (void)pickLanguage:(UIView *)src {
    // Names in their own script so either is always recognisable.
    [self sheet:HLT(@"settings.language") options:@[@"English", @"简体中文"] src:src pick:^(NSInteger i) {
        NSString *code = i == 1 ? @"zh-Hans" : @"en";
        if (![code isEqualToString:[HLKit languageCode]]) [HLKit setLanguageCode:code];
    }];
}

- (void)pickCurrency:(UIView *)src {
    NSArray *codes = [HLKit currencyCodes];
    [self sheet:HLT(@"settings.currency") options:codes src:src pick:^(NSInteger i) {
        [HLKit setDefaultCurrency:codes[i]];
        [[HLStore shared] notifyChanged];
    }];
}

- (void)notifications {
    [[UNUserNotificationCenter currentNotificationCenter] getNotificationSettingsWithCompletionHandler:^(UNNotificationSettings *s) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (s.authorizationStatus == UNAuthorizationStatusNotDetermined) {
                [HLInsights requestPermission:^(BOOL granted) { [self viewWillAppear:NO]; if (granted) [HLInsights rescheduleAll]; }];
            } else {
                // Already decided: only the system Settings app can change it.
                NSURL *u = [NSURL URLWithString:UIApplicationOpenSettingsURLString];
                [[UIApplication sharedApplication] openURL:u options:@{} completionHandler:nil];
            }
        });
    }];
}

#pragma mark - Reports & backup

- (void)pickScopeFor:(NSString *)kind src:(UIView *)src {
    HLStore *store = [HLStore shared];
    void (^run)(NSString *, NSString *) = ^(NSString *scope, NSString *value) {
        NSString *err = nil;
        NSURL *u = [kind isEqualToString:@"pdf"] ? [HLArchive pdfForScope:scope value:value error:&err] : [HLArchive csvForScope:scope value:value error:&err];
        if (!u) { [HLKit tell:self title:HLT(@"report.err.title") message:err]; return; }
        [self share:u from:src done:nil];
    };
    [self sheet:HLT(@"report.chooseScope") options:@[HLT(@"report.scopeAll"), HLT(@"stock.scopeRoom"), HLT(@"stock.scopeCategory")] src:src pick:^(NSInteger i) {
        if (i == 0) { run(@"all", nil); return; }
        NSArray *rows = i == 1 ? [store rooms] : [store categories];
        NSMutableArray *names = [NSMutableArray array];
        for (HLRow *r in rows) [names addObject:[NSString stringWithFormat:@"%@ (%@)", [store nameOf:r], r[@"item_count"] ?: @0]];
        [self sheet:i == 1 ? HLT(@"stock.scopeRoom") : HLT(@"stock.scopeCategory") options:names src:src pick:^(NSInteger j) {
            run(i == 1 ? @"room" : @"category", rows[j][@"id"]);
        }];
    }];
}

- (void)share:(NSURL *)url from:(UIView *)src done:(void (^)(BOOL completed))done {
    UIActivityViewController *a = [[UIActivityViewController alloc] initWithActivityItems:@[url] applicationActivities:nil];
    __weak typeof(self) ws = self;
    a.completionWithItemsHandler = ^(UIActivityType type, BOOL completed, NSArray *items, NSError *error) {
        if (error) [HLKit tell:ws title:HLT(@"report.err.title") message:error.localizedDescription];
        if (done) done(completed && !error);
    };
    a.popoverPresentationController.sourceView = src;
    a.popoverPresentationController.sourceRect = src.bounds;
    [self presentViewController:a animated:YES completion:nil];
}

- (void)makeBackup:(UIView *)src {
    NSString *err = nil;
    NSURL *u = [HLArchive backup:&err];
    if (!u) { [HLKit tell:self title:HLT(@"backup.err.title") message:err]; return; }
    [self share:u from:src done:^(BOOL completed) {
        // Confirmed only when the system reports the save / share finished.
        if (completed) [HLKit tell:self title:HLT(@"backup.doneTitle") message:u.lastPathComponent];
    }];
}

- (void)pickBackup {
    UTType *t = [UTType typeWithFilenameExtension:@"homeledger"] ?: UTTypeJSON;
    UIDocumentPickerViewController *p = [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:@[t, UTTypeJSON, UTTypeData] asCopy:YES];
    p.delegate = self;
    [self presentViewController:p animated:YES completion:nil];
}

- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    NSURL *u = urls.firstObject;
    if (!u) return;
    NSString *err = nil;
    NSDictionary *s = [HLArchive inspectBackup:u error:&err];
    if (!s) { [HLKit tell:self title:HLT(@"backup.err.title") message:err]; return; }
    NSString *msg = [NSString stringWithFormat:HLT(@"backup.summary"), [HLKit dayTime:[HLKit dateFromStamp:[s[@"created"] doubleValue]]],
                     (long)[s[@"items"] integerValue], (long)[s[@"rooms"] integerValue], (long)[s[@"categories"] integerValue],
                     (long)[s[@"maintenance"] integerValue], (long)[s[@"photos"] integerValue], (long)[s[@"duplicates"] integerValue]];
    [HLKit ask:self title:HLT(@"backup.restoreTitle") message:msg action:HLT(@"backup.restore") destructive:NO then:^{
        NSString *e2 = nil;
        NSDictionary *r = [HLArchive restoreBackup:u error:&e2];
        if (!r) { [HLKit tell:self title:HLT(@"backup.err.title") message:e2]; return; }
        [HLKit tell:self title:HLT(@"backup.restoredTitle") message:[NSString stringWithFormat:HLT(@"backup.restoredMsg"),
                                                                     (long)[r[@"added"] integerValue], (long)[r[@"skipped"] integerValue]]];
    }];
}

#pragma mark - Data

- (void)sample:(BOOL)load {
    if (load) {
        NSString *err = nil;
        if (![[HLStore shared] loadSampleData:&err]) [HLKit tell:self title:HLT(@"common.error") message:err];
        else [HLKit tell:self title:HLT(@"settings.sampleLoaded") message:HLT(@"settings.sampleLoadedMsg")];
        return;
    }
    [HLKit ask:self title:HLT(@"settings.removeSample") message:HLT(@"settings.removeSampleMsg") action:HLT(@"common.delete") destructive:YES then:^{
        NSString *err = nil;
        if (![[HLStore shared] removeSampleData:&err]) [HLKit tell:self title:HLT(@"common.error") message:err];
    }];
}

- (void)erase {
    NSInteger n = [[HLStore shared] scalar:@"SELECT COUNT(*) FROM item" args:nil];
    [HLKit ask:self title:HLT(@"settings.erase") message:[NSString stringWithFormat:HLT(@"settings.eraseMsg"), (long)n]
        action:HLT(@"settings.eraseConfirm") destructive:YES then:^{
        // Second confirmation: this cannot be undone without a backup.
        [HLKit ask:self title:HLT(@"settings.eraseAgainTitle") message:HLT(@"settings.eraseAgainMsg") action:HLT(@"settings.eraseConfirm") destructive:YES then:^{
            NSString *err = nil;
            if (![[HLStore shared] eraseAll:&err]) { [HLKit tell:self title:HLT(@"common.error") message:err]; return; }
            [[UNUserNotificationCenter currentNotificationCenter] removeAllPendingNotificationRequests];
            [HLKit tell:self title:HLT(@"settings.erasedTitle") message:nil];
        }];
    }];
}

- (void)privacy {
    UIViewController *vc = [[UIViewController alloc] init];
    vc.title = HLT(@"settings.privacy");
    vc.view.backgroundColor = [HLKit mist];
    UIScrollView *sv = [[UIScrollView alloc] init];
    sv.translatesAutoresizingMaskIntoConstraints = NO;
    [vc.view addSubview:sv];
    UIStackView *s = [[UIStackView alloc] init];
    s.axis = UILayoutConstraintAxisVertical;
    s.spacing = 14;
    s.translatesAutoresizingMaskIntoConstraints = NO;
    [sv addSubview:s];
    NSArray *blocks = @[@[@"iphone", @"privacy.localTitle", @"privacy.localBody"], @[@"wifi.slash", @"privacy.netTitle", @"privacy.netBody"],
                        @[@"camera", @"privacy.permTitle", @"privacy.permBody"], @[@"square.and.arrow.up", @"privacy.exportTitle", @"privacy.exportBody"],
                        @[@"trash", @"privacy.deleteTitle", @"privacy.deleteBody"]];
    for (NSArray *b in blocks) {
        UIView *card = [HLKit card];
        UIImageView *iv = [[UIImageView alloc] initWithImage:[HLKit symbol:b[0] size:18]];
        iv.tintColor = [HLKit leafText];
        [iv.widthAnchor constraintEqualToConstant:26].active = YES;
        UILabel *t = [HLKit label:16 weight:UIFontWeightBold color:[HLKit ink]];
        t.text = HLT(b[1]);
        UILabel *m = [HLKit label:14 weight:UIFontWeightRegular color:[HLKit ink]];
        m.text = HLT(b[2]);
        UIStackView *txt = [[UIStackView alloc] initWithArrangedSubviews:@[t, m]];
        txt.axis = UILayoutConstraintAxisVertical;
        txt.spacing = 4;
        UIStackView *row = [[UIStackView alloc] initWithArrangedSubviews:@[iv, txt]];
        row.spacing = 12;
        row.alignment = UIStackViewAlignmentTop;
        row.translatesAutoresizingMaskIntoConstraints = NO;
        [card addSubview:row];
        [NSLayoutConstraint activateConstraints:@[
            [row.topAnchor constraintEqualToAnchor:card.topAnchor constant:16], [row.bottomAnchor constraintEqualToAnchor:card.bottomAnchor constant:-16],
            [row.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:16], [row.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-16]]];
        [s addArrangedSubview:card];
    }
    [NSLayoutConstraint activateConstraints:@[
        [sv.topAnchor constraintEqualToAnchor:vc.view.safeAreaLayoutGuide.topAnchor], [sv.bottomAnchor constraintEqualToAnchor:vc.view.bottomAnchor],
        [sv.leadingAnchor constraintEqualToAnchor:vc.view.leadingAnchor], [sv.trailingAnchor constraintEqualToAnchor:vc.view.trailingAnchor],
        [s.topAnchor constraintEqualToAnchor:sv.contentLayoutGuide.topAnchor constant:12], [s.bottomAnchor constraintEqualToAnchor:sv.contentLayoutGuide.bottomAnchor constant:-30],
        [s.leadingAnchor constraintEqualToAnchor:sv.frameLayoutGuide.leadingAnchor constant:16], [s.trailingAnchor constraintEqualToAnchor:sv.frameLayoutGuide.trailingAnchor constant:-16]]];
    [self.navigationController pushViewController:vc animated:YES];
}

@end
