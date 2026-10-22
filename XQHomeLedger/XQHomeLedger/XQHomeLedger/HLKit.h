//
//  HLKit.h
//  XQHomeLedger
//
//  Design tokens, in-app language, money/date formatting and small UI builders shared by every screen.
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// Localized text in the language chosen inside the app (English by default).
#define HLT(key) [HLKit text:(key)]

extern NSNotificationName const HLLanguageChangedNotification;
/// Posted by HLStore after any committed change, so visible screens can refresh.
extern NSNotificationName const HLDataChangedNotification;

typedef NS_ENUM(NSInteger, HLItemStatus) {
    HLItemStatusInUse = 0,
    HLItemStatusStored,
    HLItemStatusRepair,
    HLItemStatusDisposed,
};

typedef NS_ENUM(NSInteger, HLWarranty) {
    HLWarrantyNone = 0,      // no end date entered — never treated as expired
    HLWarrantyActive,
    HLWarrantyExpiring,      // ends within the next 30 days
    HLWarrantyExpired,
};

@interface HLKit : NSObject

#pragma mark Palette
+ (UIColor *)paper;      // #FFFFFF page
+ (UIColor *)mist;       // #F7F9F6 secondary background
+ (UIColor *)mint;       // #E3F8DF soft green areas
+ (UIColor *)leaf;       // #43B85A primary action fill
+ (UIColor *)leafText;   // deeper green for text and icons on white
+ (UIColor *)ink;        // #171717
+ (UIColor *)ash;        // #858585
+ (UIColor *)hair;       // #EEEEEE
+ (UIColor *)amber;      // warning
+ (UIColor *)coral;      // error / destructive

#pragma mark Type
/// SF Pro Rounded — used for numbers and headlines.
+ (UIFont *)rounded:(CGFloat)size weight:(UIFontWeight)weight;

#pragma mark Language
+ (NSString *)languageCode;              // "en" or "zh-Hans"
+ (void)setLanguageCode:(NSString *)code;
+ (NSString *)text:(NSString *)key;
+ (NSLocale *)locale;

#pragma mark Money (integer minor units, one currency per amount)
+ (NSString *)defaultCurrency;
+ (void)setDefaultCurrency:(NSString *)code;
+ (NSArray<NSString *> *)currencyCodes;
+ (NSInteger)minorDigits:(NSString *)code;
+ (NSString *)money:(long long)minor currency:(NSString *)code;
/// Parses user text into minor units. Empty text returns NO with error nil (meaning "not entered").
+ (BOOL)parseMoney:(nullable NSString *)text currency:(NSString *)code minor:(long long *)minor error:(NSString * _Nullable * _Nullable)error;
/// Minor units back to an editable decimal string ("1234.50").
+ (NSString *)moneyInput:(long long)minor currency:(NSString *)code;

#pragma mark Dates
+ (NSString *)day:(nullable NSDate *)date;
+ (NSString *)dayTime:(nullable NSDate *)date;
+ (NSDate *)dateFromStamp:(double)stamp;   // stored as seconds since 1970

#pragma mark Vocabulary
+ (NSString *)statusName:(NSInteger)status;
+ (UIColor *)statusColor:(NSInteger)status;
+ (NSString *)statusIcon:(NSInteger)status;
+ (HLWarranty)warrantyForEnd:(nullable NSDate *)end;
+ (NSString *)warrantyName:(HLWarranty)w;
+ (UIColor *)warrantyColor:(HLWarranty)w;

#pragma mark Builders
+ (UILabel *)label:(CGFloat)size weight:(UIFontWeight)weight color:(UIColor *)color;
/// White rounded card with a soft shadow.
+ (UIView *)card;
/// Capsule button. filled = green background with white title.
+ (UIButton *)pill:(NSString *)title icon:(nullable NSString *)symbol filled:(BOOL)filled;
/// Small rounded tag: tinted background, coloured text (meaning never depends on colour alone).
+ (UILabel *)chip:(NSString *)text color:(UIColor *)color;
/// Circular progress ring 0...1.
+ (UIView *)ring:(CGFloat)progress color:(UIColor *)color diameter:(CGFloat)diameter line:(CGFloat)line;
+ (UIView *)emptyWithIcon:(NSString *)symbol title:(NSString *)title message:(NSString *)message
                   action:(nullable NSString *)action handler:(nullable void (^)(void))handler;
+ (UIImage *)symbol:(NSString *)name size:(CGFloat)size;

#pragma mark Alerts
+ (void)tell:(UIViewController *)vc title:(NSString *)title message:(nullable NSString *)message;
+ (void)ask:(UIViewController *)vc title:(NSString *)title message:(nullable NSString *)message
     action:(NSString *)action destructive:(BOOL)destructive then:(void (^)(void))then;

+ (NSString *)trim:(nullable NSString *)s;

@end

NS_ASSUME_NONNULL_END
