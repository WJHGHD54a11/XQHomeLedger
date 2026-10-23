//
//  HLItemController.h
//  XQHomeLedger
//
//  Item detail: photos, full record, warranty state, maintenance history with totals, reminders,
//  stocktake state and actions (edit, duplicate, check, delete).
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface HLItemController : UIViewController

- (instancetype)initWithItemId:(NSString *)itemId;

@end

NS_ASSUME_NONNULL_END
