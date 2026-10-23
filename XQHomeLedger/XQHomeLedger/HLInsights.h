//
//  HLInsights.h
//  XQHomeLedger
//
//  Statistics computed from stored rows, plus local reminder scheduling.
//  Amounts are integer minor units and are only ever summed within one currency.
//

#import <Foundation/Foundation.h>
#import "HLStore.h"

NS_ASSUME_NONNULL_BEGIN

/// currency code -> NSNumber(long long minor units)
typedef NSDictionary<NSString *, NSNumber *> HLMoneyBag;

@interface HLInsights : NSObject

/// Snapshot over the given items (nil = all non-disposed items).
- (instancetype)initWithItems:(nullable NSArray<HLRow *> *)items;

@property (nonatomic, readonly) NSInteger itemCount;
@property (nonatomic, readonly) NSInteger pricedCount;       // items with a purchase price
@property (nonatomic, readonly) NSInteger valuedCount;       // items with a current value
@property (nonatomic, readonly) HLMoneyBag *purchaseTotals;
@property (nonatomic, readonly) HLMoneyBag *valueTotals;
@property (nonatomic, readonly) HLMoneyBag *repairTotals;
@property (nonatomic, readonly) NSInteger repairCount;
@property (nonatomic, readonly) NSInteger warrantyActive, warrantyExpiring, warrantyExpired, warrantyNone;
@property (nonatomic, readonly) NSInteger underRepair, notChecked, needsAttention;
/// @[@{@"key": id or @"", @"name", @"icon", @"count": NSNumber, @"value": HLMoneyBag}] sorted by count.
@property (nonatomic, readonly) NSArray<NSDictionary *> *byRoom;
@property (nonatomic, readonly) NSArray<NSDictionary *> *byCategory;
/// Repair cost per item category: @[@{@"name", @"cost": HLMoneyBag, @"count"}].
@property (nonatomic, readonly) NSArray<NSDictionary *> *repairByCategory;

/// One line per currency ("$1,200.00 · €80.00"); placeholder when empty.
+ (NSString *)describe:(HLMoneyBag *)bag;
/// Amount in the default currency only (for headline numbers), with a note when other currencies exist.
+ (long long)primary:(HLMoneyBag *)bag otherCurrencies:(BOOL *)others;

#pragma mark Reminders
/// Asks for notification permission (only when the user enables a reminder). Completion on main queue.
+ (void)requestPermission:(void (^)(BOOL granted))completion;
/// Re-schedules every stored reminder that is still in the future (call after edits / restore).
+ (void)rescheduleAll;

@end

NS_ASSUME_NONNULL_END
