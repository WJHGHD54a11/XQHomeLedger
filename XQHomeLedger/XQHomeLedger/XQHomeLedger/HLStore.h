//
//  HLStore.h
//  XQHomeLedger
//
//  SQLite persistence (system libsqlite3, no third-party wrapper) + attachment files on disk.
//  Rows are NSDictionary keyed by column name; NULL columns are absent from the dictionary.
//
//  Tables: household, room, category, item, tag, item_tag, maintenance, attachment,
//          stocktake, stocktake_entry, reminder.
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

typedef NSDictionary<NSString *, id> HLRow;

@interface HLStore : NSObject

+ (instancetype)shared;
/// Non-nil when the database could not be opened; the app shows it instead of silently losing data.
@property (nonatomic, readonly, nullable) NSString *openError;

#pragma mark Generic
- (NSArray<HLRow *> *)query:(NSString *)sql args:(nullable NSArray *)args;
- (nullable HLRow *)row:(NSString *)sql args:(nullable NSArray *)args;
- (long long)scalar:(NSString *)sql args:(nullable NSArray *)args;
/// Executes one statement. Pass [NSNull null] for SQL NULL.
- (BOOL)run:(NSString *)sql args:(nullable NSArray *)args error:(NSString * _Nullable * _Nullable)error;
/// Runs block inside BEGIN/COMMIT; any NO return or failed statement rolls everything back.
- (BOOL)transaction:(BOOL (^)(NSString * _Nullable * _Nullable error))block error:(NSString * _Nullable * _Nullable)error;
- (NSString *)makeId;
- (double)now;
/// Posts HLDataChangedNotification on the main queue.
- (void)notifyChanged;

#pragma mark Household & structure
- (HLRow *)household;
- (BOOL)renameHousehold:(NSString *)name error:(NSString * _Nullable * _Nullable)error;
- (NSArray<HLRow *> *)rooms;
- (NSArray<HLRow *> *)categories;
- (nullable HLRow *)roomWithId:(nullable NSString *)rid;
- (nullable HLRow *)categoryWithId:(nullable NSString *)cid;
/// Display name: user text, or the localized built-in name.
- (NSString *)nameOf:(nullable HLRow *)roomOrCategory;
- (nullable NSString *)saveRoom:(nullable NSString *)rid name:(NSString *)name icon:(NSString *)icon error:(NSString * _Nullable * _Nullable)error;
- (nullable NSString *)saveCategory:(nullable NSString *)cid name:(NSString *)name icon:(NSString *)icon error:(NSString * _Nullable * _Nullable)error;
/// Items in the room / category are kept and become "Unassigned".
- (BOOL)deleteRoom:(NSString *)rid error:(NSString * _Nullable * _Nullable)error;
- (BOOL)deleteCategory:(NSString *)cid error:(NSString * _Nullable * _Nullable)error;

#pragma mark Items
- (nullable HLRow *)itemWithId:(NSString *)iid;
/// Every item with room_name / category_name / tags joined in. Disposed items included.
- (NSArray<HLRow *> *)allItems;
/// Insert (iid nil) or update. values uses column names; tags is an array of strings.
- (nullable NSString *)saveItem:(nullable NSString *)iid values:(NSDictionary *)values tags:(NSArray<NSString *> *)tags
                          error:(NSString * _Nullable * _Nullable)error;
- (nullable NSString *)duplicateItem:(NSString *)iid error:(NSString * _Nullable * _Nullable)error;
/// Deletes items with their maintenance records, stocktake entries, reminders and attachment files.
- (BOOL)deleteItems:(NSArray<NSString *> *)ids error:(NSString * _Nullable * _Nullable)error;
- (BOOL)setStatus:(NSInteger)status forItems:(NSArray<NSString *> *)ids error:(NSString * _Nullable * _Nullable)error;
- (BOOL)moveItems:(NSArray<NSString *> *)ids toRoom:(nullable NSString *)rid error:(NSString * _Nullable * _Nullable)error;
- (NSArray<NSString *> *)tagsForItem:(NSString *)iid;
- (NSArray<NSString *> *)allTags;

#pragma mark Maintenance
- (NSArray<HLRow *> *)maintenanceForItem:(NSString *)iid;
- (nullable NSString *)saveMaintenance:(nullable NSString *)mid item:(NSString *)iid values:(NSDictionary *)values
                                 error:(NSString * _Nullable * _Nullable)error;
- (BOOL)deleteMaintenance:(NSString *)mid error:(NSString * _Nullable * _Nullable)error;

#pragma mark Attachments (photos)
/// Downscales, writes JPEG to Application Support/Attachments and returns the stored file name.
- (nullable NSString *)storeImage:(UIImage *)image error:(NSString * _Nullable * _Nullable)error;
- (nullable UIImage *)imageNamed:(nullable NSString *)file;
- (NSURL *)attachmentURL:(NSString *)file;
- (NSArray<HLRow *> *)attachmentsFor:(NSString *)ownerType owner:(NSString *)ownerId;
- (BOOL)addAttachment:(NSString *)file ownerType:(NSString *)type owner:(NSString *)ownerId error:(NSString * _Nullable * _Nullable)error;
- (BOOL)deleteAttachment:(NSString *)aid error:(NSString * _Nullable * _Nullable)error;
/// Removes files that no row references (edits that were cancelled, interrupted imports).
- (void)sweepFiles;

#pragma mark Stocktake
- (nullable HLRow *)openStocktake;
- (NSArray<HLRow *> *)stocktakes;
/// Snapshots the matching items (scope "all" / "room" / "category") as Not Checked entries.
- (nullable NSString *)startStocktakeScope:(NSString *)scope value:(nullable NSString *)value
                                     error:(NSString * _Nullable * _Nullable)error;
- (NSArray<HLRow *> *)entriesFor:(NSString *)sid;
/// result: 1 checked, 2 missing, 3 needs action. moveTo non-nil also moves the item to that room.
- (BOOL)markEntry:(NSString *)eid result:(NSInteger)result note:(nullable NSString *)note moveTo:(nullable NSString *)rid
            error:(NSString * _Nullable * _Nullable)error;
- (BOOL)finishStocktake:(NSString *)sid error:(NSString * _Nullable * _Nullable)error;
- (BOOL)deleteStocktake:(NSString *)sid error:(NSString * _Nullable * _Nullable)error;

#pragma mark Reminders
- (NSArray<HLRow *> *)remindersForItem:(NSString *)iid;
- (NSArray<HLRow *> *)allReminders;
- (nullable NSString *)saveReminder:(nullable NSString *)rid item:(NSString *)iid kind:(NSString *)kind fireAt:(double)fireAt
                              title:(NSString *)title error:(NSString * _Nullable * _Nullable)error;
- (BOOL)deleteReminder:(NSString *)rid error:(NSString * _Nullable * _Nullable)error;

#pragma mark Sample data
- (BOOL)hasSampleData;
- (BOOL)loadSampleData:(NSString * _Nullable * _Nullable)error;
- (BOOL)removeSampleData:(NSString * _Nullable * _Nullable)error;
/// Deletes every record and file (Settings → Erase All Data).
- (BOOL)eraseAll:(NSString * _Nullable * _Nullable)error;

@end

NS_ASSUME_NONNULL_END
