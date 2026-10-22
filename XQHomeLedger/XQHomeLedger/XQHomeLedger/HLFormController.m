//
//  HLFormController.m
//  XQHomeLedger
//

#import "HLFormController.h"
#import <PhotosUI/PhotosUI.h>
#import "HLKit.h"

@implementation HLFieldSpec
+ (instancetype)key:(NSString *)key title:(NSString *)title type:(HLField)type {
    HLFieldSpec *f = [[HLFieldSpec alloc] init];
    f.key = key;
    f.title = title;
    f.type = type;
    return f;
}
@end

@interface HLFormController () <UITextFieldDelegate, PHPickerViewControllerDelegate, UIImagePickerControllerDelegate, UINavigationControllerDelegate>
@property (nonatomic, copy) NSArray<NSDictionary *> *sections;
@property (nonatomic, strong) NSMutableDictionary *values;
@property (nonatomic, strong) NSMutableDictionary<NSString *, UIView *> *controls;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSString *> *currencies;   // money key -> currency
@property (nonatomic, strong) NSMutableArray<NSDictionary *> *photos;   // @{@"file", @"id"?}
@property (nonatomic, strong) NSMutableArray<NSString *> *removedPhotoIds;
@property (nonatomic, strong) NSMutableArray<NSString *> *pickedFiles;
@property (nonatomic, strong) UIStackView *photoStrip;
@property (nonatomic) BOOL saved;
@end

@implementation HLFormController

- (instancetype)initWithTitle:(NSString *)title sections:(NSArray<NSDictionary *> *)sections values:(NSDictionary *)values {
    if ((self = [super initWithNibName:nil bundle:nil])) {
        self.title = title;
        _sections = [sections copy];
        _values = [NSMutableDictionary dictionaryWithDictionary:values ?: @{}];
        _controls = [NSMutableDictionary dictionary];
        _currencies = [NSMutableDictionary dictionary];
        _photos = [NSMutableArray array];
        _removedPhotoIds = [NSMutableArray array];
        _pickedFiles = [NSMutableArray array];
    }
    return self;
}

- (void)presentFrom:(UIViewController *)host {
    UINavigationController *n = [[UINavigationController alloc] initWithRootViewController:self];
    n.modalInPresentation = YES;   // unsaved input is never lost to an accidental swipe
    UIViewController *top = host;
    while (top.presentedViewController) top = top.presentedViewController;
    [top presentViewController:n animated:YES completion:nil];
}

#pragma mark - Layout

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [HLKit mist];
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:HLT(@"common.cancel") style:UIBarButtonItemStylePlain
                                                                            target:self action:@selector(cancel)];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:self.saveTitle ?: HLT(@"common.save") style:UIBarButtonItemStyleDone
                                                                             target:self action:@selector(save)];
    self.navigationController.navigationBar.tintColor = [HLKit leafText];
    for (HLRow *p in self.existingPhotos ?: @[]) [self.photos addObject:@{@"file": p[@"file"], @"id": p[@"id"]}];

    UIScrollView *sv = [[UIScrollView alloc] init];
    sv.translatesAutoresizingMaskIntoConstraints = NO;
    sv.keyboardDismissMode = UIScrollViewKeyboardDismissModeInteractive;
    sv.alwaysBounceVertical = YES;
    [self.view addSubview:sv];
    UIStackView *stack = [[UIStackView alloc] init];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 18;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [sv addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[
        [sv.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [sv.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [sv.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        // keyboardLayoutGuide (iOS 15) keeps the focused field above the keyboard.
        [sv.bottomAnchor constraintEqualToAnchor:self.view.keyboardLayoutGuide.topAnchor],
        [stack.topAnchor constraintEqualToAnchor:sv.contentLayoutGuide.topAnchor constant:12],
        [stack.bottomAnchor constraintEqualToAnchor:sv.contentLayoutGuide.bottomAnchor constant:-28],
        [stack.leadingAnchor constraintEqualToAnchor:sv.frameLayoutGuide.leadingAnchor constant:16],
        [stack.trailingAnchor constraintEqualToAnchor:sv.frameLayoutGuide.trailingAnchor constant:-16],
    ]];
    for (NSDictionary *sec in self.sections) [stack addArrangedSubview:[self sectionView:sec]];
    UILabel *req = [HLKit label:12 weight:UIFontWeightRegular color:[HLKit ash]];
    req.text = HLT(@"form.requiredNote");
    [stack addArrangedSubview:req];
}

- (UIView *)sectionView:(NSDictionary *)sec {
    UIStackView *outer = [[UIStackView alloc] init];
    outer.axis = UILayoutConstraintAxisVertical;
    outer.spacing = 8;
    UILabel *head = [HLKit label:13 weight:UIFontWeightBold color:[HLKit ash]];
    head.text = [sec[@"title"] uppercaseStringWithLocale:[HLKit locale]];
    [outer addArrangedSubview:head];
    UIView *card = [HLKit card];
    UIStackView *rows = [[UIStackView alloc] init];
    rows.axis = UILayoutConstraintAxisVertical;
    rows.spacing = 14;
    rows.translatesAutoresizingMaskIntoConstraints = NO;
    [card addSubview:rows];
    [NSLayoutConstraint activateConstraints:@[
        [rows.topAnchor constraintEqualToAnchor:card.topAnchor constant:16],
        [rows.bottomAnchor constraintEqualToAnchor:card.bottomAnchor constant:-16],
        [rows.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:16],
        [rows.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-16],
    ]];
    for (HLFieldSpec *f in sec[@"fields"]) [rows addArrangedSubview:[self fieldView:f]];
    [outer addArrangedSubview:card];
    return outer;
}

- (UITextField *)textField:(NSString *)placeholder {
    UITextField *t = [[UITextField alloc] init];
    t.font = [UIFont systemFontOfSize:16];
    t.textColor = [HLKit ink];
    t.tintColor = [HLKit leaf];
    t.backgroundColor = [HLKit mist];
    t.layer.cornerRadius = 12;
    t.leftView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 12, 1)];
    t.leftViewMode = UITextFieldViewModeAlways;
    t.clearButtonMode = UITextFieldViewModeWhileEditing;
    t.returnKeyType = UIReturnKeyDone;
    t.delegate = self;
    if (placeholder) t.attributedPlaceholder = [[NSAttributedString alloc] initWithString:placeholder attributes:@{NSForegroundColorAttributeName: [HLKit ash]}];
    [t.heightAnchor constraintEqualToConstant:46].active = YES;
    return t;
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    [textField resignFirstResponder];
    return YES;
}

- (UIView *)fieldView:(HLFieldSpec *)f {
    UIStackView *box = [[UIStackView alloc] init];
    box.axis = UILayoutConstraintAxisVertical;
    box.spacing = 6;
    UILabel *cap = [HLKit label:13 weight:UIFontWeightSemibold color:[HLKit ink]];
    cap.text = f.required ? [f.title stringByAppendingString:@" *"] : f.title;
    [box addArrangedSubview:cap];
    id v = self.values[f.key];
    switch (f.type) {
        case HLFieldText:
        case HLFieldTags: {
            UITextField *t = [self textField:f.placeholder];
            t.text = [v isKindOfClass:[NSString class]] ? v : ([v isKindOfClass:[NSArray class]] ? [v componentsJoinedByString:@", "] : nil);
            t.autocapitalizationType = f.type == HLFieldTags ? UITextAutocapitalizationTypeNone : UITextAutocapitalizationTypeSentences;
            self.controls[f.key] = t;
            [box addArrangedSubview:t];
            break;
        }
        case HLFieldLongText: {
            UITextView *t = [[UITextView alloc] init];
            t.font = [UIFont systemFontOfSize:16];
            t.textColor = [HLKit ink];
            t.tintColor = [HLKit leaf];
            t.backgroundColor = [HLKit mist];
            t.layer.cornerRadius = 12;
            t.textContainerInset = UIEdgeInsetsMake(10, 8, 10, 8);
            t.scrollEnabled = NO;
            t.text = [v isKindOfClass:[NSString class]] ? v : nil;
            [t.heightAnchor constraintGreaterThanOrEqualToConstant:84].active = YES;
            self.controls[f.key] = t;
            [box addArrangedSubview:t];
            break;
        }
        case HLFieldDate: {
            UIDatePicker *d = [[UIDatePicker alloc] init];
            d.datePickerMode = UIDatePickerModeDate;
            d.preferredDatePickerStyle = UIDatePickerStyleCompact;
            d.locale = [HLKit locale];
            d.tintColor = [HLKit leaf];
            NSDate *date = [v isKindOfClass:[NSNumber class]] ? [HLKit dateFromStamp:[v doubleValue]] : ([v isKindOfClass:[NSDate class]] ? v : nil);
            d.date = date ?: [NSDate date];
            UISwitch *sw = [[UISwitch alloc] init];
            sw.onTintColor = [HLKit leaf];
            sw.on = date != nil || f.required;
            sw.hidden = f.required;
            d.enabled = sw.on;
            d.alpha = sw.on ? 1 : 0.35;
            __weak UIDatePicker *wd = d;
            [sw addAction:[UIAction actionWithHandler:^(UIAction *a) {
                BOOL on = ((UISwitch *)a.sender).isOn;
                wd.enabled = on;
                wd.alpha = on ? 1 : 0.35;
            }] forControlEvents:UIControlEventValueChanged];
            UIView *spacer = [[UIView alloc] init];
            UIStackView *row = [[UIStackView alloc] initWithArrangedSubviews:@[d, spacer, sw]];
            row.alignment = UIStackViewAlignmentCenter;
            self.controls[f.key] = d;
            self.controls[[f.key stringByAppendingString:@"#on"]] = sw;
            [box addArrangedSubview:row];
            break;
        }
        case HLFieldMoney: {
            UITextField *t = [self textField:f.placeholder ?: @"0.00"];
            t.keyboardType = UIKeyboardTypeDecimalPad;
            NSString *cur = self.values[f.curKey] ?: [HLKit defaultCurrency];
            self.currencies[f.key] = cur;
            if ([v isKindOfClass:[NSNumber class]]) t.text = [HLKit moneyInput:[v longLongValue] currency:cur];
            UIButton *cb = [UIButton buttonWithType:UIButtonTypeSystem];
            cb.titleLabel.font = [HLKit rounded:15 weight:UIFontWeightSemibold];
            cb.tintColor = [HLKit leafText];
            cb.backgroundColor = [HLKit mint];
            cb.layer.cornerRadius = 12;
            cb.showsMenuAsPrimaryAction = YES;
            [cb.widthAnchor constraintEqualToConstant:72].active = YES;
            [self configureCurrency:cb key:f.key];
            UIStackView *row = [[UIStackView alloc] initWithArrangedSubviews:@[t, cb]];
            row.spacing = 8;
            self.controls[f.key] = t;
            [box addArrangedSubview:row];
            break;
        }
        case HLFieldPick: {
            UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
            b.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeading;
            b.backgroundColor = [HLKit mist];
            b.layer.cornerRadius = 12;
            b.titleLabel.font = [UIFont systemFontOfSize:16];
            b.tintColor = [HLKit ink];
            b.showsMenuAsPrimaryAction = YES;
            [b.heightAnchor constraintEqualToConstant:46].active = YES;
            NSUInteger idx = [f.optionValues indexOfObject:v ?: [NSNull null]];
            self.values[f.key] = idx == NSNotFound ? f.optionValues.firstObject : f.optionValues[idx];
            [self configurePick:b field:f];
            self.controls[f.key] = b;
            [box addArrangedSubview:b];
            break;
        }
        case HLFieldPhotos: {
            UIScrollView *sv = [[UIScrollView alloc] init];
            sv.showsHorizontalScrollIndicator = NO;
            [sv.heightAnchor constraintEqualToConstant:92].active = YES;
            UIStackView *strip = [[UIStackView alloc] init];
            strip.spacing = 10;
            strip.translatesAutoresizingMaskIntoConstraints = NO;
            [sv addSubview:strip];
            [NSLayoutConstraint activateConstraints:@[
                [strip.leadingAnchor constraintEqualToAnchor:sv.contentLayoutGuide.leadingAnchor],
                [strip.trailingAnchor constraintEqualToAnchor:sv.contentLayoutGuide.trailingAnchor],
                [strip.topAnchor constraintEqualToAnchor:sv.contentLayoutGuide.topAnchor],
                [strip.bottomAnchor constraintEqualToAnchor:sv.contentLayoutGuide.bottomAnchor],
                [strip.heightAnchor constraintEqualToAnchor:sv.frameLayoutGuide.heightAnchor],
            ]];
            self.photoStrip = strip;
            [self refreshPhotos];
            [box addArrangedSubview:sv];
            break;
        }
    }
    if (f.hint.length) {
        UILabel *h = [HLKit label:12 weight:UIFontWeightRegular color:[HLKit ash]];
        h.text = f.hint;
        [box addArrangedSubview:h];
    }
    return box;
}

- (void)configureCurrency:(UIButton *)b key:(NSString *)key {
    [b setTitle:self.currencies[key] forState:UIControlStateNormal];
    NSMutableArray *acts = [NSMutableArray array];
    __weak typeof(self) ws = self;
    __weak UIButton *wb = b;
    for (NSString *c in [HLKit currencyCodes]) {
        UIAction *a = [UIAction actionWithTitle:c image:nil identifier:nil handler:^(UIAction *x) {
            ws.currencies[key] = c;
            if (wb) [ws configureCurrency:wb key:key];
        }];
        a.state = [c isEqualToString:self.currencies[key]] ? UIMenuElementStateOn : UIMenuElementStateOff;
        [acts addObject:a];
    }
    b.menu = [UIMenu menuWithTitle:HLT(@"field.currency") children:acts];
}

- (void)configurePick:(UIButton *)b field:(HLFieldSpec *)f {
    NSUInteger idx = [f.optionValues indexOfObject:self.values[f.key] ?: [NSNull null]];
    if (idx == NSNotFound) idx = 0;
    [b setTitle:[@"   " stringByAppendingString:f.optionTitles[idx]] forState:UIControlStateNormal];
    NSMutableArray *acts = [NSMutableArray array];
    __weak typeof(self) ws = self;
    __weak UIButton *wb = b;
    [f.optionTitles enumerateObjectsUsingBlock:^(NSString *t, NSUInteger i, BOOL *stop) {
        UIAction *a = [UIAction actionWithTitle:t image:nil identifier:nil handler:^(UIAction *x) {
            ws.values[f.key] = f.optionValues[i];
            if (wb) [ws configurePick:wb field:f];
        }];
        a.state = i == idx ? UIMenuElementStateOn : UIMenuElementStateOff;
        [acts addObject:a];
    }];
    b.menu = [UIMenu menuWithTitle:f.title children:acts];
}

#pragma mark - Photos

- (void)refreshPhotos {
    for (UIView *v in self.photoStrip.arrangedSubviews) [v removeFromSuperview];
    UIButtonConfiguration *ac = [UIButtonConfiguration tintedButtonConfiguration];
    ac.image = [HLKit symbol:@"camera" size:20];
    ac.title = HLT(@"photo.add");
    ac.imagePlacement = NSDirectionalRectEdgeTop;
    ac.imagePadding = 4;
    ac.baseBackgroundColor = [HLKit mint];
    ac.baseForegroundColor = [HLKit leafText];
    ac.background.cornerRadius = 14;
    UIButton *add = [UIButton buttonWithConfiguration:ac primaryAction:nil];
    [add.widthAnchor constraintEqualToConstant:92].active = YES;
    [add addTarget:self action:@selector(addPhoto:) forControlEvents:UIControlEventTouchUpInside];
    [self.photoStrip addArrangedSubview:add];
    [self.photos enumerateObjectsUsingBlock:^(NSDictionary *p, NSUInteger i, BOOL *stop) {
        UIImageView *iv = [[UIImageView alloc] initWithImage:[[HLStore shared] imageNamed:p[@"file"]] ?: [HLKit symbol:@"exclamationmark.triangle" size:22]];
        iv.contentMode = iv.image.size.width > 40 ? UIViewContentModeScaleAspectFill : UIViewContentModeCenter;
        iv.tintColor = [HLKit amber];
        iv.backgroundColor = [HLKit mist];
        iv.clipsToBounds = YES;
        iv.layer.cornerRadius = 14;
        iv.userInteractionEnabled = YES;
        iv.isAccessibilityElement = YES;
        iv.accessibilityLabel = [NSString stringWithFormat:HLT(@"photo.n"), (long)i + 1];
        [iv.widthAnchor constraintEqualToConstant:92].active = YES;
        UIButton *x = [UIButton buttonWithType:UIButtonTypeSystem];
        [x setImage:[HLKit symbol:@"xmark.circle.fill" size:20] forState:UIControlStateNormal];
        x.tintColor = UIColor.whiteColor;
        x.tag = (NSInteger)i;
        x.accessibilityLabel = HLT(@"photo.remove");
        x.translatesAutoresizingMaskIntoConstraints = NO;
        [x addTarget:self action:@selector(removePhoto:) forControlEvents:UIControlEventTouchUpInside];
        [iv addSubview:x];
        [NSLayoutConstraint activateConstraints:@[[x.topAnchor constraintEqualToAnchor:iv.topAnchor constant:2],
                                                  [x.trailingAnchor constraintEqualToAnchor:iv.trailingAnchor constant:-2]]];
        [self.photoStrip addArrangedSubview:iv];
    }];
}

- (void)addPhoto:(UIView *)sender {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:HLT(@"photo.add") message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    if ([UIImagePickerController isSourceTypeAvailable:UIImagePickerControllerSourceTypeCamera]) {
        // Camera permission is requested by the system only when the user picks this.
        [a addAction:[UIAlertAction actionWithTitle:HLT(@"photo.camera") style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) {
            UIImagePickerController *p = [[UIImagePickerController alloc] init];
            p.sourceType = UIImagePickerControllerSourceTypeCamera;
            p.delegate = self;
            [self presentViewController:p animated:YES completion:nil];
        }]];
    }
    // PHPicker runs out of process and needs no photo-library permission.
    [a addAction:[UIAlertAction actionWithTitle:HLT(@"photo.library") style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) {
        PHPickerConfiguration *c = [[PHPickerConfiguration alloc] init];
        c.filter = [PHPickerFilter imagesFilter];
        c.selectionLimit = 6;
        PHPickerViewController *p = [[PHPickerViewController alloc] initWithConfiguration:c];
        p.delegate = self;
        [self presentViewController:p animated:YES completion:nil];
    }]];
    [a addAction:[UIAlertAction actionWithTitle:HLT(@"common.cancel") style:UIAlertActionStyleCancel handler:nil]];
    a.popoverPresentationController.sourceView = sender;
    a.popoverPresentationController.sourceRect = sender.bounds;
    [self presentViewController:a animated:YES completion:nil];
}

- (void)take:(UIImage *)img {
    NSString *err = nil;
    NSString *file = [[HLStore shared] storeImage:img error:&err];
    if (!file) { [HLKit tell:self title:HLT(@"common.error") message:err]; return; }
    [self.pickedFiles addObject:file];
    [self.photos addObject:@{@"file": file}];
    [self refreshPhotos];
}

- (void)picker:(PHPickerViewController *)picker didFinishPicking:(NSArray<PHPickerResult *> *)results {
    [picker dismissViewControllerAnimated:YES completion:nil];
    __block NSInteger failed = 0;
    dispatch_group_t g = dispatch_group_create();
    NSMutableArray *imgs = [NSMutableArray array];
    for (NSUInteger i = 0; i < results.count; i++) [imgs addObject:[NSNull null]];
    [results enumerateObjectsUsingBlock:^(PHPickerResult *r, NSUInteger i, BOOL *stop) {
        if (![r.itemProvider canLoadObjectOfClass:[UIImage class]]) { failed++; return; }
        dispatch_group_enter(g);
        [r.itemProvider loadObjectOfClass:[UIImage class] completionHandler:^(id<NSItemProviderReading> obj, NSError *e) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if ([(NSObject *)obj isKindOfClass:[UIImage class]]) imgs[i] = obj; else failed++;
                dispatch_group_leave(g);
            });
        }];
    }];
    dispatch_group_notify(g, dispatch_get_main_queue(), ^{
        for (id img in imgs) if ([img isKindOfClass:[UIImage class]]) [self take:img];
        if (failed) [HLKit tell:self title:HLT(@"common.error") message:[NSString stringWithFormat:HLT(@"photo.failedN"), (long)failed]];
    });
}

- (void)imagePickerController:(UIImagePickerController *)picker didFinishPickingMediaWithInfo:(NSDictionary<UIImagePickerControllerInfoKey, id> *)info {
    [picker dismissViewControllerAnimated:YES completion:nil];
    UIImage *img = info[UIImagePickerControllerOriginalImage];
    if (img) [self take:img]; else [HLKit tell:self title:HLT(@"common.error") message:HLT(@"photo.failed")];
}

- (void)imagePickerControllerDidCancel:(UIImagePickerController *)picker {
    [picker dismissViewControllerAnimated:YES completion:nil];
}

- (void)removePhoto:(UIButton *)b {
    if (b.tag >= (NSInteger)self.photos.count) return;
    NSDictionary *p = self.photos[b.tag];
    if (p[@"id"]) [self.removedPhotoIds addObject:p[@"id"]];
    [self.photos removeObjectAtIndex:b.tag];
    [self refreshPhotos];
}

#pragma mark - Save / cancel

/// Reads every control. Returns nil and sets error for the first invalid field.
- (NSDictionary *)collect:(NSArray **)tagsOut error:(NSString **)error {
    NSMutableDictionary *out = [NSMutableDictionary dictionary];
    NSArray *tags = @[];
    for (NSDictionary *sec in self.sections) for (HLFieldSpec *f in sec[@"fields"]) {
        id value = [NSNull null];
        switch (f.type) {
            case HLFieldText: {
                NSString *s = [HLKit trim:((UITextField *)self.controls[f.key]).text];
                if (s.length) value = s;
                break;
            }
            case HLFieldLongText: {
                NSString *s = [HLKit trim:((UITextView *)self.controls[f.key]).text];
                if (s.length) value = s;
                break;
            }
            case HLFieldTags: {
                NSMutableArray *a = [NSMutableArray array];
                for (NSString *t in [((UITextField *)self.controls[f.key]).text componentsSeparatedByCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@",，;"]]) {
                    NSString *x = [HLKit trim:t];
                    if (x.length && ![a containsObject:x]) [a addObject:x];
                }
                tags = a;
                continue;
            }
            case HLFieldDate:
                if (((UISwitch *)self.controls[[f.key stringByAppendingString:@"#on"]]).isOn) value = ((UIDatePicker *)self.controls[f.key]).date;
                break;
            case HLFieldMoney: {
                long long minor = 0;
                NSString *e = nil, *cur = self.currencies[f.key];
                if ([HLKit parseMoney:((UITextField *)self.controls[f.key]).text currency:cur minor:&minor error:&e]) {
                    value = @(minor);
                    out[f.curKey] = cur;
                } else if (e) {
                    if (error) *error = [NSString stringWithFormat:@"%@: %@", f.title, e];
                    return nil;
                } else {
                    out[f.curKey] = [NSNull null];   // not entered — never stored as zero
                }
                break;
            }
            case HLFieldPick:
                value = self.values[f.key] ?: [NSNull null];
                break;
            case HLFieldPhotos:
                continue;
        }
        if (f.required && value == [NSNull null]) {
            if (error) *error = [NSString stringWithFormat:HLT(@"err.required"), f.title];
            return nil;
        }
        out[f.key] = value;
    }
    if (tagsOut) *tagsOut = tags;
    return out;
}

- (void)save {
    [self.view endEditing:YES];
    NSString *err = nil;
    NSArray *tags = nil;
    NSDictionary *v = [self collect:&tags error:&err];
    if (!v) { [HLKit tell:self title:HLT(@"common.checkInput") message:err]; return; }
    NSMutableArray *newFiles = [NSMutableArray array];
    for (NSDictionary *p in self.photos) if (!p[@"id"]) [newFiles addObject:p[@"file"]];
    NSString *fail = self.onSave ? self.onSave(v, tags ?: @[], newFiles, self.removedPhotoIds) : nil;
    if (fail) { [HLKit tell:self title:HLT(@"common.error") message:fail]; return; }
    self.saved = YES;
    [self finish];
}

- (void)cancel {
    [self finish];
}

- (void)finish {
    void (^done)(BOOL) = self.onClose;
    BOOL saved = self.saved;
    [self.presentingViewController dismissViewControllerAnimated:YES completion:^{
        // Picked photos that were never attached (cancel, or removed before saving) are deleted.
        [[HLStore shared] sweepFiles];
        if (done) done(saved);
    }];
}

#pragma mark - Ready-made forms

+ (HLFieldSpec *)f:(NSString *)key title:(NSString *)titleKey type:(HLField)type {
    return [HLFieldSpec key:key title:HLT(titleKey) type:type];
}

/// Writes the photo changes collected by the form for one owner record.
+ (NSString *)applyPhotos:(NSArray<NSString *> *)files removed:(NSArray<NSString *> *)removed type:(NSString *)type owner:(NSString *)owner {
    NSString *err = nil;
    for (NSString *aid in removed) if (![[HLStore shared] deleteAttachment:aid error:&err]) return err;
    for (NSString *file in files) if (![[HLStore shared] addAttachment:file ownerType:type owner:owner error:&err]) return err;
    return nil;
}

+ (void)presentItemFormFor:(HLRow *)item from:(UIViewController *)host {
    [self presentItemFormFor:item from:host done:nil];
}

+ (void)presentItemFormFor:(HLRow *)item from:(UIViewController *)host done:(void (^)(NSString *))done {
    HLStore *store = [HLStore shared];
    NSMutableArray *roomTitles = [NSMutableArray arrayWithObject:HLT(@"common.unassigned")], *roomIds = [NSMutableArray arrayWithObject:[NSNull null]];
    for (HLRow *r in [store rooms]) { [roomTitles addObject:[store nameOf:r]]; [roomIds addObject:r[@"id"]]; }
    NSMutableArray *catTitles = [NSMutableArray arrayWithObject:HLT(@"common.unassigned")], *catIds = [NSMutableArray arrayWithObject:[NSNull null]];
    for (HLRow *c in [store categories]) { [catTitles addObject:[store nameOf:c]]; [catIds addObject:c[@"id"]]; }

    HLFieldSpec *name = [self f:@"name" title:@"field.name" type:HLFieldText]; name.required = YES; name.placeholder = HLT(@"field.namePh");
    HLFieldSpec *room = [self f:@"room_id" title:@"field.room" type:HLFieldPick]; room.optionTitles = roomTitles; room.optionValues = roomIds;
    HLFieldSpec *cat = [self f:@"category_id" title:@"field.category" type:HLFieldPick]; cat.optionTitles = catTitles; cat.optionValues = catIds;
    HLFieldSpec *spot = [self f:@"spot" title:@"field.spot" type:HLFieldText]; spot.placeholder = HLT(@"field.spotPh");
    HLFieldSpec *tags = [self f:@"tags" title:@"field.tags" type:HLFieldTags]; tags.placeholder = HLT(@"field.tagsPh"); tags.hint = HLT(@"field.tagsHint");
    HLFieldSpec *price = [self f:@"price" title:@"field.price" type:HLFieldMoney]; price.curKey = @"price_cur";
    HLFieldSpec *value = [self f:@"value" title:@"field.value" type:HLFieldMoney]; value.curKey = @"value_cur"; value.hint = HLT(@"field.valueHint");
    HLFieldSpec *status = [self f:@"status" title:@"field.status" type:HLFieldPick];
    status.optionTitles = @[[HLKit statusName:0], [HLKit statusName:1], [HLKit statusName:2], [HLKit statusName:3]];
    status.optionValues = @[@0, @1, @2, @3];
    HLFieldSpec *wEnd = [self f:@"warranty_end" title:@"field.warrantyEnd" type:HLFieldDate]; wEnd.hint = HLT(@"field.warrantyHint");

    NSArray *sections = @[
        @{@"title": HLT(@"form.secBasics"), @"fields": @[name, [self f:@"photos" title:@"field.photos" type:HLFieldPhotos], cat,
                                                         [self f:@"brand" title:@"field.brand" type:HLFieldText], [self f:@"model" title:@"field.model" type:HLFieldText]]},
        @{@"title": HLT(@"form.secWhere"), @"fields": @[room, spot, tags]},
        @{@"title": HLT(@"form.secPurchase"), @"fields": @[[self f:@"purchase_date" title:@"field.purchaseDate" type:HLFieldDate], price, value,
                                                           [self f:@"channel" title:@"field.channel" type:HLFieldText],
                                                           [self f:@"serial" title:@"field.serial" type:HLFieldText]]},
        @{@"title": HLT(@"form.secWarranty"), @"fields": @[[self f:@"warranty_start" title:@"field.warrantyStart" type:HLFieldDate], wEnd,
                                                           [self f:@"warranty_note" title:@"field.warrantyNote" type:HLFieldLongText]]},
        @{@"title": HLT(@"form.secStatus"), @"fields": @[status, [self f:@"notes" title:@"field.notes" type:HLFieldLongText]]},
    ];
    NSMutableDictionary *vals = [NSMutableDictionary dictionaryWithDictionary:item ?: @{}];
    if (item) vals[@"tags"] = [store tagsForItem:item[@"id"]];
    HLFormController *f = [[HLFormController alloc] initWithTitle:item ? HLT(@"item.edit") : HLT(@"item.new") sections:sections values:vals];
    f.existingPhotos = item ? [store attachmentsFor:@"item" owner:item[@"id"]] : nil;
    __block NSString *savedId = item[@"id"];
    f.onSave = ^NSString *(NSDictionary *v, NSArray *t, NSArray *newPhotos, NSArray *removed) {
        id ws = v[@"warranty_start"], we = v[@"warranty_end"];
        if ([ws isKindOfClass:[NSDate class]] && [we isKindOfClass:[NSDate class]] && [we compare:ws] == NSOrderedAscending) return HLT(@"err.warrantyOrder");
        NSString *err = nil;
        NSString *iid = [store saveItem:item[@"id"] values:v tags:t error:&err];
        if (!iid) return err;
        savedId = iid;
        return [self applyPhotos:newPhotos removed:removed type:@"item" owner:iid];
    };
    f.onClose = ^(BOOL saved) { if (done) done(saved ? savedId : nil); };
    [f presentFrom:host];
}

+ (void)presentMaintenanceFor:(HLRow *)record item:(HLRow *)item from:(UIViewController *)host done:(void (^)(void))done {
    HLStore *store = [HLStore shared];
    HLFieldSpec *date = [self f:@"date" title:@"field.date" type:HLFieldDate]; date.required = YES;
    HLFieldSpec *kind = [self f:@"kind" title:@"field.kind" type:HLFieldPick];
    kind.optionTitles = @[HLT(@"mkind.maintenance"), HLT(@"mkind.repair"), HLT(@"mkind.inspection"), HLT(@"mkind.other")];
    kind.optionValues = @[@0, @1, @2, @3];
    HLFieldSpec *cost = [self f:@"cost" title:@"field.cost" type:HLFieldMoney]; cost.curKey = @"cost_cur";
    HLFieldSpec *issue = [self f:@"issue" title:@"field.issue" type:HLFieldLongText];
    NSArray *sections = @[
        @{@"title": HLT(@"form.secRecord"), @"fields": @[date, kind, issue, [self f:@"action" title:@"field.actionTaken" type:HLFieldLongText]]},
        @{@"title": HLT(@"form.secCost"), @"fields": @[cost, [self f:@"provider" title:@"field.provider" type:HLFieldText]]},
        @{@"title": HLT(@"form.secExtra"), @"fields": @[[self f:@"photos" title:@"field.photos" type:HLFieldPhotos],
                                                        [self f:@"notes" title:@"field.notes" type:HLFieldLongText]]},
    ];
    NSMutableDictionary *vals = [NSMutableDictionary dictionaryWithDictionary:record ?: @{}];
    if (!record) vals[@"date"] = @([NSDate date].timeIntervalSince1970);
    HLFormController *f = [[HLFormController alloc] initWithTitle:record ? HLT(@"maint.edit") : HLT(@"maint.new") sections:sections values:vals];
    f.existingPhotos = record ? [store attachmentsFor:@"maintenance" owner:record[@"id"]] : nil;
    f.onSave = ^NSString *(NSDictionary *v, NSArray *t, NSArray *newPhotos, NSArray *removed) {
        if (v[@"issue"] == [NSNull null] && v[@"action"] == [NSNull null]) return HLT(@"err.maintEmpty");
        NSString *err = nil;
        NSString *mid = [store saveMaintenance:record[@"id"] item:item[@"id"] values:v error:&err];
        if (!mid) return err;
        return [self applyPhotos:newPhotos removed:removed type:@"maintenance" owner:mid];
    };
    f.onClose = ^(BOOL saved) { if (done) done(); };
    [f presentFrom:host];
}

@end
