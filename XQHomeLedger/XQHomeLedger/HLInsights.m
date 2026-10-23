//
//  HLInsights.m
//  XQHomeLedger
//

#import "HLInsights.h"
#import <UserNotifications/UserNotifications.h>
#import "HLKit.h"

@interface HLInsights ()
@property (nonatomic, readwrite) NSInteger itemCount, pricedCount, valuedCount, repairCount;
@property (nonatomic, readwrite) HLMoneyBag *purchaseTotals, *valueTotals, *repairTotals;
@property (nonatomic, readwrite) NSInteger warrantyActive, warrantyExpiring, warrantyExpired, warrantyNone;
@property (nonatomic, readwrite) NSInteger underRepair, notChecked, needsAttention;
@property (nonatomic, readwrite) NSArray<NSDictionary *> *byRoom, *byCategory, *repairByCategory;
@end

static void HLAdd(NSMutableDictionary *bag, NSString *cur, NSNumber *minor) {
    if (!minor || !cur.length) return;
    bag[cur] = @([bag[cur] longLongValue] + minor.longLongValue);
}

@implementation HLInsights

- (instancetype)initWithItems:(NSArray<HLRow *> *)items {
    if ((self = [super init])) {
        HLStore *store = [HLStore shared];
        NSArray *rows = items;
        if (!rows) {
            rows = [[store allItems] filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(HLRow *r, NSDictionary *b) {
                return [r[@"status"] integerValue] != HLItemStatusDisposed;
            }]];
        }
        NSMutableDictionary *buy = [NSMutableDictionary dictionary], *val = [NSMutableDictionary dictionary], *rep = [NSMutableDictionary dictionary];
        NSMutableDictionary *rooms = [NSMutableDictionary dictionary], *cats = [NSMutableDictionary dictionary], *repCat = [NSMutableDictionary dictionary];
        NSMutableSet *ids = [NSMutableSet set];
        for (HLRow *r in rows) {
            [ids addObject:r[@"id"]];
            if (r[@"price"]) { _pricedCount++; HLAdd(buy, r[@"price_cur"], r[@"price"]); }
            if (r[@"value"]) { _valuedCount++; HLAdd(val, r[@"value_cur"], r[@"value"]); }
            HLWarranty w = [HLKit warrantyForEnd:r[@"warranty_end"] ? [HLKit dateFromStamp:[r[@"warranty_end"] doubleValue]] : nil];
            switch (w) {
                case HLWarrantyActive: _warrantyActive++; break;
                case HLWarrantyExpiring: _warrantyExpiring++; break;
                case HLWarrantyExpired: _warrantyExpired++; break;
                default: _warrantyNone++; break;
            }
            if ([r[@"status"] integerValue] == HLItemStatusRepair) _underRepair++;
            if ([r[@"check_state"] integerValue] == 0) _notChecked++;
            [self bucket:rooms key:r[@"room_id"] name:[store nameOf:r[@"room_id"] ? @{@"name": r[@"room_name"] ?: @"", @"builtin": r[@"room_builtin"] ?: @""} : nil]
                    icon:r[@"room_icon"] ?: @"questionmark.square.dashed" row:r];
            [self bucket:cats key:r[@"category_id"] name:[store nameOf:r[@"category_id"] ? @{@"name": r[@"category_name"] ?: @"", @"builtin": r[@"category_builtin"] ?: @""} : nil]
                    icon:r[@"category_icon"] ?: @"questionmark.square.dashed" row:r];
        }
        _itemCount = rows.count;
        // Repairs: maintenance cost of the items in scope, grouped by currency and by item category.
        NSDictionary *catName = [NSMutableDictionary dictionary];
        for (HLRow *r in rows) ((NSMutableDictionary *)catName)[r[@"id"]] = [store nameOf:r[@"category_id"] ? @{@"name": r[@"category_name"] ?: @"", @"builtin": r[@"category_builtin"] ?: @""} : nil];
        for (HLRow *m in [store query:@"SELECT item_id, cost, cost_cur FROM maintenance" args:nil]) {
            if (![ids containsObject:m[@"item_id"]]) continue;
            _repairCount++;
            HLAdd(rep, m[@"cost_cur"], m[@"cost"]);
            NSString *cn = catName[m[@"item_id"]];
            NSMutableDictionary *b = repCat[cn] ?: [@{@"name": cn, @"cost": [NSMutableDictionary dictionary], @"count": @0} mutableCopy];
            b[@"count"] = @([b[@"count"] integerValue] + 1);
            HLAdd(b[@"cost"], m[@"cost_cur"], m[@"cost"]);
            repCat[cn] = b;
        }
        _purchaseTotals = buy; _valueTotals = val; _repairTotals = rep;
        _needsAttention = _underRepair + _warrantyExpiring;
        NSArray *sort = @[[NSSortDescriptor sortDescriptorWithKey:@"count" ascending:NO], [NSSortDescriptor sortDescriptorWithKey:@"name" ascending:YES]];
        _byRoom = [rooms.allValues sortedArrayUsingDescriptors:sort];
        _byCategory = [cats.allValues sortedArrayUsingDescriptors:sort];
        _repairByCategory = [repCat.allValues sortedArrayUsingDescriptors:sort];
    }
    return self;
}

- (void)bucket:(NSMutableDictionary *)map key:(NSString *)key name:(NSString *)name icon:(NSString *)icon row:(HLRow *)r {
    NSString *k = key ?: @"";
    NSMutableDictionary *b = map[k] ?: [@{@"key": k, @"name": name, @"icon": icon, @"count": @0, @"value": [NSMutableDictionary dictionary]} mutableCopy];
    b[@"count"] = @([b[@"count"] integerValue] + 1);
    HLAdd(b[@"value"], r[@"value_cur"], r[@"value"]);
    map[k] = b;
}

+ (NSString *)describe:(HLMoneyBag *)bag {
    if (bag.count == 0) return HLT(@"insights.noAmounts");
    NSString *def = [HLKit defaultCurrency];
    NSArray *keys = [bag.allKeys sortedArrayUsingComparator:^NSComparisonResult(NSString *a, NSString *b) {
        if ([a isEqualToString:def]) return NSOrderedAscending;
        if ([b isEqualToString:def]) return NSOrderedDescending;
        return [a compare:b];
    }];
    NSMutableArray *parts = [NSMutableArray array];
    for (NSString *c in keys) [parts addObject:[HLKit money:bag[c].longLongValue currency:c]];
    return [parts componentsJoinedByString:@"  ·  "];
}

+ (long long)primary:(HLMoneyBag *)bag otherCurrencies:(BOOL *)others {
    NSString *def = [HLKit defaultCurrency];
    if (others) *others = (bag.count > (bag[def] ? 1 : 0));
    return bag[def].longLongValue;
}

#pragma mark - Reminders

+ (void)requestPermission:(void (^)(BOOL))completion {
    [[UNUserNotificationCenter currentNotificationCenter] requestAuthorizationWithOptions:UNAuthorizationOptionAlert | UNAuthorizationOptionSound
                                                                        completionHandler:^(BOOL granted, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{ completion(granted); });
    }];
}

+ (void)rescheduleAll {
    UNUserNotificationCenter *center = [UNUserNotificationCenter currentNotificationCenter];
    [center getNotificationSettingsWithCompletionHandler:^(UNNotificationSettings *settings) {
        if (settings.authorizationStatus != UNAuthorizationStatusAuthorized &&
            settings.authorizationStatus != UNAuthorizationStatusProvisional) return;
        dispatch_async(dispatch_get_main_queue(), ^{
            [center removeAllPendingNotificationRequests];
            double now = [NSDate date].timeIntervalSince1970;
            NSCalendar *cal = [NSCalendar currentCalendar];
            for (HLRow *r in [[HLStore shared] allReminders]) {
                if ([r[@"fire_at"] doubleValue] <= now) continue;
                UNMutableNotificationContent *c = [[UNMutableNotificationContent alloc] init];
                c.title = r[@"title"] ?: @"";
                c.body = r[@"item_name"] ?: @"";
                c.sound = [UNNotificationSound defaultSound];
                NSDateComponents *dc = [cal components:NSCalendarUnitYear | NSCalendarUnitMonth | NSCalendarUnitDay | NSCalendarUnitHour | NSCalendarUnitMinute
                                              fromDate:[HLKit dateFromStamp:[r[@"fire_at"] doubleValue]]];
                UNCalendarNotificationTrigger *t = [UNCalendarNotificationTrigger triggerWithDateMatchingComponents:dc repeats:NO];
                [center addNotificationRequest:[UNNotificationRequest requestWithIdentifier:r[@"id"] content:c trigger:t] withCompletionHandler:nil];
            }
        });
    }];
}

@end
