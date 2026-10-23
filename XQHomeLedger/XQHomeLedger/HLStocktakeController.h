//
//  HLStocktakeController.h
//  XQHomeLedger
//
//  Stocktake: start a session (all / room / category), confirm each item, record moves and problems,
//  finish and review results. Past sessions are kept.
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface HLStocktakeController : UITableViewController

/// sessionId nil = overview (open session, start new, history).
- (instancetype)initWithSession:(nullable NSString *)sessionId;

@end

NS_ASSUME_NONNULL_END
