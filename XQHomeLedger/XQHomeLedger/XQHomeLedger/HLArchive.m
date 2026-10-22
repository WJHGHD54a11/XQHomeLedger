//
//  HLArchive.m
//  XQHomeLedger
//

#import "HLArchive.h"
#import <UIKit/UIKit.h>
#import "HLKit.h"
#import "HLInsights.h"

NSString * const HLBackupFormat = @"homeledger-backup";
NSInteger const HLBackupVersion = 1;

// Table order matters for restore: parents before children.
static NSArray<NSString *> *HLBackupTables(void) {
    return @[@"room", @"category", @"item", @"tag", @"item_tag", @"maintenance", @"attachment", @"stocktake", @"stocktake_entry", @"reminder"];
}

@implementation HLArchive

#pragma mark - Helpers

+ (NSURL *)exportURL:(NSString *)base ext:(NSString *)ext {
    NSURL *dir = [[NSFileManager defaultManager].temporaryDirectory URLByAppendingPathComponent:@"Exports" isDirectory:YES];
    [[NSFileManager defaultManager] createDirectoryAtURL:dir withIntermediateDirectories:YES attributes:nil error:nil];
    NSDateFormatter *f = [[NSDateFormatter alloc] init];
    f.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
    f.dateFormat = @"yyyy-MM-dd-HHmm";
    NSURL *u = [dir URLByAppendingPathComponent:[NSString stringWithFormat:@"%@-%@.%@", base, [f stringFromDate:[NSDate date]], ext]];
    [[NSFileManager defaultManager] removeItemAtURL:u error:nil];
    return u;
}

+ (NSArray<HLRow *> *)itemsForScope:(NSString *)scope value:(NSString *)value {
    NSArray *all = [[HLStore shared] allItems];
    if ([scope isEqualToString:@"room"]) return [all filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"room_id == %@", value]];
    if ([scope isEqualToString:@"category"]) return [all filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"category_id == %@", value]];
    return all;
}

+ (NSString *)scopeTitle:(NSString *)scope value:(NSString *)value {
    HLStore *s = [HLStore shared];
    if ([scope isEqualToString:@"room"]) return [NSString stringWithFormat:HLT(@"report.scopeRoom"), [s nameOf:[s roomWithId:value]]];
    if ([scope isEqualToString:@"category"]) return [NSString stringWithFormat:HLT(@"report.scopeCategory"), [s nameOf:[s categoryWithId:value]]];
    return HLT(@"report.scopeAll");
}

+ (NSString *)roomOf:(HLRow *)r {
    return r[@"room_id"] ? [[HLStore shared] nameOf:@{@"name": r[@"room_name"] ?: @"", @"builtin": r[@"room_builtin"] ?: @""}] : HLT(@"common.unassigned");
}

+ (NSString *)categoryOf:(HLRow *)r {
    return r[@"category_id"] ? [[HLStore shared] nameOf:@{@"name": r[@"category_name"] ?: @"", @"builtin": r[@"category_builtin"] ?: @""}] : HLT(@"common.unassigned");
}

#pragma mark - CSV

+ (NSString *)csvCell:(id)v {
    NSString *s = [v isKindOfClass:[NSString class]] ? v : (v ? [v description] : @"");
    // Leading = + - @ would be run as formulas by spreadsheet apps.
    if (s.length && [@"=+-@" rangeOfString:[s substringToIndex:1]].location != NSNotFound) s = [@"'" stringByAppendingString:s];
    if ([s rangeOfCharacterFromSet:[NSCharacterSet characterSetWithCharactersInString:@",\"\n\r"]].location != NSNotFound) {
        s = [NSString stringWithFormat:@"\"%@\"", [s stringByReplacingOccurrencesOfString:@"\"" withString:@"\"\""]];
    }
    return s;
}

+ (NSString *)plainAmount:(id)minor cur:(NSString *)cur {
    if (!minor) return @"";
    return [HLKit moneyInput:[minor longLongValue] currency:cur ?: [HLKit defaultCurrency]];
}

+ (NSURL *)csvForScope:(NSString *)scope value:(NSString *)value error:(NSString **)error {
    NSArray *items = [self itemsForScope:scope value:value];
    if (items.count == 0) { if (error) *error = HLT(@"report.err.empty"); return nil; }
    NSArray *head = @[HLT(@"field.name"), HLT(@"field.room"), HLT(@"field.spot"), HLT(@"field.category"), HLT(@"field.brand"), HLT(@"field.model"),
                      HLT(@"field.serial"), HLT(@"field.status"), HLT(@"field.purchaseDate"), HLT(@"field.price"), HLT(@"csv.priceCurrency"),
                      HLT(@"field.value"), HLT(@"csv.valueCurrency"), HLT(@"field.warrantyEnd"), HLT(@"field.warranty"), HLT(@"field.tags"),
                      HLT(@"maint.count"), HLT(@"field.notes")];
    NSMutableArray *lines = [NSMutableArray array];
    NSMutableArray *h = [NSMutableArray array];
    for (NSString *x in head) [h addObject:[self csvCell:x]];
    [lines addObject:[h componentsJoinedByString:@","]];
    NSDateFormatter *iso = [[NSDateFormatter alloc] init];
    iso.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
    iso.dateFormat = @"yyyy-MM-dd";
    for (HLRow *r in items) {
        NSString *(^d)(NSString *) = ^NSString *(NSString *k) { return r[k] ? [iso stringFromDate:[HLKit dateFromStamp:[r[k] doubleValue]]] : @""; };
        HLWarranty w = [HLKit warrantyForEnd:r[@"warranty_end"] ? [HLKit dateFromStamp:[r[@"warranty_end"] doubleValue]] : nil];
        NSArray *cells = @[r[@"name"] ?: @"", [self roomOf:r], r[@"spot"] ?: @"", [self categoryOf:r], r[@"brand"] ?: @"", r[@"model"] ?: @"",
                           r[@"serial"] ?: @"", [HLKit statusName:[r[@"status"] integerValue]], d(@"purchase_date"),
                           [self plainAmount:r[@"price"] cur:r[@"price_cur"]], r[@"price"] ? (r[@"price_cur"] ?: @"") : @"",
                           [self plainAmount:r[@"value"] cur:r[@"value_cur"]], r[@"value"] ? (r[@"value_cur"] ?: @"") : @"",
                           d(@"warranty_end"), [HLKit warrantyName:w], r[@"tags"] ?: @"", r[@"maint_count"] ?: @0, r[@"notes"] ?: @""];
        NSMutableArray *row = [NSMutableArray array];
        for (id c in cells) [row addObject:[self csvCell:c]];
        [lines addObject:[row componentsJoinedByString:@","]];
    }
    // UTF-8 BOM so Excel opens Chinese text correctly.
    NSMutableData *data = [NSMutableData dataWithBytes:"\xEF\xBB\xBF" length:3];
    [data appendData:[[[lines componentsJoinedByString:@"\r\n"] stringByAppendingString:@"\r\n"] dataUsingEncoding:NSUTF8StringEncoding]];
    NSURL *u = [self exportURL:@"HomeLedger-Inventory" ext:@"csv"];
    if (![data writeToURL:u options:NSDataWritingAtomic error:nil]) { if (error) *error = HLT(@"report.err.write"); return nil; }
    return u;
}

#pragma mark - PDF

static const CGFloat kW = 595.2, kH = 841.8, kM = 42;

typedef struct { CGFloat y; NSInteger page; } HLCursor;

+ (NSDictionary *)font:(CGFloat)size bold:(BOOL)bold color:(UIColor *)c {
    NSMutableParagraphStyle *p = [[NSMutableParagraphStyle alloc] init];
    p.lineBreakMode = NSLineBreakByWordWrapping;
    // System font falls back to PingFang for Chinese, so both languages render.
    return @{NSFontAttributeName: [UIFont systemFontOfSize:size weight:bold ? UIFontWeightSemibold : UIFontWeightRegular],
             NSForegroundColorAttributeName: c, NSParagraphStyleAttributeName: p};
}

+ (CGFloat)height:(NSString *)s attrs:(NSDictionary *)a width:(CGFloat)w {
    return s.length ? ceil([s boundingRectWithSize:CGSizeMake(w, CGFLOAT_MAX) options:NSStringDrawingUsesLineFragmentOrigin attributes:a context:nil].size.height) : 0;
}

+ (void)page:(UIGraphicsPDFRendererContext *)ctx cursor:(HLCursor *)cur title:(NSString *)title {
    [ctx beginPage];
    cur->page += 1;
    [[HLKit mint] setFill];
    UIRectFill(CGRectMake(0, 0, kW, 64));
    UIBezierPath *mark = [UIBezierPath bezierPathWithRoundedRect:CGRectMake(kM, 18, 28, 28) cornerRadius:8];
    [[HLKit leaf] setFill];
    [mark fill];
    [@"HL" drawInRect:CGRectMake(kM, 25, 28, 14) withAttributes:@{NSFontAttributeName: [UIFont systemFontOfSize:10 weight:UIFontWeightHeavy],
                                                                  NSForegroundColorAttributeName: UIColor.whiteColor,
                                                                  NSParagraphStyleAttributeName: ({ NSMutableParagraphStyle *p = [NSMutableParagraphStyle new]; p.alignment = NSTextAlignmentCenter; p; })}];
    [@"HomeLedger" drawAtPoint:CGPointMake(kM + 38, 18) withAttributes:[self font:14 bold:YES color:[HLKit ink]]];
    [title drawAtPoint:CGPointMake(kM + 38, 37) withAttributes:[self font:9 bold:NO color:[HLKit ash]]];
    NSString *pg = [NSString stringWithFormat:HLT(@"report.page"), (long)cur->page];
    [[HLKit hair] setFill];
    UIRectFill(CGRectMake(kM, kH - 34, kW - 2 * kM, 0.6));
    [pg drawInRect:CGRectMake(kM, kH - 28, kW - 2 * kM, 12) withAttributes:({
        NSMutableDictionary *a = [[self font:8 bold:NO color:[HLKit ash]] mutableCopy];
        NSMutableParagraphStyle *p = [NSMutableParagraphStyle new]; p.alignment = NSTextAlignmentRight; a[NSParagraphStyleAttributeName] = p; a; })];
    [HLT(@"report.footer") drawAtPoint:CGPointMake(kM, kH - 28) withAttributes:[self font:8 bold:NO color:[HLKit ash]]];
    cur->y = 86;
}

+ (void)ensure:(CGFloat)h ctx:(UIGraphicsPDFRendererContext *)ctx cursor:(HLCursor *)cur title:(NSString *)title {
    if (cur->y + h > kH - 46) [self page:ctx cursor:cur title:title];
}

/// Draws wrapped text, breaking across pages when it is taller than the remaining space.
+ (void)text:(NSString *)s attrs:(NSDictionary *)a x:(CGFloat)x width:(CGFloat)w ctx:(UIGraphicsPDFRendererContext *)ctx cursor:(HLCursor *)cur title:(NSString *)title {
    if (!s.length) return;
    NSTextStorage *ts = [[NSTextStorage alloc] initWithString:s attributes:a];
    NSLayoutManager *lm = [[NSLayoutManager alloc] init];
    [ts addLayoutManager:lm];
    NSUInteger done = 0, total = lm.numberOfGlyphs, guard = 0;
    while (done < total && guard++ < 500) {
        CGFloat avail = kH - 46 - cur->y;
        if (avail < 14) { [self page:ctx cursor:cur title:title]; continue; }
        NSTextContainer *tc = [[NSTextContainer alloc] initWithSize:CGSizeMake(w, avail)];
        tc.lineFragmentPadding = 0;
        [lm addTextContainer:tc];
        NSRange g = [lm glyphRangeForTextContainer:tc];
        if (g.length == 0) { [self page:ctx cursor:cur title:title]; continue; }
        [lm drawGlyphsForGlyphRange:g atPoint:CGPointMake(x, cur->y)];
        cur->y += ceil([lm usedRectForTextContainer:tc].size.height);
        done = NSMaxRange(g);
    }
}

+ (NSURL *)pdfForScope:(NSString *)scope value:(NSString *)value error:(NSString **)error {
    NSArray *items = [self itemsForScope:scope value:value];
    if (items.count == 0) { if (error) *error = HLT(@"report.err.empty"); return nil; }
    NSString *scopeTitle = [self scopeTitle:scope value:value];
    NSString *title = [NSString stringWithFormat:@"%@ · %@", HLT(@"report.title"), scopeTitle];
    HLInsights *ins = [[HLInsights alloc] initWithItems:[items filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"status != 3"]]];
    NSURL *u = [self exportURL:@"HomeLedger-Report" ext:@"pdf"];
    UIGraphicsPDFRendererFormat *fmt = [UIGraphicsPDFRendererFormat defaultFormat];
    fmt.documentInfo = @{(__bridge NSString *)kCGPDFContextTitle: title, (__bridge NSString *)kCGPDFContextCreator: @"HomeLedger"};
    UIGraphicsPDFRenderer *r = [[UIGraphicsPDFRenderer alloc] initWithBounds:CGRectMake(0, 0, kW, kH) format:fmt];
    NSError *e = nil;
    BOOL ok = [r writePDFToURL:u withActions:^(UIGraphicsPDFRendererContext *ctx) {
        HLCursor cur = {0, 0};
        [self page:ctx cursor:&cur title:title];
        [self summary:ins items:items scope:scopeTitle ctx:ctx cursor:&cur title:title];
        [self groups:items ctx:ctx cursor:&cur title:title];
        cur.y += 10;
        [self text:HLT(@"report.disclaimer") attrs:[self font:8 bold:NO color:[HLKit ash]] x:kM width:kW - 2 * kM ctx:ctx cursor:&cur title:title];
    } error:&e];
    NSDictionary *attrs = [[NSFileManager defaultManager] attributesOfItemAtPath:u.path error:nil];
    if (!ok || [attrs fileSize] == 0) { if (error) *error = HLT(@"report.err.pdf"); return nil; }
    return u;
}

+ (void)heading:(NSString *)t ctx:(UIGraphicsPDFRendererContext *)ctx cursor:(HLCursor *)cur title:(NSString *)title {
    [self ensure:60 ctx:ctx cursor:cur title:title];
    cur->y += 6;
    [t drawAtPoint:CGPointMake(kM, cur->y) withAttributes:[self font:13 bold:YES color:[HLKit ink]]];
    cur->y += 20;
    [[HLKit leaf] setFill];
    UIRectFill(CGRectMake(kM, cur->y, 32, 2));
    cur->y += 10;
}

+ (void)pair:(NSString *)label value:(NSString *)value ctx:(UIGraphicsPDFRendererContext *)ctx cursor:(HLCursor *)cur title:(NSString *)title {
    NSDictionary *la = [self font:9.5 bold:YES color:[HLKit ash]], *va = [self font:9.5 bold:NO color:[HLKit ink]];
    CGFloat lw = 150, vw = kW - 2 * kM - lw - 8;
    CGFloat h = MAX([self height:label attrs:la width:lw], [self height:value attrs:va width:vw]);
    [self ensure:h + 4 ctx:ctx cursor:cur title:title];
    [label drawInRect:CGRectMake(kM, cur->y, lw, h) withAttributes:la];
    [value drawInRect:CGRectMake(kM + lw + 8, cur->y, vw, h) withAttributes:va];
    cur->y += h + 4;
}

+ (void)summary:(HLInsights *)ins items:(NSArray *)items scope:(NSString *)scope ctx:(UIGraphicsPDFRendererContext *)ctx cursor:(HLCursor *)cur title:(NSString *)title {
    NSString *home = [HLKit trim:[[HLStore shared] household][@"name"]];
    [self text:home.length ? home : HLT(@"home.defaultName") attrs:[self font:20 bold:YES color:[HLKit ink]] x:kM width:kW - 2 * kM ctx:ctx cursor:cur title:title];
    cur->y += 6;
    [self heading:HLT(@"report.summary") ctx:ctx cursor:cur title:title];
    [self pair:HLT(@"report.date") value:[HLKit dayTime:[NSDate date]] ctx:ctx cursor:cur title:title];
    [self pair:HLT(@"report.scope") value:scope ctx:ctx cursor:cur title:title];
    [self pair:HLT(@"report.items") value:[NSString stringWithFormat:HLT(@"report.itemsValue"), (long)items.count, (long)ins.itemCount] ctx:ctx cursor:cur title:title];
    [self pair:HLT(@"insights.purchase") value:[NSString stringWithFormat:@"%@  (%@)", [HLInsights describe:ins.purchaseTotals],
                                                [NSString stringWithFormat:HLT(@"home.basedOn"), (long)ins.pricedCount]] ctx:ctx cursor:cur title:title];
    [self pair:HLT(@"insights.value") value:[NSString stringWithFormat:@"%@  (%@)", [HLInsights describe:ins.valueTotals],
                                             [NSString stringWithFormat:HLT(@"home.basedOn"), (long)ins.valuedCount]] ctx:ctx cursor:cur title:title];
    [self pair:HLT(@"field.warranty") value:[NSString stringWithFormat:@"%@ %ld · %@ %ld · %@ %ld · %@ %ld",
                                             [HLKit warrantyName:HLWarrantyActive], (long)ins.warrantyActive, [HLKit warrantyName:HLWarrantyExpiring], (long)ins.warrantyExpiring,
                                             [HLKit warrantyName:HLWarrantyExpired], (long)ins.warrantyExpired, [HLKit warrantyName:HLWarrantyNone], (long)ins.warrantyNone]
                ctx:ctx cursor:cur title:title];
    [self pair:HLT(@"insights.repairs") value:[NSString stringWithFormat:@"%@  (%@)", [HLInsights describe:ins.repairTotals],
                                               [NSString stringWithFormat:HLT(@"report.records"), (long)ins.repairCount]] ctx:ctx cursor:cur title:title];
    [self text:HLT(@"insights.moneyNote") attrs:[self font:8 bold:NO color:[HLKit ash]] x:kM width:kW - 2 * kM ctx:ctx cursor:cur title:title];
}

+ (void)groups:(NSArray<HLRow *> *)items ctx:(UIGraphicsPDFRendererContext *)ctx cursor:(HLCursor *)cur title:(NSString *)title {
    // Group by room, in the user's room order, unassigned last.
    NSMutableArray *order = [NSMutableArray array];
    for (HLRow *r in [[HLStore shared] rooms]) [order addObject:r[@"id"]];
    [order addObject:@""];
    NSDictionary *ia = [self font:10 bold:YES color:[HLKit ink]], *da = [self font:8.5 bold:NO color:[HLKit ash]], *ma = [self font:9 bold:YES color:[HLKit ink]];
    CGFloat w = kW - 2 * kM, mw = 130;
    for (NSString *rid in order) {
        NSArray *group = [items filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(HLRow *r, NSDictionary *b) {
            return [(r[@"room_id"] ?: @"") isEqualToString:rid];
        }]];
        if (group.count == 0) continue;
        group = [group sortedArrayUsingDescriptors:@[[NSSortDescriptor sortDescriptorWithKey:@"name" ascending:YES selector:@selector(localizedStandardCompare:)]]];
        [self heading:[NSString stringWithFormat:@"%@ (%ld)", [self roomOf:group.firstObject], (long)group.count] ctx:ctx cursor:cur title:title];
        for (HLRow *r in group) {
            NSMutableArray *d = [NSMutableArray arrayWithObjects:[self categoryOf:r], [HLKit statusName:[r[@"status"] integerValue]], nil];
            for (NSString *k in @[@"brand", @"model", @"serial", @"spot"]) if ([HLKit trim:r[k]].length) [d addObject:r[k]];
            HLWarranty wy = [HLKit warrantyForEnd:r[@"warranty_end"] ? [HLKit dateFromStamp:[r[@"warranty_end"] doubleValue]] : nil];
            NSString *wtext = r[@"warranty_end"] ? [NSString stringWithFormat:@"%@ · %@", [HLKit warrantyName:wy], [HLKit day:[HLKit dateFromStamp:[r[@"warranty_end"] doubleValue]]]]
                                                 : [HLKit warrantyName:wy];
            [d addObject:wtext];
            if ([r[@"maint_count"] integerValue]) [d addObject:[NSString stringWithFormat:HLT(@"report.records"), (long)[r[@"maint_count"] integerValue]]];
            NSString *detail = [d componentsJoinedByString:@" · "];
            NSMutableArray *money = [NSMutableArray array];
            if (r[@"price"]) [money addObject:[NSString stringWithFormat:@"%@ %@", HLT(@"report.paid"), [HLKit money:[r[@"price"] longLongValue] currency:r[@"price_cur"] ?: [HLKit defaultCurrency]]]];
            if (r[@"value"]) [money addObject:[NSString stringWithFormat:@"%@ %@", HLT(@"report.worth"), [HLKit money:[r[@"value"] longLongValue] currency:r[@"value_cur"] ?: [HLKit defaultCurrency]]]];
            NSString *m = money.count ? [money componentsJoinedByString:@"\n"] : HLT(@"report.noAmount");
            CGFloat h = [self height:r[@"name"] attrs:ia width:w - mw - 10] + 2 + [self height:detail attrs:da width:w - mw - 10];
            h = MAX(h, [self height:m attrs:ma width:mw]) + 10;
            // Each item stays on one page; very long entries wrap onto the next.
            [self ensure:MIN(h, kH - 140) ctx:ctx cursor:cur title:title];
            CGFloat top = cur->y;
            [r[@"name"] drawInRect:CGRectMake(kM, top, w - mw - 10, h) withAttributes:ia];
            CGFloat nh = [self height:r[@"name"] attrs:ia width:w - mw - 10];
            [detail drawInRect:CGRectMake(kM, top + nh + 2, w - mw - 10, h) withAttributes:da];
            NSMutableDictionary *mr = [ma mutableCopy];
            NSMutableParagraphStyle *p = [NSMutableParagraphStyle new]; p.alignment = NSTextAlignmentRight; mr[NSParagraphStyleAttributeName] = p;
            [m drawInRect:CGRectMake(kM + w - mw, top, mw, h) withAttributes:mr];
            cur->y = top + h;
            [[HLKit hair] setFill];
            UIRectFill(CGRectMake(kM, cur->y - 5, w, 0.5));
        }
    }
}

#pragma mark - Backup

+ (NSURL *)backup:(NSString **)error {
    HLStore *store = [HLStore shared];
    NSMutableDictionary *root = [NSMutableDictionary dictionary];
    root[@"format"] = HLBackupFormat;
    root[@"version"] = @(HLBackupVersion);
    root[@"created"] = @([store now]);
    root[@"household"] = [store household];
    NSMutableDictionary *tables = [NSMutableDictionary dictionary];
    for (NSString *t in HLBackupTables()) tables[t] = [store query:[NSString stringWithFormat:@"SELECT * FROM %@", t] args:nil];
    root[@"tables"] = tables;
    // Photos travel inside the file, keyed by their stored name, so references stay valid.
    NSMutableDictionary *files = [NSMutableDictionary dictionary];
    NSInteger missing = 0;
    for (HLRow *a in tables[@"attachment"]) {
        NSData *d = [NSData dataWithContentsOfURL:[store attachmentURL:a[@"file"]]];
        if (d) files[a[@"file"]] = [d base64EncodedStringWithOptions:0]; else missing++;
    }
    root[@"files"] = files;
    root[@"missingFiles"] = @(missing);
    NSData *json = [NSJSONSerialization dataWithJSONObject:root options:0 error:nil];
    NSURL *u = [self exportURL:@"HomeLedger-Backup" ext:@"homeledger"];
    if (!json || ![json writeToURL:u options:NSDataWritingAtomic error:nil]) { if (error) *error = HLT(@"backup.err.write"); return nil; }
    return u;
}

+ (NSDictionary *)load:(NSURL *)url error:(NSString **)error {
    BOOL scoped = [url startAccessingSecurityScopedResource];
    NSData *d = [NSData dataWithContentsOfURL:url];
    if (scoped) [url stopAccessingSecurityScopedResource];
    if (!d) { if (error) *error = HLT(@"backup.err.read"); return nil; }
    id root = [NSJSONSerialization JSONObjectWithData:d options:0 error:nil];
    if (![root isKindOfClass:[NSDictionary class]] || ![root[@"format"] isEqual:HLBackupFormat] || ![root[@"tables"] isKindOfClass:[NSDictionary class]]) {
        if (error) *error = HLT(@"backup.err.format");
        return nil;
    }
    if ([root[@"version"] integerValue] > HLBackupVersion) { if (error) *error = HLT(@"backup.err.newer"); return nil; }
    return root;
}

+ (NSDictionary *)inspectBackup:(NSURL *)url error:(NSString **)error {
    NSDictionary *root = [self load:url error:error];
    if (!root) return nil;
    NSDictionary *t = root[@"tables"];
    HLStore *store = [HLStore shared];
    NSInteger dupItems = 0;
    for (HLRow *it in t[@"item"]) if ([it isKindOfClass:[NSDictionary class]] && it[@"id"] && [store itemWithId:it[@"id"]]) dupItems++;
    return @{@"created": root[@"created"] ?: @0, @"version": root[@"version"] ?: @0,
             @"items": @([t[@"item"] count]), @"rooms": @([t[@"room"] count]), @"categories": @([t[@"category"] count]),
             @"maintenance": @([t[@"maintenance"] count]), @"photos": @([root[@"files"] count]), @"stocktakes": @([t[@"stocktake"] count]),
             @"duplicates": @(dupItems)};
}

+ (NSDictionary *)restoreBackup:(NSURL *)url error:(NSString **)error {
    NSDictionary *root = [self load:url error:error];
    if (!root) return nil;
    HLStore *store = [HLStore shared];
    NSDictionary *t = root[@"tables"], *files = [root[@"files"] isKindOfClass:[NSDictionary class]] ? root[@"files"] : @{};
    __block NSInteger added = 0, skipped = 0;
    NSMutableArray *written = [NSMutableArray array];
    // Valid columns per table, read from the live schema, so unknown keys in a file are ignored.
    NSMutableDictionary *cols = [NSMutableDictionary dictionary];
    for (NSString *tb in HLBackupTables()) {
        NSMutableSet *c = [NSMutableSet set];
        for (HLRow *r in [store query:[NSString stringWithFormat:@"PRAGMA table_info(%@)", tb] args:nil]) [c addObject:r[@"name"]];
        cols[tb] = c;
    }
    NSMutableDictionary *tagMap = [NSMutableDictionary dictionary];   // backup tag id -> local tag id
    BOOL ok = [store transaction:^BOOL(NSString **e) {
        for (NSString *tb in HLBackupTables()) {
            for (HLRow *row in [t[tb] isKindOfClass:[NSArray class]] ? t[tb] : @[]) {
                if (![row isKindOfClass:[NSDictionary class]]) continue;
                NSMutableDictionary *r = [row mutableCopy];
                if ([tb isEqualToString:@"tag"]) {
                    // Tags are unique by name: reuse the local tag when the name already exists.
                    HLRow *local = [store row:@"SELECT id FROM tag WHERE name = ? COLLATE NOCASE" args:@[r[@"name"] ?: @""]];
                    if (local) { tagMap[r[@"id"] ?: @""] = local[@"id"]; skipped++; continue; }
                }
                if ([tb isEqualToString:@"item_tag"] && tagMap[r[@"tag_id"] ?: @""]) r[@"tag_id"] = tagMap[r[@"tag_id"]];
                NSMutableArray *names = [NSMutableArray array], *marks = [NSMutableArray array], *args = [NSMutableArray array];
                for (NSString *k in r) {
                    if (![cols[tb] containsObject:k]) continue;
                    id v = r[k];
                    if (![v isKindOfClass:[NSString class]] && ![v isKindOfClass:[NSNumber class]]) continue;
                    [names addObject:k]; [marks addObject:@"?"]; [args addObject:v];
                }
                if (names.count == 0) continue;
                NSString *sql = [NSString stringWithFormat:@"INSERT OR IGNORE INTO %@ (%@) VALUES (%@)", tb,
                                 [names componentsJoinedByString:@", "], [marks componentsJoinedByString:@", "]];
                long long before = [store scalar:@"SELECT total_changes()" args:nil];
                if (![store run:sql args:args error:e]) return NO;
                if ([store scalar:@"SELECT total_changes()" args:nil] > before) {
                    added++;
                    if ([tb isEqualToString:@"attachment"]) {
                        NSString *name = [r[@"file"] lastPathComponent];
                        NSData *d = [files[r[@"file"]] isKindOfClass:[NSString class]] ? [[NSData alloc] initWithBase64EncodedString:files[r[@"file"]] options:0] : nil;
                        NSURL *dst = [store attachmentURL:name];
                        if (d && ![[NSFileManager defaultManager] fileExistsAtPath:dst.path]) {
                            if (![d writeToURL:dst options:NSDataWritingAtomic error:nil]) { if (e) *e = HLT(@"backup.err.files"); return NO; }
                            [written addObject:dst];
                        }
                    }
                } else skipped++;
            }
        }
        return YES;
    } error:error];
    if (!ok) {
        // Nothing was committed, so the photos written for it are removed too.
        for (NSURL *u in written) [[NSFileManager defaultManager] removeItemAtURL:u error:nil];
        return nil;
    }
    [store notifyChanged];
    [HLInsights rescheduleAll];
    return @{@"added": @(added), @"skipped": @(skipped)};
}

@end
