#import <Foundation/Foundation.h>
#import <dlfcn.h>
#import <sqlite3.h>

// KeyboardServices is a private framework, so load it dynamically and keep
// compile-time dependencies limited to Foundation.
@interface NSObject (DictKeyboardServices)
- (void)addEntries:(NSArray *)entriesToAdd
     removeEntries:(NSArray *)entriesToRemove
withCompletionHandler:(void (^)(NSError *error))completionHandler;
@end

static const int kOperationTimeoutSeconds = 10;
static NSString *const kShortcutKey = @"shortcut";
static NSString *const kPhraseKey = @"phrase";

static BOOL loadKeyboardServices(void) {
    const char *frameworkPath =
        "/System/Library/PrivateFrameworks/KeyboardServices.framework/KeyboardServices";
    void *framework = dlopen(frameworkPath, RTLD_LAZY);
    if (framework == NULL) {
        fprintf(stderr, "KeyboardServicesを読み込めません: %s\n", dlerror());
        return NO;
    }

    if (NSClassFromString(@"_KSTextReplacementEntry") == Nil ||
        NSClassFromString(@"_KSTextReplacementClientStore") == Nil) {
        fprintf(stderr, "このmacOSではユーザ辞書APIを利用できません。\n");
        return NO;
    }
    return YES;
}

static NSArray *currentValues(void) {
    NSString *databasePath = [NSHomeDirectory()
        stringByAppendingPathComponent:@"Library/KeyboardServices/TextReplacements.db"];
    if (![[NSFileManager defaultManager] fileExistsAtPath:databasePath]) return @[];

    sqlite3 *database = NULL;
    int openResult = sqlite3_open_v2(databasePath.fileSystemRepresentation,
                                     &database, SQLITE_OPEN_READONLY, NULL);
    if (openResult != SQLITE_OK) {
        fprintf(stderr, "ユーザ辞書DBを開けません: %s\n",
                database == NULL ? "unknown error" : sqlite3_errmsg(database));
        if (database != NULL) sqlite3_close(database);
        return nil;
    }
    sqlite3_busy_timeout(database, 2000);

    const char *sql =
        "SELECT ZSHORTCUT, ZPHRASE FROM ZTEXTREPLACEMENTENTRY "
        "WHERE COALESCE(ZWASDELETED, 0) = 0 "
        "ORDER BY ZSHORTCUT COLLATE BINARY, ZPHRASE COLLATE BINARY";
    sqlite3_stmt *statement = NULL;
    if (sqlite3_prepare_v2(database, sql, -1, &statement, NULL) != SQLITE_OK) {
        fprintf(stderr, "ユーザ辞書DBを読めません: %s\n", sqlite3_errmsg(database));
        sqlite3_close(database);
        return nil;
    }

    NSMutableArray *values = [NSMutableArray array];
    int stepResult;
    while ((stepResult = sqlite3_step(statement)) == SQLITE_ROW) {
        const void *shortcutBytes = sqlite3_column_blob(statement, 0);
        int shortcutLength = sqlite3_column_bytes(statement, 0);
        const void *phraseBytes = sqlite3_column_blob(statement, 1);
        int phraseLength = sqlite3_column_bytes(statement, 1);
        NSString *shortcut = [[NSString alloc] initWithBytes:shortcutBytes
                                                      length:shortcutLength
                                                    encoding:NSUTF8StringEncoding];
        NSString *phrase = [[NSString alloc] initWithBytes:phraseBytes
                                                    length:phraseLength
                                                  encoding:NSUTF8StringEncoding];
        if (shortcut != nil && phrase != nil) {
            [values addObject:@{ kShortcutKey : shortcut, kPhraseKey : phrase }];
        }
    }

    if (stepResult != SQLITE_DONE) {
        fprintf(stderr, "ユーザ辞書DBを読めません: %s\n", sqlite3_errmsg(database));
        sqlite3_finalize(statement);
        sqlite3_close(database);
        return nil;
    }

    sqlite3_finalize(statement);
    sqlite3_close(database);
    return values;
}

static NSString *valueShortcut(NSDictionary *value) {
    return value[kShortcutKey];
}

static NSString *valuePhrase(NSDictionary *value) {
    return value[kPhraseKey];
}

static BOOL valueMatches(NSDictionary *value, NSString *shortcut, NSString *phrase) {
    return [valueShortcut(value) isEqualToString:shortcut] &&
           (phrase == nil || [valuePhrase(value) isEqualToString:phrase]);
}

static id newEntry(NSString *shortcut, NSString *phrase) {
    id entry = [[NSClassFromString(@"_KSTextReplacementEntry") alloc] init];
    [entry setValue:shortcut forKey:@"shortcut"];
    [entry setValue:phrase forKey:@"phrase"];
    return entry;
}

static int submitEntries(NSArray *entries, BOOL adding) {
    id store = [[NSClassFromString(@"_KSTextReplacementClientStore") alloc] init];
    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
    __block NSError *operationError = nil;
    [store addEntries:adding ? entries : nil
         removeEntries:adding ? nil : entries
 withCompletionHandler:^(NSError *error) {
     operationError = error;
     dispatch_semaphore_signal(semaphore);
 }];

    long timedOut = dispatch_semaphore_wait(
        semaphore,
        dispatch_time(DISPATCH_TIME_NOW,
                      (int64_t)kOperationTimeoutSeconds * NSEC_PER_SEC));
    if (timedOut != 0) {
        fprintf(stderr, "ユーザ辞書の更新がタイムアウトしました。\n");
        return EXIT_FAILURE;
    }

    if (operationError != nil && operationError.code != 0) {
        fprintf(stderr, "%s\n", operationError.localizedDescription.UTF8String);
        return EXIT_FAILURE;
    }
    return EXIT_SUCCESS;
}

static int addEntry(NSString *shortcut, NSString *phrase) {
    BOOL alreadyRegistered = NO;
    NSArray *values = currentValues();
    if (values == nil) return EXIT_FAILURE;
    for (NSDictionary *value in values) {
        if (valueMatches(value, shortcut, phrase)) {
            alreadyRegistered = YES;
            break;
        }
    }

    int result = submitEntries(@[ newEntry(shortcut, phrase) ], YES);
    if (result == EXIT_SUCCESS) {
        printf("%d\n", alreadyRegistered ? 1 : 0);
    }
    return result;
}

static int listEntries(NSString *query) {
    NSArray *values = currentValues();
    if (values == nil) return EXIT_FAILURE;

    NSUInteger matched = 0;
    for (NSDictionary *value in values) {
        NSString *shortcut = valueShortcut(value);
        NSString *phrase = valuePhrase(value);
        if (query != nil &&
            [shortcut rangeOfString:query].location == NSNotFound &&
            [phrase rangeOfString:query].location == NSNotFound) {
            continue;
        }
        printf("%s → %s\n", shortcut.UTF8String, phrase.UTF8String);
        matched++;
    }

    if (matched == 0) {
        if (query != nil) {
            printf("「%s」に一致する登録はありません。\n", query.UTF8String);
        } else {
            printf("登録はありません。\n");
        }
    }
    return EXIT_SUCCESS;
}

static int removeEntries(NSString *shortcut, NSString *phrase) {
    NSMutableArray *matches = [NSMutableArray array];
    NSArray *values = currentValues();
    if (values == nil) return EXIT_FAILURE;
    for (NSDictionary *value in values) {
        if (valueMatches(value, shortcut, phrase)) {
            [matches addObject:newEntry(valueShortcut(value), valuePhrase(value))];
        }
    }

    if (matches.count == 0) return 4;

    int result = submitEntries(matches, NO);
    if (result == EXIT_SUCCESS) {
        printf("%lu\n", (unsigned long)matches.count);
    }
    return result;
}

static NSString *argumentString(const char *argument) {
    return [NSString stringWithUTF8String:argument];
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        if (argc < 2 || !loadKeyboardServices()) return EXIT_FAILURE;

        NSString *action = argumentString(argv[1]);
        if ([action isEqualToString:@"add"] && argc == 4) {
            return addEntry(argumentString(argv[2]), argumentString(argv[3]));
        }
        if ([action isEqualToString:@"list"] && (argc == 2 || argc == 3)) {
            return listEntries(argc == 3 ? argumentString(argv[2]) : nil);
        }
        if ([action isEqualToString:@"remove"] && (argc == 3 || argc == 4)) {
            return removeEntries(argumentString(argv[2]),
                                 argc == 4 ? argumentString(argv[3]) : nil);
        }

        fprintf(stderr,
                "使い方: dict-helper add <よみ> <変換語> | "
                "list [検索語] | remove <よみ> [変換語]\n");
        return 2;
    }
}
