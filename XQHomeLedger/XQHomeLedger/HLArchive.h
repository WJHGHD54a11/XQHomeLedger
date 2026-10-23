//
//  HLArchive.h
//  XQHomeLedger
//
//  PDF asset report, CSV inventory and restorable backups (.homeledger JSON, photos embedded).
//

#import <Foundation/Foundation.h>
#import "HLStore.h"

NS_ASSUME_NONNULL_BEGIN

/// Backup format identifier and version written into every file.
extern NSString * const HLBackupFormat;
extern NSInteger const HLBackupVersion;

@interface HLArchive : NSObject

/// scope: @"all" | @"room" | @"category"; value = room / category id. Files land in tmp/Exports.
+ (nullable NSURL *)pdfForScope:(NSString *)scope value:(nullable NSString *)value error:(NSString * _Nullable * _Nullable)error;
+ (nullable NSURL *)csvForScope:(NSString *)scope value:(nullable NSString *)value error:(NSString * _Nullable * _Nullable)error;
+ (nullable NSURL *)backup:(NSString * _Nullable * _Nullable)error;

/// Reads and validates a backup. Returns a summary (counts, date, version) or nil with an error.
+ (nullable NSDictionary *)inspectBackup:(NSURL *)url error:(NSString * _Nullable * _Nullable)error;
/// Merges a validated backup: records with an id that already exists are skipped (never overwritten),
/// photos are written as new files, relations are kept. Returns counts of added / skipped records.
+ (nullable NSDictionary *)restoreBackup:(NSURL *)url error:(NSString * _Nullable * _Nullable)error;

@end

NS_ASSUME_NONNULL_END
