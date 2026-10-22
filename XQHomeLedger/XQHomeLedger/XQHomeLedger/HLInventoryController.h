//
//  HLInventoryController.h
//  XQHomeLedger
//
//  Inventory list: search, filters (room, category, status, warranty, check state), sorting, batch actions.
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// Filter keys for initWithFilter:. Values are ids / NSNumber.
extern NSString * const HLFilterRoom;        // room id, or @"" for unassigned
extern NSString * const HLFilterCategory;    // category id, or @"" for unassigned
extern NSString * const HLFilterStatus;      // NSNumber HLItemStatus
extern NSString * const HLFilterWarranty;    // NSNumber HLWarranty
extern NSString * const HLFilterUnchecked;   // @YES

@interface HLInventoryController : UIViewController

/// filter nil + title nil = the Inventory tab root.
- (instancetype)initWithFilter:(nullable NSDictionary *)filter title:(nullable NSString *)title;

@end

NS_ASSUME_NONNULL_END
