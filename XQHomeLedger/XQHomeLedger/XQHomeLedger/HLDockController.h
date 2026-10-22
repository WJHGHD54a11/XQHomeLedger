//
//  HLDockController.h
//  XQHomeLedger
//
//  Root container: a floating capsule "dock" with four destinations and a raised center Add button,
//  replacing the system tab bar. Each destination is a navigation stack.
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface HLDockController : UITabBarController

/// Shows or hides the dock (pushed detail screens hide it, like hidesBottomBarWhenPushed).
- (void)setDockHidden:(BOOL)hidden animated:(BOOL)animated;
/// Switches to a destination (0 Home, 1 Inventory, 2 Locations, 3 Insights) and updates the dock.
- (void)showTab:(NSInteger)index;
/// Opens the new-item form over the current tab (also used by Home's quick add).
- (void)presentQuickAdd;

@end

NS_ASSUME_NONNULL_END
