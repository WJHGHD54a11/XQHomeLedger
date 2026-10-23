//
//  HLFormController.h
//  XQHomeLedger
//
//  Grouped card form used for items, maintenance records, rooms and reminders.
//  Required fields are marked; the keyboard never hides the Save bar.
//

#import <UIKit/UIKit.h>
#import "HLStore.h"

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, HLField) {
    HLFieldText = 0,
    HLFieldLongText,
    HLFieldDate,          // optional: on/off switch + date
    HLFieldMoney,         // amount + currency picker; stored as minor units + code
    HLFieldPick,          // one of options (values array)
    HLFieldTags,          // comma separated
    HLFieldPhotos,        // multiple photos (attachment rows on Save)
};

/// One field. key is the column name; for money, key is the amount column and curKey the currency column.
@interface HLFieldSpec : NSObject
@property (nonatomic, copy) NSString *key;
@property (nonatomic, copy, nullable) NSString *curKey;
@property (nonatomic, copy) NSString *title;
@property (nonatomic) HLField type;
@property (nonatomic) BOOL required;
@property (nonatomic, copy, nullable) NSString *placeholder;
@property (nonatomic, copy, nullable) NSString *hint;
@property (nonatomic, copy, nullable) NSArray<NSString *> *optionTitles;
@property (nonatomic, copy, nullable) NSArray *optionValues;   // NSNull = none
+ (instancetype)key:(NSString *)key title:(NSString *)title type:(HLField)type;
@end

@interface HLFormController : UIViewController

/// sections: @[@{@"title": NSString, @"fields": @[HLFieldSpec]}]. values: initial column values.
- (instancetype)initWithTitle:(NSString *)title sections:(NSArray<NSDictionary *> *)sections values:(nullable NSDictionary *)values;

/// Photos already stored for the record (attachment rows). New picks are added on Save.
@property (nonatomic, copy, nullable) NSArray<HLRow *> *existingPhotos;
@property (nonatomic, copy, nullable) NSString *saveTitle;
/// Return nil on success, or a localized error to keep the form open.
/// newPhotos are stored file names the caller must attach; removed are attachment ids to delete.
@property (nonatomic, copy, nullable) NSString * _Nullable (^onSave)(NSDictionary *values, NSArray<NSString *> *tags,
                                                                     NSArray<NSString *> *newPhotos, NSArray<NSString *> *removedPhotoIds);
@property (nonatomic, copy, nullable) void (^onClose)(BOOL saved);

- (void)presentFrom:(UIViewController *)host;

#pragma mark Ready-made forms
/// Item add / edit (item nil = new). Saves through HLStore and opens nothing afterwards.
+ (void)presentItemFormFor:(nullable HLRow *)item from:(UIViewController *)host;
+ (void)presentItemFormFor:(nullable HLRow *)item from:(UIViewController *)host done:(nullable void (^)(NSString * _Nullable itemId))done;
+ (void)presentMaintenanceFor:(nullable HLRow *)record item:(HLRow *)item from:(UIViewController *)host done:(nullable void (^)(void))done;

@end

NS_ASSUME_NONNULL_END
