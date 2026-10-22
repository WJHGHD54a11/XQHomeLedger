//
//  HLStore.m
//  XQHomeLedger
//

#import "HLStore.h"
#import "HLKit.h"
#import <sqlite3.h>

// Bump when the schema changes and add a step in -migrate.
static const int kSchemaVersion = 1;

@interface HLStore () {
    sqlite3 *_db;
}
@property (nonatomic, readwrite, nullable) NSString *openError;
@property (nonatomic) NSInteger txDepth;
@end

@implementation HLStore

+ (instancetype)shared {
    static HLStore *s;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [[HLStore alloc] init]; });
    return s;
}

- (NSURL *)baseDir {
    NSURL *u = [[NSFileManager defaultManager] URLsForDirectory:NSApplicationSupportDirectory inDomains:NSUserDomainMask].firstObject;
    u = [u URLByAppendingPathComponent:@"HomeLedger" isDirectory:YES];
    [[NSFileManager defaultManager] createDirectoryAtURL:u withIntermediateDirectories:YES attributes:nil error:nil];
    return u;
}

- (NSURL *)fileDir {
    NSURL *u = [[self baseDir] URLByAppendingPathComponent:@"Attachments" isDirectory:YES];
    [[NSFileManager defaultManager] createDirectoryAtURL:u withIntermediateDirectories:YES attributes:nil error:nil];
    return u;
}

- (instancetype)init {
    if ((self = [super init])) {
        NSString *path = [[self baseDir] URLByAppendingPathComponent:@"ledger.sqlite"].path;
        if (sqlite3_open_v2(path.UTF8String, &_db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, NULL) != SQLITE_OK) {
            _openError = _db ? @(sqlite3_errmsg(_db)) : @"sqlite3_open failed";
            if (_db) { sqlite3_close(_db); _db = NULL; }
            // Never delete the user's file. Run on an in-memory database and tell the user.
            sqlite3_open(":memory:", &_db);
        }
        sqlite3_exec(_db, "PRAGMA foreign_keys = ON; PRAGMA journal_mode = WAL;", NULL, NULL, NULL);
        NSString *err = nil;
        if (![self migrate:&err]) _openError = err;
    }
    return self;
}

#pragma mark - Schema

- (BOOL)migrate:(NSString **)error {
    int version = (int)[self scalar:@"PRAGMA user_version" args:nil];
    if (version >= kSchemaVersion) return YES;
    NSArray *v1 = @[
        @"CREATE TABLE IF NOT EXISTS household (id TEXT PRIMARY KEY, name TEXT NOT NULL, created REAL NOT NULL)",
        @"CREATE TABLE IF NOT EXISTS room (id TEXT PRIMARY KEY, name TEXT, builtin TEXT, icon TEXT NOT NULL DEFAULT 'square.grid.2x2', "
         "sort INTEGER NOT NULL DEFAULT 0, sample INTEGER NOT NULL DEFAULT 0, created REAL NOT NULL, updated REAL NOT NULL)",
        @"CREATE TABLE IF NOT EXISTS category (id TEXT PRIMARY KEY, name TEXT, builtin TEXT, icon TEXT NOT NULL DEFAULT 'tag', "
         "sort INTEGER NOT NULL DEFAULT 0, sample INTEGER NOT NULL DEFAULT 0, created REAL NOT NULL, updated REAL NOT NULL)",
        @"CREATE TABLE IF NOT EXISTS item (id TEXT PRIMARY KEY, name TEXT NOT NULL, "
         "room_id TEXT REFERENCES room(id) ON DELETE SET NULL, category_id TEXT REFERENCES category(id) ON DELETE SET NULL, "
         "spot TEXT, brand TEXT, model TEXT, serial TEXT, channel TEXT, purchase_date REAL, "
         "price INTEGER, price_cur TEXT, value INTEGER, value_cur TEXT, "
         "warranty_start REAL, warranty_end REAL, warranty_note TEXT, status INTEGER NOT NULL DEFAULT 0, notes TEXT, "
         "check_state INTEGER NOT NULL DEFAULT 0, checked_at REAL, sample INTEGER NOT NULL DEFAULT 0, "
         "created REAL NOT NULL, updated REAL NOT NULL)",
        @"CREATE TABLE IF NOT EXISTS tag (id TEXT PRIMARY KEY, name TEXT NOT NULL UNIQUE COLLATE NOCASE)",
        @"CREATE TABLE IF NOT EXISTS item_tag (item_id TEXT NOT NULL REFERENCES item(id) ON DELETE CASCADE, "
         "tag_id TEXT NOT NULL REFERENCES tag(id) ON DELETE CASCADE, PRIMARY KEY (item_id, tag_id))",
        @"CREATE TABLE IF NOT EXISTS maintenance (id TEXT PRIMARY KEY, item_id TEXT NOT NULL REFERENCES item(id) ON DELETE CASCADE, "
         "date REAL NOT NULL, kind INTEGER NOT NULL DEFAULT 0, issue TEXT, action TEXT, cost INTEGER, cost_cur TEXT, provider TEXT, notes TEXT, "
         "created REAL NOT NULL, updated REAL NOT NULL)",
        @"CREATE TABLE IF NOT EXISTS attachment (id TEXT PRIMARY KEY, owner_type TEXT NOT NULL, owner_id TEXT NOT NULL, "
         "file TEXT NOT NULL, sort INTEGER NOT NULL DEFAULT 0, created REAL NOT NULL)",
        @"CREATE TABLE IF NOT EXISTS stocktake (id TEXT PRIMARY KEY, scope TEXT NOT NULL, scope_value TEXT, title TEXT, "
         "started REAL NOT NULL, finished REAL)",
        @"CREATE TABLE IF NOT EXISTS stocktake_entry (id TEXT PRIMARY KEY, stocktake_id TEXT NOT NULL REFERENCES stocktake(id) ON DELETE CASCADE, "
         "item_id TEXT NOT NULL REFERENCES item(id) ON DELETE CASCADE, result INTEGER NOT NULL DEFAULT 0, note TEXT, moved_to TEXT, checked_at REAL)",
        @"CREATE TABLE IF NOT EXISTS reminder (id TEXT PRIMARY KEY, item_id TEXT NOT NULL REFERENCES item(id) ON DELETE CASCADE, "
         "kind TEXT NOT NULL, fire_at REAL NOT NULL, title TEXT NOT NULL, created REAL NOT NULL)",
        @"CREATE INDEX IF NOT EXISTS idx_item_room ON item(room_id)",
        @"CREATE INDEX IF NOT EXISTS idx_item_cat ON item(category_id)",
        @"CREATE INDEX IF NOT EXISTS idx_maint_item ON maintenance(item_id)",
        @"CREATE INDEX IF NOT EXISTS idx_att_owner ON attachment(owner_type, owner_id)",
        @"CREATE INDEX IF NOT EXISTS idx_entry_st ON stocktake_entry(stocktake_id)",
    ];
    return [self transaction:^BOOL(NSString **e) {
        for (NSString *sql in v1) if (![self run:sql args:nil error:e]) return NO;
        if (![self seedStructure:e]) return NO;
        return [self run:[NSString stringWithFormat:@"PRAGMA user_version = %d", kSchemaVersion] args:nil error:e];
    } error:error];
}

/// One household plus the built-in rooms and categories. They are ordinary rows the user can rename or delete.
- (BOOL)seedStructure:(NSString **)error {
    if ([self scalar:@"SELECT COUNT(*) FROM household" args:nil] == 0) {
        if (![self run:@"INSERT INTO household (id, name, created) VALUES (?, ?, ?)" args:@[[self makeId], @"", @([self now])] error:error]) return NO;
    }
    if ([self scalar:@"SELECT COUNT(*) FROM room" args:nil] == 0) {
        NSArray *rooms = @[@[@"room.living", @"sofa"], @[@"room.kitchen", @"fork.knife"], @[@"room.bedroom", @"bed.double"],
                           @[@"room.study", @"books.vertical"], @[@"room.bathroom", @"drop"], @[@"room.garage", @"car"], @[@"room.storage", @"shippingbox"]];
        for (NSUInteger i = 0; i < rooms.count; i++) {
            if (![self run:@"INSERT INTO room (id, builtin, icon, sort, created, updated) VALUES (?, ?, ?, ?, ?, ?)"
                      args:@[[self makeId], rooms[i][0], rooms[i][1], @(i), @([self now]), @([self now])] error:error]) return NO;
        }
    }
    if ([self scalar:@"SELECT COUNT(*) FROM category" args:nil] == 0) {
        NSArray *cats = @[@[@"cat.electronics", @"desktopcomputer"], @[@"cat.appliances", @"powerplug"], @[@"cat.furniture", @"bed.double"],
                          @[@"cat.tools", @"hammer"], @[@"cat.kitchen", @"cup.and.saucer"], @[@"cat.documents", @"doc.text"],
                          @[@"cat.jewelry", @"sparkles"], @[@"cat.sports", @"sportscourt"], @[@"cat.other", @"square.grid.2x2"]];
        for (NSUInteger i = 0; i < cats.count; i++) {
            if (![self run:@"INSERT INTO category (id, builtin, icon, sort, created, updated) VALUES (?, ?, ?, ?, ?, ?)"
                      args:@[[self makeId], cats[i][0], cats[i][1], @(i), @([self now]), @([self now])] error:error]) return NO;
        }
    }
    return YES;
}

#pragma mark - Generic SQL

- (sqlite3_stmt *)prepare:(NSString *)sql args:(NSArray *)args error:(NSString **)error {
    sqlite3_stmt *st = NULL;
    if (sqlite3_prepare_v2(_db, sql.UTF8String, -1, &st, NULL) != SQLITE_OK) {
        // Messages describe the statement, never the bound values (they may be personal data).
        NSLog(@"[HLStore] prepare failed: %s", sqlite3_errmsg(_db));
        if (error) *error = HLT(@"err.db");
        return NULL;
    }
    int idx = 1;
    for (id a in args ?: @[]) {
        if (a == [NSNull null]) sqlite3_bind_null(st, idx);
        else if ([a isKindOfClass:[NSString class]]) sqlite3_bind_text(st, idx, [a UTF8String], -1, SQLITE_TRANSIENT);
        else if ([a isKindOfClass:[NSData class]]) sqlite3_bind_blob(st, idx, [a bytes], (int)[a length], SQLITE_TRANSIENT);
        else if ([a isKindOfClass:[NSNumber class]]) {
            const char *t = [a objCType];
            if (strcmp(t, @encode(double)) == 0 || strcmp(t, @encode(float)) == 0) sqlite3_bind_double(st, idx, [a doubleValue]);
            else sqlite3_bind_int64(st, idx, [a longLongValue]);
        } else sqlite3_bind_null(st, idx);
        idx++;
    }
    return st;
}

- (HLRow *)readRow:(sqlite3_stmt *)st {
    NSMutableDictionary *d = [NSMutableDictionary dictionary];
    int n = sqlite3_column_count(st);
    for (int i = 0; i < n; i++) {
        NSString *name = @(sqlite3_column_name(st, i));
        switch (sqlite3_column_type(st, i)) {
            case SQLITE_INTEGER: d[name] = @(sqlite3_column_int64(st, i)); break;
            case SQLITE_FLOAT: d[name] = @(sqlite3_column_double(st, i)); break;
            case SQLITE_TEXT: {
                const unsigned char *t = sqlite3_column_text(st, i);
                d[name] = t ? @((const char *)t) : @"";
                break;
            }
            case SQLITE_BLOB: d[name] = [NSData dataWithBytes:sqlite3_column_blob(st, i) length:(NSUInteger)sqlite3_column_bytes(st, i)]; break;
            default: break;   // NULL: key absent
        }
    }
    return d;
}

- (NSArray<HLRow *> *)query:(NSString *)sql args:(NSArray *)args {
    sqlite3_stmt *st = [self prepare:sql args:args error:nil];
    if (!st) return @[];
    NSMutableArray *out = [NSMutableArray array];
    while (sqlite3_step(st) == SQLITE_ROW) [out addObject:[self readRow:st]];
    sqlite3_finalize(st);
    return out;
}

- (HLRow *)row:(NSString *)sql args:(NSArray *)args {
    return [self query:sql args:args].firstObject;
}

- (long long)scalar:(NSString *)sql args:(NSArray *)args {
    sqlite3_stmt *st = [self prepare:sql args:args error:nil];
    if (!st) return 0;
    long long v = sqlite3_step(st) == SQLITE_ROW ? sqlite3_column_int64(st, 0) : 0;
    sqlite3_finalize(st);
    return v;
}

- (BOOL)run:(NSString *)sql args:(NSArray *)args error:(NSString **)error {
    sqlite3_stmt *st = [self prepare:sql args:args error:error];
    if (!st) return NO;
    int rc = sqlite3_step(st);
    sqlite3_finalize(st);
    if (rc == SQLITE_DONE || rc == SQLITE_ROW) return YES;
    NSLog(@"[HLStore] step failed (%d): %s", rc, sqlite3_errmsg(_db));
    if (error) *error = (rc == SQLITE_CONSTRAINT) ? HLT(@"err.dbConstraint") : HLT(@"err.db");
    return NO;
}

- (BOOL)transaction:(BOOL (^)(NSString **))block error:(NSString **)error {
    // Nested calls join the outer transaction.
    if (self.txDepth > 0) return block(error);
    if (sqlite3_exec(_db, "BEGIN IMMEDIATE", NULL, NULL, NULL) != SQLITE_OK) { if (error) *error = HLT(@"err.db"); return NO; }
    self.txDepth = 1;
    NSString *e = nil;
    BOOL ok = block(&e);
    self.txDepth = 0;
    if (ok && sqlite3_exec(_db, "COMMIT", NULL, NULL, NULL) == SQLITE_OK) return YES;
    sqlite3_exec(_db, "ROLLBACK", NULL, NULL, NULL);
    if (error) *error = e ?: HLT(@"err.db");
    return NO;
}

- (NSString *)makeId {
    return [NSUUID UUID].UUIDString.lowercaseString;
}

- (double)now {
    return [NSDate date].timeIntervalSince1970;
}

- (void)notifyChanged {
    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:HLDataChangedNotification object:nil];
    });
}

/// Turns a values dictionary into bind args, mapping missing / NSNull / empty strings to SQL NULL.
- (id)sqlValue:(id)v {
    if (!v || v == [NSNull null]) return [NSNull null];
    if ([v isKindOfClass:[NSString class]] && [HLKit trim:v].length == 0) return [NSNull null];
    if ([v isKindOfClass:[NSDate class]]) return @([v timeIntervalSince1970]);
    return v;
}

#pragma mark - Household, rooms, categories

- (HLRow *)household {
    return [self row:@"SELECT * FROM household LIMIT 1" args:nil] ?: @{};
}

- (BOOL)renameHousehold:(NSString *)name error:(NSString **)error {
    BOOL ok = [self run:@"UPDATE household SET name = ?" args:@[[HLKit trim:name]] error:error];
    if (ok) [self notifyChanged];
    return ok;
}

- (NSArray<HLRow *> *)rooms {
    return [self query:@"SELECT r.*, (SELECT COUNT(*) FROM item i WHERE i.room_id = r.id) AS item_count FROM room r ORDER BY sort, created" args:nil];
}

- (NSArray<HLRow *> *)categories {
    return [self query:@"SELECT c.*, (SELECT COUNT(*) FROM item i WHERE i.category_id = c.id) AS item_count FROM category c ORDER BY sort, created" args:nil];
}

- (HLRow *)roomWithId:(NSString *)rid {
    return rid.length ? [self row:@"SELECT * FROM room WHERE id = ?" args:@[rid]] : nil;
}

- (HLRow *)categoryWithId:(NSString *)cid {
    return cid.length ? [self row:@"SELECT * FROM category WHERE id = ?" args:@[cid]] : nil;
}

- (NSString *)nameOf:(HLRow *)r {
    if (!r) return HLT(@"common.unassigned");
    NSString *n = [HLKit trim:r[@"name"]];
    if (n.length) return n;
    NSString *b = r[@"builtin"];
    return b.length ? HLT(b) : HLT(@"common.unassigned");
}

- (NSString *)saveNamed:(NSString *)table id:(NSString *)rowId name:(NSString *)name icon:(NSString *)icon error:(NSString **)error {
    NSString *n = [HLKit trim:name];
    if (!n.length) { if (error) *error = [NSString stringWithFormat:HLT(@"err.required"), HLT(@"field.name")]; return nil; }
    // Names are unique per table, compared against what the user sees (built-in names are localized).
    NSString *all = [NSString stringWithFormat:@"SELECT * FROM %@", table];
    for (HLRow *r in [self query:all args:nil]) {
        if (rowId && [r[@"id"] isEqualToString:rowId]) continue;
        if ([[self nameOf:r] caseInsensitiveCompare:n] == NSOrderedSame) {
            if (error) *error = [NSString stringWithFormat:HLT(@"err.nameTaken"), n];
            return nil;
        }
    }
    BOOL ok;
    NSString *rid = rowId;
    if (rid) {
        ok = [self run:[NSString stringWithFormat:@"UPDATE %@ SET name = ?, icon = ?, updated = ? WHERE id = ?", table]
                  args:@[n, icon, @([self now]), rid] error:error];
    } else {
        rid = [self makeId];
        long long sort = [self scalar:[NSString stringWithFormat:@"SELECT COALESCE(MAX(sort), -1) + 1 FROM %@", table] args:nil];
        ok = [self run:[NSString stringWithFormat:@"INSERT INTO %@ (id, name, icon, sort, created, updated) VALUES (?, ?, ?, ?, ?, ?)", table]
                  args:@[rid, n, icon, @(sort), @([self now]), @([self now])] error:error];
    }
    if (!ok) return nil;
    [self notifyChanged];
    return rid;
}

- (NSString *)saveRoom:(NSString *)rid name:(NSString *)name icon:(NSString *)icon error:(NSString **)error {
    return [self saveNamed:@"room" id:rid name:name icon:icon error:error];
}

- (NSString *)saveCategory:(NSString *)cid name:(NSString *)name icon:(NSString *)icon error:(NSString **)error {
    return [self saveNamed:@"category" id:cid name:name icon:icon error:error];
}

- (BOOL)deleteRoom:(NSString *)rid error:(NSString **)error {
    // item.room_id is ON DELETE SET NULL, so items stay and become Unassigned.
    BOOL ok = [self run:@"DELETE FROM room WHERE id = ?" args:@[rid] error:error];
    if (ok) [self notifyChanged];
    return ok;
}

- (BOOL)deleteCategory:(NSString *)cid error:(NSString **)error {
    BOOL ok = [self run:@"DELETE FROM category WHERE id = ?" args:@[cid] error:error];
    if (ok) [self notifyChanged];
    return ok;
}

#pragma mark - Items

static NSString * const kItemSelect =
    @"SELECT i.*, r.name AS room_name, r.builtin AS room_builtin, r.icon AS room_icon, "
     "c.name AS category_name, c.builtin AS category_builtin, c.icon AS category_icon, "
     "(SELECT GROUP_CONCAT(t.name, ', ') FROM item_tag it JOIN tag t ON t.id = it.tag_id WHERE it.item_id = i.id) AS tags, "
     "(SELECT COUNT(*) FROM maintenance m WHERE m.item_id = i.id) AS maint_count, "
     "(SELECT MAX(date) FROM maintenance m WHERE m.item_id = i.id) AS maint_last, "
     "(SELECT file FROM attachment a WHERE a.owner_type = 'item' AND a.owner_id = i.id ORDER BY sort, created LIMIT 1) AS photo "
     "FROM item i LEFT JOIN room r ON r.id = i.room_id LEFT JOIN category c ON c.id = i.category_id";

/// Columns the item form may write. Anything else in values is ignored.
+ (NSArray<NSString *> *)itemColumns {
    return @[@"name", @"room_id", @"category_id", @"spot", @"brand", @"model", @"serial", @"channel", @"purchase_date",
             @"price", @"price_cur", @"value", @"value_cur", @"warranty_start", @"warranty_end", @"warranty_note", @"status", @"notes"];
}

- (HLRow *)itemWithId:(NSString *)iid {
    return iid.length ? [self row:[kItemSelect stringByAppendingString:@" WHERE i.id = ?"] args:@[iid]] : nil;
}

- (NSArray<HLRow *> *)allItems {
    return [self query:[kItemSelect stringByAppendingString:@" ORDER BY i.updated DESC"] args:nil];
}

- (BOOL)writeTags:(NSArray<NSString *> *)tags item:(NSString *)iid error:(NSString **)error {
    if (![self run:@"DELETE FROM item_tag WHERE item_id = ?" args:@[iid] error:error]) return NO;
    NSMutableOrderedSet *clean = [NSMutableOrderedSet orderedSet];
    for (NSString *t in tags) { NSString *x = [HLKit trim:t]; if (x.length) [clean addObject:x]; }
    for (NSString *t in clean) {
        if (![self run:@"INSERT OR IGNORE INTO tag (id, name) VALUES (?, ?)" args:@[[self makeId], t] error:error]) return NO;
        if (![self run:@"INSERT OR IGNORE INTO item_tag (item_id, tag_id) SELECT ?, id FROM tag WHERE name = ? COLLATE NOCASE"
                  args:@[iid, t] error:error]) return NO;
    }
    // Tags no item uses any more are removed so filters stay meaningful.
    return [self run:@"DELETE FROM tag WHERE id NOT IN (SELECT tag_id FROM item_tag)" args:nil error:error];
}

- (NSString *)saveItem:(NSString *)iid values:(NSDictionary *)values tags:(NSArray<NSString *> *)tags error:(NSString **)error {
    if ([HLKit trim:values[@"name"]].length == 0) {
        if (error) *error = [NSString stringWithFormat:HLT(@"err.required"), HLT(@"field.name")];
        return nil;
    }
    __block NSString *rid = iid;
    BOOL ok = [self transaction:^BOOL(NSString **e) {
        NSArray *cols = [HLStore itemColumns];
        NSMutableArray *args = [NSMutableArray array];
        for (NSString *c in cols) [args addObject:[self sqlValue:values[c]]];
        if (rid) {
            NSMutableArray *sets = [NSMutableArray array];
            for (NSString *c in cols) [sets addObject:[c stringByAppendingString:@" = ?"]];
            [args addObjectsFromArray:@[@([self now]), rid]];
            NSString *sql = [NSString stringWithFormat:@"UPDATE item SET %@, updated = ? WHERE id = ?", [sets componentsJoinedByString:@", "]];
            if (![self run:sql args:args error:e]) return NO;
        } else {
            rid = [self makeId];
            NSMutableArray *marks = [NSMutableArray array];
            for (NSUInteger i = 0; i < cols.count; i++) [marks addObject:@"?"];
            [args insertObject:rid atIndex:0];
            [args addObjectsFromArray:@[@([self now]), @([self now])]];
            NSString *sql = [NSString stringWithFormat:@"INSERT INTO item (id, %@, created, updated) VALUES (?, %@, ?, ?)",
                             [cols componentsJoinedByString:@", "], [marks componentsJoinedByString:@", "]];
            if (![self run:sql args:args error:e]) return NO;
        }
        return [self writeTags:tags item:rid error:e];
    } error:error];
    if (!ok) return nil;
    [self notifyChanged];
    return rid;
}

- (NSString *)duplicateItem:(NSString *)iid error:(NSString **)error {
    HLRow *src = [self row:@"SELECT * FROM item WHERE id = ?" args:@[iid]];
    if (!src) { if (error) *error = HLT(@"err.notFound"); return nil; }
    NSMutableDictionary *v = [NSMutableDictionary dictionary];
    for (NSString *c in [HLStore itemColumns]) if (src[c]) v[c] = src[c];
    v[@"name"] = [NSString stringWithFormat:HLT(@"item.copyName"), src[@"name"] ?: @""];
    // A serial number identifies one physical object, so the copy starts without it.
    [v removeObjectForKey:@"serial"];
    return [self saveItem:nil values:v tags:[self tagsForItem:iid] error:error];
}

- (BOOL)deleteItems:(NSArray<NSString *> *)ids error:(NSString **)error {
    if (ids.count == 0) return YES;
    NSMutableSet *files = [NSMutableSet set];
    BOOL ok = [self transaction:^BOOL(NSString **e) {
        for (NSString *iid in ids) {
            // Photos of the item and of its maintenance records.
            for (HLRow *a in [self query:@"SELECT file FROM attachment WHERE (owner_type = 'item' AND owner_id = ?) OR "
                                          "(owner_type = 'maintenance' AND owner_id IN (SELECT id FROM maintenance WHERE item_id = ?))"
                                    args:@[iid, iid]]) [files addObject:a[@"file"]];
            if (![self run:@"DELETE FROM attachment WHERE (owner_type = 'item' AND owner_id = ?) OR "
                            "(owner_type = 'maintenance' AND owner_id IN (SELECT id FROM maintenance WHERE item_id = ?))"
                      args:@[iid, iid] error:e]) return NO;
            // maintenance, item_tag, stocktake_entry and reminder rows cascade.
            if (![self run:@"DELETE FROM item WHERE id = ?" args:@[iid] error:e]) return NO;
        }
        return [self run:@"DELETE FROM tag WHERE id NOT IN (SELECT tag_id FROM item_tag)" args:nil error:e];
    } error:error];
    if (!ok) return NO;
    for (NSString *f in files) [self removeFileIfUnused:f];
    [self notifyChanged];
    return YES;
}

- (BOOL)setStatus:(NSInteger)status forItems:(NSArray<NSString *> *)ids error:(NSString **)error {
    BOOL ok = [self transaction:^BOOL(NSString **e) {
        for (NSString *iid in ids) {
            if (![self run:@"UPDATE item SET status = ?, updated = ? WHERE id = ?" args:@[@(status), @([self now]), iid] error:e]) return NO;
        }
        return YES;
    } error:error];
    if (ok) [self notifyChanged];
    return ok;
}

- (BOOL)moveItems:(NSArray<NSString *> *)ids toRoom:(NSString *)rid error:(NSString **)error {
    BOOL ok = [self transaction:^BOOL(NSString **e) {
        for (NSString *iid in ids) {
            if (![self run:@"UPDATE item SET room_id = ?, updated = ? WHERE id = ?" args:@[rid ?: [NSNull null], @([self now]), iid] error:e]) return NO;
        }
        return YES;
    } error:error];
    if (ok) [self notifyChanged];
    return ok;
}

- (NSArray<NSString *> *)tagsForItem:(NSString *)iid {
    NSMutableArray *a = [NSMutableArray array];
    for (HLRow *r in [self query:@"SELECT t.name FROM item_tag it JOIN tag t ON t.id = it.tag_id WHERE it.item_id = ? ORDER BY t.name" args:@[iid]]) [a addObject:r[@"name"]];
    return a;
}

- (NSArray<NSString *> *)allTags {
    NSMutableArray *a = [NSMutableArray array];
    for (HLRow *r in [self query:@"SELECT name FROM tag ORDER BY name COLLATE NOCASE" args:nil]) [a addObject:r[@"name"]];
    return a;
}

#pragma mark - Maintenance

- (NSArray<HLRow *> *)maintenanceForItem:(NSString *)iid {
    return [self query:@"SELECT m.*, (SELECT COUNT(*) FROM attachment a WHERE a.owner_type = 'maintenance' AND a.owner_id = m.id) AS photo_count "
                        "FROM maintenance m WHERE m.item_id = ? ORDER BY m.date DESC, m.created DESC" args:@[iid]];
}

- (NSString *)saveMaintenance:(NSString *)mid item:(NSString *)iid values:(NSDictionary *)values error:(NSString **)error {
    NSArray *cols = @[@"date", @"kind", @"issue", @"action", @"cost", @"cost_cur", @"provider", @"notes"];
    if (!values[@"date"]) { if (error) *error = [NSString stringWithFormat:HLT(@"err.required"), HLT(@"field.date")]; return nil; }
    NSMutableArray *args = [NSMutableArray array];
    for (NSString *c in cols) [args addObject:[self sqlValue:values[c]]];
    __block NSString *rid = mid;
    BOOL ok = [self transaction:^BOOL(NSString **e) {
        if (rid) {
            [args addObjectsFromArray:@[@([self now]), rid]];
            if (![self run:@"UPDATE maintenance SET date = ?, kind = ?, issue = ?, action = ?, cost = ?, cost_cur = ?, provider = ?, notes = ?, "
                            "updated = ? WHERE id = ?" args:args error:e]) return NO;
        } else {
            rid = [self makeId];
            [args insertObject:iid atIndex:0];
            [args insertObject:rid atIndex:0];
            [args addObjectsFromArray:@[@([self now]), @([self now])]];
            if (![self run:@"INSERT INTO maintenance (id, item_id, date, kind, issue, action, cost, cost_cur, provider, notes, created, updated) "
                            "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)" args:args error:e]) return NO;
        }
        // The item shows its latest maintenance, so its modified time moves too.
        return [self run:@"UPDATE item SET updated = ? WHERE id = ?" args:@[@([self now]), iid] error:e];
    } error:error];
    if (!ok) return nil;
    [self notifyChanged];
    return rid;
}

- (BOOL)deleteMaintenance:(NSString *)mid error:(NSString **)error {
    NSMutableArray *files = [NSMutableArray array];
    for (HLRow *a in [self attachmentsFor:@"maintenance" owner:mid]) [files addObject:a[@"file"]];
    BOOL ok = [self transaction:^BOOL(NSString **e) {
        return [self run:@"DELETE FROM attachment WHERE owner_type = 'maintenance' AND owner_id = ?" args:@[mid] error:e]
            && [self run:@"DELETE FROM maintenance WHERE id = ?" args:@[mid] error:e];
    } error:error];
    if (!ok) return NO;
    for (NSString *f in files) [self removeFileIfUnused:f];
    [self notifyChanged];
    return YES;
}

#pragma mark - Attachments

- (NSString *)storeImage:(UIImage *)image error:(NSString **)error {
    // Long side capped at 1800 px: sharp on screen and in reports without filling the device.
    CGFloat maxSide = 1800, longSide = MAX(image.size.width, image.size.height);
    UIImage *img = image;
    if (longSide > maxSide) {
        CGFloat k = maxSide / longSide;
        CGSize sz = CGSizeMake(floor(image.size.width * k), floor(image.size.height * k));
        UIGraphicsImageRendererFormat *f = [UIGraphicsImageRendererFormat defaultFormat];
        f.scale = 1;
        img = [[[UIGraphicsImageRenderer alloc] initWithSize:sz format:f] imageWithActions:^(UIGraphicsImageRendererContext *c) {
            [image drawInRect:CGRectMake(0, 0, sz.width, sz.height)];
        }];
    }
    NSData *jpg = UIImageJPEGRepresentation(img, 0.82);
    NSString *name = [[self makeId] stringByAppendingPathExtension:@"jpg"];
    if (!jpg || ![jpg writeToURL:[self attachmentURL:name] options:NSDataWritingAtomic error:nil]) {
        if (error) *error = HLT(@"err.photoSave");
        return nil;
    }
    return name;
}

- (NSURL *)attachmentURL:(NSString *)file {
    return [[self fileDir] URLByAppendingPathComponent:file.lastPathComponent];
}

- (UIImage *)imageNamed:(NSString *)file {
    return file.length ? [UIImage imageWithContentsOfFile:[self attachmentURL:file].path] : nil;
}

- (NSArray<HLRow *> *)attachmentsFor:(NSString *)ownerType owner:(NSString *)ownerId {
    return [self query:@"SELECT * FROM attachment WHERE owner_type = ? AND owner_id = ? ORDER BY sort, created" args:@[ownerType, ownerId]];
}

- (BOOL)addAttachment:(NSString *)file ownerType:(NSString *)type owner:(NSString *)ownerId error:(NSString **)error {
    long long sort = [self scalar:@"SELECT COALESCE(MAX(sort), -1) + 1 FROM attachment WHERE owner_type = ? AND owner_id = ?" args:@[type, ownerId]];
    BOOL ok = [self run:@"INSERT INTO attachment (id, owner_type, owner_id, file, sort, created) VALUES (?, ?, ?, ?, ?, ?)"
                   args:@[[self makeId], type, ownerId, file, @(sort), @([self now])] error:error];
    if (ok) [self notifyChanged];
    return ok;
}

- (BOOL)deleteAttachment:(NSString *)aid error:(NSString **)error {
    HLRow *a = [self row:@"SELECT * FROM attachment WHERE id = ?" args:@[aid]];
    if (!a) return YES;
    if (![self run:@"DELETE FROM attachment WHERE id = ?" args:@[aid] error:error]) return NO;
    [self removeFileIfUnused:a[@"file"]];
    [self notifyChanged];
    return YES;
}

- (void)removeFileIfUnused:(NSString *)file {
    if (!file.length || self.openError) return;
    if ([self scalar:@"SELECT COUNT(*) FROM attachment WHERE file = ?" args:@[file]] > 0) return;
    [[NSFileManager defaultManager] removeItemAtURL:[self attachmentURL:file] error:nil];
}

- (void)sweepFiles {
    if (self.openError) return;   // in-memory fallback: references unknown, keep every file
    NSMutableSet *used = [NSMutableSet set];
    for (HLRow *r in [self query:@"SELECT file FROM attachment" args:nil]) [used addObject:r[@"file"]];
    for (NSString *f in [[NSFileManager defaultManager] contentsOfDirectoryAtPath:[self fileDir].path error:nil]) {
        if (![used containsObject:f]) [[NSFileManager defaultManager] removeItemAtURL:[self attachmentURL:f] error:nil];
    }
}

#pragma mark - Stocktake

- (HLRow *)openStocktake {
    return [self row:@"SELECT * FROM stocktake WHERE finished IS NULL ORDER BY started DESC LIMIT 1" args:nil];
}

- (NSArray<HLRow *> *)stocktakes {
    return [self query:@"SELECT s.*, "
                        "(SELECT COUNT(*) FROM stocktake_entry e WHERE e.stocktake_id = s.id) AS total, "
                        "(SELECT COUNT(*) FROM stocktake_entry e WHERE e.stocktake_id = s.id AND e.result = 1) AS checked, "
                        "(SELECT COUNT(*) FROM stocktake_entry e WHERE e.stocktake_id = s.id AND e.result IN (2, 3)) AS flagged "
                        "FROM stocktake s ORDER BY s.started DESC" args:nil];
}

- (NSString *)startStocktakeScope:(NSString *)scope value:(NSString *)value error:(NSString **)error {
    if ([self openStocktake]) { if (error) *error = HLT(@"err.stocktakeOpen"); return nil; }
    NSString *where = @"status != 3";   // disposed items are not counted
    NSArray *args = @[];
    if ([scope isEqualToString:@"room"] && value) { where = [where stringByAppendingString:@" AND room_id = ?"]; args = @[value]; }
    else if ([scope isEqualToString:@"category"] && value) { where = [where stringByAppendingString:@" AND category_id = ?"]; args = @[value]; }
    NSArray *items = [self query:[NSString stringWithFormat:@"SELECT id FROM item WHERE %@", where] args:args];
    if (items.count == 0) { if (error) *error = HLT(@"err.stocktakeEmpty"); return nil; }
    NSString *title = HLT(@"stock.scopeAll");
    if ([scope isEqualToString:@"room"]) title = [self nameOf:[self roomWithId:value]];
    else if ([scope isEqualToString:@"category"]) title = [self nameOf:[self categoryWithId:value]];
    NSString *sid = [self makeId];
    BOOL ok = [self transaction:^BOOL(NSString **e) {
        if (![self run:@"INSERT INTO stocktake (id, scope, scope_value, title, started) VALUES (?, ?, ?, ?, ?)"
                  args:@[sid, scope, value ?: [NSNull null], title, @([self now])] error:e]) return NO;
        for (HLRow *it in items) {
            if (![self run:@"INSERT INTO stocktake_entry (id, stocktake_id, item_id) VALUES (?, ?, ?)" args:@[[self makeId], sid, it[@"id"]] error:e]) return NO;
            // Items in this session go back to Not Checked until confirmed.
            if (![self run:@"UPDATE item SET check_state = 0 WHERE id = ?" args:@[it[@"id"]] error:e]) return NO;
        }
        return YES;
    } error:error];
    if (!ok) return nil;
    [self notifyChanged];
    return sid;
}

- (NSArray<HLRow *> *)entriesFor:(NSString *)sid {
    return [self query:@"SELECT e.*, i.name AS item_name, i.room_id, i.status, r.name AS room_name, r.builtin AS room_builtin, "
                        "(SELECT file FROM attachment a WHERE a.owner_type = 'item' AND a.owner_id = i.id ORDER BY sort LIMIT 1) AS photo "
                        "FROM stocktake_entry e JOIN item i ON i.id = e.item_id LEFT JOIN room r ON r.id = i.room_id "
                        "WHERE e.stocktake_id = ? ORDER BY e.result, i.name COLLATE NOCASE" args:@[sid]];
}

- (BOOL)markEntry:(NSString *)eid result:(NSInteger)result note:(NSString *)note moveTo:(NSString *)rid error:(NSString **)error {
    HLRow *e = [self row:@"SELECT * FROM stocktake_entry WHERE id = ?" args:@[eid]];
    if (!e) { if (error) *error = HLT(@"err.notFound"); return NO; }
    BOOL ok = [self transaction:^BOOL(NSString **err) {
        if (![self run:@"UPDATE stocktake_entry SET result = ?, note = ?, moved_to = ?, checked_at = ? WHERE id = ?"
                  args:@[@(result), [self sqlValue:note], rid ?: [NSNull null], result ? @([self now]) : [NSNull null], eid] error:err]) return NO;
        if (rid && ![self run:@"UPDATE item SET room_id = ?, updated = ? WHERE id = ?" args:@[rid, @([self now]), e[@"item_id"]] error:err]) return NO;
        return [self run:@"UPDATE item SET check_state = ?, checked_at = ? WHERE id = ?"
                    args:@[@(result == 1 ? 1 : 0), result == 1 ? @([self now]) : [NSNull null], e[@"item_id"]] error:err];
    } error:error];
    if (ok) [self notifyChanged];
    return ok;
}

- (BOOL)finishStocktake:(NSString *)sid error:(NSString **)error {
    BOOL ok = [self run:@"UPDATE stocktake SET finished = ? WHERE id = ?" args:@[@([self now]), sid] error:error];
    if (ok) [self notifyChanged];
    return ok;
}

- (BOOL)deleteStocktake:(NSString *)sid error:(NSString **)error {
    BOOL ok = [self run:@"DELETE FROM stocktake WHERE id = ?" args:@[sid] error:error];
    if (ok) [self notifyChanged];
    return ok;
}

#pragma mark - Reminders

- (NSArray<HLRow *> *)remindersForItem:(NSString *)iid {
    return [self query:@"SELECT * FROM reminder WHERE item_id = ? ORDER BY fire_at" args:@[iid]];
}

- (NSArray<HLRow *> *)allReminders {
    return [self query:@"SELECT r.*, i.name AS item_name FROM reminder r JOIN item i ON i.id = r.item_id ORDER BY r.fire_at" args:nil];
}

- (NSString *)saveReminder:(NSString *)rid item:(NSString *)iid kind:(NSString *)kind fireAt:(double)fireAt title:(NSString *)title error:(NSString **)error {
    NSString *r = rid ?: [self makeId];
    BOOL ok = rid
        ? [self run:@"UPDATE reminder SET kind = ?, fire_at = ?, title = ? WHERE id = ?" args:@[kind, @(fireAt), title, rid] error:error]
        : [self run:@"INSERT INTO reminder (id, item_id, kind, fire_at, title, created) VALUES (?, ?, ?, ?, ?, ?)"
               args:@[r, iid, kind, @(fireAt), title, @([self now])] error:error];
    if (!ok) return nil;
    [self notifyChanged];
    return r;
}

- (BOOL)deleteReminder:(NSString *)rid error:(NSString **)error {
    BOOL ok = [self run:@"DELETE FROM reminder WHERE id = ?" args:@[rid] error:error];
    if (ok) [self notifyChanged];
    return ok;
}

#pragma mark - Sample data

- (BOOL)hasSampleData {
    return [self scalar:@"SELECT COUNT(*) FROM item WHERE sample = 1" args:nil] > 0;
}

/// Optional demo records, flagged sample = 1 so they can be removed in one step. Names say "Sample".
- (BOOL)loadSampleData:(NSString **)error {
    if ([self hasSampleData]) return YES;
    NSString *cur = [HLKit defaultCurrency];
    NSInteger k = [HLKit minorDigits:cur] == 0 ? 1 : 100;   // amounts below are whole units
    NSCalendar *cal = [NSCalendar currentCalendar];
    NSDate *(^ago)(NSInteger) = ^NSDate *(NSInteger days) { return [cal dateByAddingUnit:NSCalendarUnitDay value:-days toDate:[NSDate date] options:0]; };
    NSString *(^roomFor)(NSString *) = ^NSString *(NSString *b) { return [self row:@"SELECT id FROM room WHERE builtin = ?" args:@[b]][@"id"]; };
    NSString *(^catFor)(NSString *) = ^NSString *(NSString *b) { return [self row:@"SELECT id FROM category WHERE builtin = ?" args:@[b]][@"id"]; };
    NSArray *samples = @[
        @{@"name": HLT(@"sample.tv"), @"room": @"room.living", @"cat": @"cat.electronics", @"brand": @"Sample", @"price": @899, @"value": @520,
          @"bought": @420, @"wEnd": @(-35), @"status": @(HLItemStatusInUse)},
        @{@"name": HLT(@"sample.coffee"), @"room": @"room.kitchen", @"cat": @"cat.appliances", @"brand": @"Sample", @"price": @249, @"value": @150,
          @"bought": @300, @"wEnd": @20, @"status": @(HLItemStatusInUse)},
        @{@"name": HLT(@"sample.drill"), @"room": @"room.garage", @"cat": @"cat.tools", @"brand": @"Sample", @"price": @129, @"bought": @700,
          @"status": @(HLItemStatusRepair)},
        @{@"name": HLT(@"sample.bike"), @"room": @"room.storage", @"cat": @"cat.sports", @"brand": @"Sample", @"price": @640, @"value": @380,
          @"bought": @900, @"wEnd": @400, @"status": @(HLItemStatusStored)},
    ];
    BOOL ok = [self transaction:^BOOL(NSString **e) {
        for (NSDictionary *s in samples) {
            NSMutableDictionary *v = [NSMutableDictionary dictionary];
            v[@"name"] = s[@"name"];
            v[@"room_id"] = roomFor(s[@"room"]) ?: [NSNull null];
            v[@"category_id"] = catFor(s[@"cat"]) ?: [NSNull null];
            v[@"brand"] = s[@"brand"];
            v[@"purchase_date"] = ago([s[@"bought"] integerValue]);
            v[@"price"] = @([s[@"price"] longLongValue] * k);
            v[@"price_cur"] = cur;
            if (s[@"value"]) { v[@"value"] = @([s[@"value"] longLongValue] * k); v[@"value_cur"] = cur; }
            if (s[@"wEnd"]) { v[@"warranty_start"] = v[@"purchase_date"]; v[@"warranty_end"] = ago(-[s[@"wEnd"] integerValue]); }
            v[@"status"] = s[@"status"];
            NSString *iid = [self saveItem:nil values:v tags:@[HLT(@"sample.tag")] error:e];
            if (!iid) return NO;
            if (![self run:@"UPDATE item SET sample = 1 WHERE id = ?" args:@[iid] error:e]) return NO;
            if ([s[@"status"] integerValue] == HLItemStatusRepair) {
                NSDictionary *m = @{@"date": ago(12), @"kind": @1, @"issue": HLT(@"sample.issue"), @"action": HLT(@"sample.action"),
                                    @"cost": @(35 * k), @"cost_cur": cur, @"provider": HLT(@"sample.provider")};
                if (![self saveMaintenance:nil item:iid values:m error:e]) return NO;
            }
        }
        return YES;
    } error:error];
    if (ok) [self notifyChanged];
    return ok;
}

- (BOOL)removeSampleData:(NSString **)error {
    NSMutableArray *ids = [NSMutableArray array];
    for (HLRow *r in [self query:@"SELECT id FROM item WHERE sample = 1" args:nil]) [ids addObject:r[@"id"]];
    return [self deleteItems:ids error:error];
}

- (BOOL)eraseAll:(NSString **)error {
    BOOL ok = [self transaction:^BOOL(NSString **e) {
        for (NSString *t in @[@"reminder", @"stocktake_entry", @"stocktake", @"attachment", @"maintenance", @"item_tag", @"tag", @"item", @"room", @"category"]) {
            if (![self run:[NSString stringWithFormat:@"DELETE FROM %@", t] args:nil error:e]) return NO;
        }
        if (![self run:@"UPDATE household SET name = ''" args:nil error:e]) return NO;
        return [self seedStructure:e];
    } error:error];
    if (!ok) return NO;
    for (NSString *f in [[NSFileManager defaultManager] contentsOfDirectoryAtPath:[self fileDir].path error:nil]) {
        [[NSFileManager defaultManager] removeItemAtURL:[self attachmentURL:f] error:nil];
    }
    [self notifyChanged];
    return YES;
}

@end
