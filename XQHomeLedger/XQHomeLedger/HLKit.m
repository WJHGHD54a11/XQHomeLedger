//
//  HLKit.m
//  XQHomeLedger
//

#import "HLKit.h"

NSNotificationName const HLLanguageChangedNotification = @"HLLanguageChangedNotification";
NSNotificationName const HLDataChangedNotification = @"HLDataChangedNotification";

static NSString * const kLangKey = @"hl.language";
static NSString * const kCurrencyKey = @"hl.currency";
static NSString * const kMiss = @"⁣hl";   // invisible separator; never a real translation

static UIColor *HLRGB(uint32_t v) {
    return [UIColor colorWithRed:((v >> 16) & 0xFF) / 255.0 green:((v >> 8) & 0xFF) / 255.0 blue:(v & 0xFF) / 255.0 alpha:1];
}

@implementation HLKit

#pragma mark - Palette

+ (UIColor *)paper    { return HLRGB(0xFFFFFF); }
+ (UIColor *)mist     { return HLRGB(0xF7F9F6); }
+ (UIColor *)mint     { return HLRGB(0xE3F8DF); }
+ (UIColor *)leaf     { return HLRGB(0x43B85A); }
+ (UIColor *)leafText { return HLRGB(0x2C8A41); }
+ (UIColor *)ink      { return HLRGB(0x171717); }
+ (UIColor *)ash      { return HLRGB(0x858585); }
+ (UIColor *)hair     { return HLRGB(0xEEEEEE); }
+ (UIColor *)amber    { return HLRGB(0xC98417); }
+ (UIColor *)coral    { return HLRGB(0xD9483F); }

+ (UIFont *)rounded:(CGFloat)size weight:(UIFontWeight)weight {
    UIFont *base = [UIFont systemFontOfSize:size weight:weight];
    UIFontDescriptor *d = [base.fontDescriptor fontDescriptorWithDesign:UIFontDescriptorSystemDesignRounded];
    return d ? [UIFont fontWithDescriptor:d size:size] : base;
}

#pragma mark - Language

static NSBundle *sLangBundle;

+ (NSString *)languageCode {
    NSString *c = [[NSUserDefaults standardUserDefaults] stringForKey:kLangKey];
    return [c isEqualToString:@"zh-Hans"] ? @"zh-Hans" : @"en";
}

+ (void)setLanguageCode:(NSString *)code {
    [[NSUserDefaults standardUserDefaults] setObject:([code isEqualToString:@"zh-Hans"] ? @"zh-Hans" : @"en") forKey:kLangKey];
    @synchronized (self) { sLangBundle = nil; }
    [[NSNotificationCenter defaultCenter] postNotificationName:HLLanguageChangedNotification object:nil];
}

+ (NSBundle *)langBundle {
    @synchronized (self) {
        if (!sLangBundle) {
            NSString *path = [[NSBundle mainBundle] pathForResource:[self languageCode] ofType:@"lproj"];
            sLangBundle = path ? [NSBundle bundleWithPath:path] : [NSBundle mainBundle];
        }
        return sLangBundle;
    }
}

+ (NSString *)text:(NSString *)key {
    NSString *s = [[self langBundle] localizedStringForKey:key value:kMiss table:nil];
    if (![s isEqualToString:kMiss]) return s;
    // Missing translation falls back to English rather than showing a raw key.
    NSString *en = [[NSBundle mainBundle] pathForResource:@"en" ofType:@"lproj"];
    return en ? [[NSBundle bundleWithPath:en] localizedStringForKey:key value:key table:nil] : key;
}

+ (NSLocale *)locale {
    return [NSLocale localeWithLocaleIdentifier:[[self languageCode] isEqualToString:@"zh-Hans"] ? @"zh_Hans_CN" : @"en_US"];
}

#pragma mark - Money

+ (NSArray<NSString *> *)currencyCodes {
    return @[@"USD", @"EUR", @"GBP", @"CNY", @"JPY", @"HKD", @"CAD", @"AUD", @"SGD", @"KRW"];
}

+ (NSString *)defaultCurrency {
    NSString *c = [[NSUserDefaults standardUserDefaults] stringForKey:kCurrencyKey];
    if ([[self currencyCodes] containsObject:c]) return c;
    // First run: the device region's currency when supported, otherwise USD. Shown and changeable in Settings.
    NSString *local = [NSLocale currentLocale].currencyCode;
    return [[self currencyCodes] containsObject:local] ? local : @"USD";
}

+ (void)setDefaultCurrency:(NSString *)code {
    if ([[self currencyCodes] containsObject:code]) [[NSUserDefaults standardUserDefaults] setObject:code forKey:kCurrencyKey];
}

+ (NSInteger)minorDigits:(NSString *)code {
    return ([code isEqualToString:@"JPY"] || [code isEqualToString:@"KRW"]) ? 0 : 2;
}

+ (NSString *)money:(long long)minor currency:(NSString *)code {
    NSInteger digits = [self minorDigits:code];
    // NSDecimalNumber keeps the exact value; doubles are never used for amounts.
    NSDecimalNumber *n = [NSDecimalNumber decimalNumberWithMantissa:(unsigned long long)llabs(minor) exponent:(short)-digits isNegative:minor < 0];
    NSNumberFormatter *f = [[NSNumberFormatter alloc] init];
    f.numberStyle = NSNumberFormatterCurrencyStyle;
    f.locale = [self locale];
    f.currencyCode = code;
    f.minimumFractionDigits = digits;
    f.maximumFractionDigits = digits;
    return [f stringFromNumber:n] ?: [NSString stringWithFormat:@"%@ %@", code, n];
}

+ (BOOL)parseMoney:(NSString *)text currency:(NSString *)code minor:(long long *)minor error:(NSString **)error {
    NSString *s = [[self trim:text] stringByReplacingOccurrencesOfString:@"," withString:@""];
    s = [s stringByReplacingOccurrencesOfString:@" " withString:@""];
    if (s.length == 0) { if (error) *error = nil; return NO; }
    NSCharacterSet *bad = [[NSCharacterSet characterSetWithCharactersInString:@"0123456789."] invertedSet];
    if ([s rangeOfCharacterFromSet:bad].location != NSNotFound || [s componentsSeparatedByString:@"."].count > 2) {
        if (error) *error = HLT(@"err.amount"); return NO;
    }
    NSDecimalNumber *n = [NSDecimalNumber decimalNumberWithString:s locale:@{NSLocaleDecimalSeparator: @"."}];
    if ([n isEqualToNumber:[NSDecimalNumber notANumber]]) { if (error) *error = HLT(@"err.amount"); return NO; }
    NSInteger digits = [self minorDigits:code];
    NSArray *parts = [s componentsSeparatedByString:@"."];
    if (parts.count == 2 && [parts[1] length] > (NSUInteger)digits) { if (error) *error = HLT(@"err.amountDigits"); return NO; }
    NSDecimalNumber *scaled = [n decimalNumberByMultiplyingByPowerOf10:(short)digits];
    if ([scaled compare:[NSDecimalNumber decimalNumberWithString:@"100000000000000"]] == NSOrderedDescending) {
        if (error) *error = HLT(@"err.amountLarge"); return NO;
    }
    *minor = scaled.longLongValue;
    return YES;
}

+ (NSString *)moneyInput:(long long)minor currency:(NSString *)code {
    NSInteger digits = [self minorDigits:code];
    NSDecimalNumber *n = [NSDecimalNumber decimalNumberWithMantissa:(unsigned long long)llabs(minor) exponent:(short)-digits isNegative:minor < 0];
    return [n descriptionWithLocale:@{NSLocaleDecimalSeparator: @"."}];
}

#pragma mark - Dates

+ (NSString *)format:(NSDate *)date time:(BOOL)time {
    if (!date) return HLT(@"common.notSet");
    NSDateFormatter *f = [[NSDateFormatter alloc] init];
    f.locale = [self locale];
    f.dateStyle = NSDateFormatterMediumStyle;
    f.timeStyle = time ? NSDateFormatterShortStyle : NSDateFormatterNoStyle;
    return [f stringFromDate:date];
}

+ (NSString *)day:(NSDate *)date { return [self format:date time:NO]; }
+ (NSString *)dayTime:(NSDate *)date { return [self format:date time:YES]; }
+ (NSDate *)dateFromStamp:(double)stamp { return [NSDate dateWithTimeIntervalSince1970:stamp]; }

#pragma mark - Vocabulary

+ (NSString *)statusName:(NSInteger)status {
    switch (status) {
        case HLItemStatusStored: return HLT(@"status.stored");
        case HLItemStatusRepair: return HLT(@"status.repair");
        case HLItemStatusDisposed: return HLT(@"status.disposed");
        default: return HLT(@"status.inUse");
    }
}

+ (UIColor *)statusColor:(NSInteger)status {
    switch (status) {
        case HLItemStatusStored: return [UIColor colorWithRed:0.29 green:0.47 blue:0.78 alpha:1];
        case HLItemStatusRepair: return [self amber];
        case HLItemStatusDisposed: return [self ash];
        default: return [self leafText];
    }
}

+ (NSString *)statusIcon:(NSInteger)status {
    switch (status) {
        case HLItemStatusStored: return @"archivebox";
        case HLItemStatusRepair: return @"wrench";
        case HLItemStatusDisposed: return @"xmark.bin";
        default: return @"checkmark.circle";
    }
}

+ (HLWarranty)warrantyForEnd:(NSDate *)end {
    if (!end) return HLWarrantyNone;
    // Compare calendar days in the current time zone so "ends today" still counts as active.
    NSCalendar *cal = [NSCalendar currentCalendar];
    NSDate *today = [cal startOfDayForDate:[NSDate date]];
    NSDate *endDay = [cal startOfDayForDate:end];
    if ([endDay compare:today] == NSOrderedAscending) return HLWarrantyExpired;
    NSDate *soon = [cal dateByAddingUnit:NSCalendarUnitDay value:30 toDate:today options:0];
    return [endDay compare:soon] != NSOrderedDescending ? HLWarrantyExpiring : HLWarrantyActive;
}

+ (NSString *)warrantyName:(HLWarranty)w {
    switch (w) {
        case HLWarrantyActive: return HLT(@"warranty.active");
        case HLWarrantyExpiring: return HLT(@"warranty.expiring");
        case HLWarrantyExpired: return HLT(@"warranty.expired");
        default: return HLT(@"warranty.none");
    }
}

+ (UIColor *)warrantyColor:(HLWarranty)w {
    switch (w) {
        case HLWarrantyActive: return [self leafText];
        case HLWarrantyExpiring: return [self amber];
        case HLWarrantyExpired: return [self coral];
        default: return [self ash];
    }
}

#pragma mark - Builders

+ (UILabel *)label:(CGFloat)size weight:(UIFontWeight)weight color:(UIColor *)color {
    UILabel *l = [[UILabel alloc] init];
    l.font = [UIFont systemFontOfSize:size weight:weight];
    l.textColor = color;
    l.numberOfLines = 0;
    l.adjustsFontForContentSizeCategory = YES;
    return l;
}

+ (UIView *)card {
    UIView *v = [[UIView alloc] init];
    v.backgroundColor = [self paper];
    v.layer.cornerRadius = 22;
    v.layer.cornerCurve = kCACornerCurveContinuous;
    v.layer.shadowColor = [UIColor colorWithRed:0.10 green:0.30 blue:0.15 alpha:1].CGColor;
    v.layer.shadowOpacity = 0.07;
    v.layer.shadowRadius = 16;
    v.layer.shadowOffset = CGSizeMake(0, 6);
    return v;
}

+ (UIButton *)pill:(NSString *)title icon:(NSString *)symbol filled:(BOOL)filled {
    UIButtonConfiguration *c = filled ? [UIButtonConfiguration filledButtonConfiguration] : [UIButtonConfiguration tintedButtonConfiguration];
    c.title = title;
    c.image = symbol ? [self symbol:symbol size:15] : nil;
    c.imagePadding = 6;
    c.cornerStyle = UIButtonConfigurationCornerStyleCapsule;
    c.baseBackgroundColor = filled ? [self leaf] : [self mint];
    c.baseForegroundColor = filled ? [UIColor whiteColor] : [self leafText];
    c.contentInsets = NSDirectionalEdgeInsetsMake(12, 18, 12, 18);
    c.titleTextAttributesTransformer = ^NSDictionary<NSAttributedStringKey, id> *(NSDictionary<NSAttributedStringKey, id> *a) {
        NSMutableDictionary *m = [a mutableCopy];
        m[NSFontAttributeName] = [HLKit rounded:16 weight:UIFontWeightSemibold];
        return m;
    };
    UIButton *b = [UIButton buttonWithConfiguration:c primaryAction:nil];
    [b.heightAnchor constraintGreaterThanOrEqualToConstant:46].active = YES;
    return b;
}

+ (UILabel *)chip:(NSString *)text color:(UIColor *)color {
    UILabel *l = [[UILabel alloc] init];
    l.text = [NSString stringWithFormat:@"  %@  ", text];
    l.font = [UIFont systemFontOfSize:12 weight:UIFontWeightSemibold];
    l.textColor = color;
    l.backgroundColor = [color colorWithAlphaComponent:0.12];
    l.layer.cornerRadius = 9;
    l.clipsToBounds = YES;
    l.textAlignment = NSTextAlignmentCenter;
    [l.heightAnchor constraintEqualToConstant:22].active = YES;
    [l setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    [l setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    return l;
}

+ (UIView *)ring:(CGFloat)progress color:(UIColor *)color diameter:(CGFloat)diameter line:(CGFloat)line {
    UIView *v = [[UIView alloc] init];
    v.translatesAutoresizingMaskIntoConstraints = NO;
    [v.widthAnchor constraintEqualToConstant:diameter].active = YES;
    [v.heightAnchor constraintEqualToConstant:diameter].active = YES;
    CGFloat r = (diameter - line) / 2;
    UIBezierPath *path = [UIBezierPath bezierPathWithArcCenter:CGPointMake(diameter / 2, diameter / 2) radius:r
                                                    startAngle:-M_PI_2 endAngle:M_PI * 1.5 clockwise:YES];
    CAShapeLayer *track = [CAShapeLayer layer];
    track.path = path.CGPath;
    track.fillColor = UIColor.clearColor.CGColor;
    track.strokeColor = [color colorWithAlphaComponent:0.14].CGColor;
    track.lineWidth = line;
    [v.layer addSublayer:track];
    CAShapeLayer *bar = [CAShapeLayer layer];
    bar.path = path.CGPath;
    bar.fillColor = UIColor.clearColor.CGColor;
    bar.strokeColor = color.CGColor;
    bar.lineWidth = line;
    bar.lineCap = kCALineCapRound;
    bar.strokeEnd = MAX(0, MIN(1, progress));
    [v.layer addSublayer:bar];
    return v;
}

+ (UIView *)emptyWithIcon:(NSString *)symbol title:(NSString *)title message:(NSString *)message
                   action:(NSString *)action handler:(void (^)(void))handler {
    UIView *wrap = [[UIView alloc] init];
    UIView *badge = [[UIView alloc] init];
    badge.backgroundColor = [self mint];
    badge.layer.cornerRadius = 36;
    badge.translatesAutoresizingMaskIntoConstraints = NO;
    UIImageView *iv = [[UIImageView alloc] initWithImage:[self symbol:symbol size:30]];
    iv.tintColor = [self leafText];
    iv.translatesAutoresizingMaskIntoConstraints = NO;
    [badge addSubview:iv];
    UILabel *t = [self label:19 weight:UIFontWeightBold color:[self ink]];
    t.font = [self rounded:19 weight:UIFontWeightBold];
    t.text = title;
    t.textAlignment = NSTextAlignmentCenter;
    UILabel *m = [self label:14 weight:UIFontWeightRegular color:[self ash]];
    m.text = message;
    m.textAlignment = NSTextAlignmentCenter;
    UIStackView *s = [[UIStackView alloc] initWithArrangedSubviews:@[badge, t, m]];
    s.axis = UILayoutConstraintAxisVertical;
    s.alignment = UIStackViewAlignmentCenter;
    s.spacing = 10;
    [s setCustomSpacing:16 afterView:badge];
    if (action && handler) {
        UIButton *b = [self pill:action icon:@"plus" filled:YES];
        [b addAction:[UIAction actionWithHandler:^(UIAction *a) { handler(); }] forControlEvents:UIControlEventTouchUpInside];
        [s setCustomSpacing:20 afterView:m];
        [s addArrangedSubview:b];
    }
    s.translatesAutoresizingMaskIntoConstraints = NO;
    [wrap addSubview:s];
    [NSLayoutConstraint activateConstraints:@[
        [badge.widthAnchor constraintEqualToConstant:72], [badge.heightAnchor constraintEqualToConstant:72],
        [iv.centerXAnchor constraintEqualToAnchor:badge.centerXAnchor], [iv.centerYAnchor constraintEqualToAnchor:badge.centerYAnchor],
        [s.centerYAnchor constraintEqualToAnchor:wrap.centerYAnchor constant:-30],
        [s.leadingAnchor constraintEqualToAnchor:wrap.leadingAnchor constant:36],
        [s.trailingAnchor constraintEqualToAnchor:wrap.trailingAnchor constant:-36],
    ]];
    return wrap;
}

+ (UIImage *)symbol:(NSString *)name size:(CGFloat)size {
    UIImageSymbolConfiguration *c = [UIImageSymbolConfiguration configurationWithPointSize:size weight:UIImageSymbolWeightMedium];
    return [UIImage systemImageNamed:name withConfiguration:c] ?: [UIImage systemImageNamed:@"square" withConfiguration:c];
}

#pragma mark - Alerts

+ (void)tell:(UIViewController *)vc title:(NSString *)title message:(NSString *)message {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:HLT(@"common.ok") style:UIAlertActionStyleCancel handler:nil]];
    [vc presentViewController:a animated:YES completion:nil];
}

+ (void)ask:(UIViewController *)vc title:(NSString *)title message:(NSString *)message
     action:(NSString *)action destructive:(BOOL)destructive then:(void (^)(void))then {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:HLT(@"common.cancel") style:UIAlertActionStyleCancel handler:nil]];
    [a addAction:[UIAlertAction actionWithTitle:action style:destructive ? UIAlertActionStyleDestructive : UIAlertActionStyleDefault
                                        handler:^(UIAlertAction *x) { then(); }]];
    [vc presentViewController:a animated:YES completion:nil];
}

+ (NSString *)trim:(NSString *)s {
    return [s ?: @"" stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

@end
