//
//  HLSettingsController.h
//  XQHomeLedger
//
//  Settings: household, language, currency, reminders, reports (PDF / CSV), backup & restore,
//  sample data, privacy and data erase.
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface HLSettingsController : UITableViewController

- (instancetype)init;
/// Opens scrolled to the Reports & Backup section (Home → Reports).
- (instancetype)initWithReportsFocus;

@end

NS_ASSUME_NONNULL_END
