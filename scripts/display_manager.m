// display_manager - Manage Mac display resolution and mirroring
// Compile: clang -framework CoreGraphics -framework Foundation -o display_manager display_manager.m

#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

#pragma mark - Display helpers

typedef struct {
    CGDirectDisplayID displayID;
} DMDisplay;

static int getAllDisplays(DMDisplay *displays, int maxCount) {
    CGDirectDisplayID ids[32];
    uint32_t count = 0;
    if (CGGetOnlineDisplayList(32, ids, &count) != kCGErrorSuccess) return 0;
    int n = (int)(count < maxCount ? count : maxCount);
    for (int i = 0; i < n; i++) {
        displays[i].displayID = ids[i];
    }
    return n;
}

static BOOL isMainDisplay(CGDirectDisplayID displayID) {
    return CGDisplayIsMain(displayID) != 0;
}

static NSString *displayTag(CGDirectDisplayID displayID) {
    if (isMainDisplay(displayID)) return @"main";

    DMDisplay all[32];
    int count = getAllDisplays(all, 32);
    int extIndex = 0;
    for (int i = 0; i < count; i++) {
        if (isMainDisplay(all[i].displayID)) continue;
        if (all[i].displayID == displayID) {
            return [NSString stringWithFormat:@"ext%d", extIndex];
        }
        extIndex++;
    }
    return @"unknown";
}

static BOOL resolveDisplayTag(NSString *tag, CGDirectDisplayID *outID) {
    if ([tag isEqualToString:@"main"]) {
        *outID = CGMainDisplayID();
        return YES;
    }

    if ([tag hasPrefix:@"ext"]) {
        int num = [[tag substringFromIndex:3] intValue];
        DMDisplay all[32];
        int count = getAllDisplays(all, 32);

        // Collect externals
        CGDirectDisplayID externals[32];
        int extCount = 0;
        for (int i = 0; i < count; i++) {
            if (!isMainDisplay(all[i].displayID)) {
                externals[extCount++] = all[i].displayID;
            }
        }

        if (num < extCount) {
            *outID = externals[num];
            return YES;
        }
        fprintf(stderr, "Error: No display \"%s\" (only %d external display(s))\n",
                [tag UTF8String], extCount);
        return NO;
    }

    fprintf(stderr, "Error: Invalid display tag: \"%s\"\n", [tag UTF8String]);
    return NO;
}

#pragma mark - Display mode helpers

static BOOL isModeDefault(CGDisplayModeRef mode) {
    uint32_t flags = CGDisplayModeGetIOFlags(mode);
    return (flags & 0x4) != 0;
}

static BOOL isModeHiDPI(CGDisplayModeRef mode) {
    size_t w = CGDisplayModeGetWidth(mode);
    size_t h = CGDisplayModeGetHeight(mode);
    size_t pw = CGDisplayModeGetPixelWidth(mode);
    size_t ph = CGDisplayModeGetPixelHeight(mode);
    return (pw != w && ph != h);
}

static NSArray *getAllModes(CGDirectDisplayID displayID) {
    NSDictionary *options = @{(__bridge NSString *)kCGDisplayShowDuplicateLowResolutionModes: @YES};
    CFArrayRef modeList = CGDisplayCopyAllDisplayModes(displayID, (__bridge CFDictionaryRef)options);
    if (!modeList) return @[];

    NSArray *modes = (NSArray *)modeList;
    NSArray *result = [modes copy];
    CFRelease(modeList);
    return result;
}

static CGDisplayModeRef findDefaultMode(CGDirectDisplayID displayID) {
    NSArray *modes = getAllModes(displayID);
    for (id modeObj in modes) {
        CGDisplayModeRef mode = (__bridge CGDisplayModeRef)modeObj;
        if (isModeDefault(mode)) return mode;
    }
    return NULL;
}

static CGDisplayModeRef findHighestMode(CGDirectDisplayID displayID) {
    NSArray *modes = getAllModes(displayID);
    CGDisplayModeRef highest = NULL;
    size_t highestPixels = 0;

    for (id modeObj in modes) {
        CGDisplayModeRef mode = (__bridge CGDisplayModeRef)modeObj;
        size_t pixels = CGDisplayModeGetWidth(mode) * CGDisplayModeGetHeight(mode);
        if (pixels > highestPixels) {
            highestPixels = pixels;
            highest = mode;
        }
    }
    return highest;
}

static CGDisplayModeRef findClosestMode(CGDirectDisplayID displayID, size_t width, size_t height) {
    NSArray *modes = getAllModes(displayID);

    // First pass: exact match
    for (id modeObj in modes) {
        CGDisplayModeRef mode = (__bridge CGDisplayModeRef)modeObj;
        if (CGDisplayModeGetWidth(mode) == width && CGDisplayModeGetHeight(mode) == height) {
            return mode;
        }
    }
    return NULL;
}

static BOOL setDisplayMode(CGDirectDisplayID displayID, CGDisplayModeRef mode) {
    CGDisplayConfigRef configRef;
    if (CGBeginDisplayConfiguration(&configRef) != kCGErrorSuccess) {
        fprintf(stderr, "Error: Failed to begin display configuration for \"%s\"\n",
                [displayTag(displayID) UTF8String]);
        return NO;
    }
    if (CGConfigureDisplayWithDisplayMode(configRef, displayID, mode, NULL) != kCGErrorSuccess) {
        CGCancelDisplayConfiguration(configRef);
        fprintf(stderr, "Error: Failed to set \"%s\" to %zux%zu\n",
                [displayTag(displayID) UTF8String],
                CGDisplayModeGetWidth(mode), CGDisplayModeGetHeight(mode));
        return NO;
    }
    CGCompleteDisplayConfiguration(configRef, kCGConfigurePermanently);
    return YES;
}

#pragma mark - Commands

static int handleRes(NSArray<NSString *> *args) {
    if (args.count == 0) {
        fprintf(stderr, "Usage: display_manager res <highest|default|width height> [scope...]\n");
        return 1;
    }

    NSString *first = args[0];

    if ([first isEqualToString:@"highest"] || [first isEqualToString:@"default"]) {
        // Collect scope displays
        NSMutableArray<NSNumber *> *displays = [NSMutableArray array];
        if (args.count == 1) {
            // Default scope: main
            [displays addObject:@(CGMainDisplayID())];
        } else {
            for (NSUInteger i = 1; i < args.count; i++) {
                if ([args[i] isEqualToString:@"all"]) {
                    DMDisplay all[32];
                    int count = getAllDisplays(all, 32);
                    [displays removeAllObjects];
                    for (int j = 0; j < count; j++) {
                        [displays addObject:@(all[j].displayID)];
                    }
                    break;
                }
                CGDirectDisplayID did;
                if (!resolveDisplayTag(args[i], &did)) return 1;
                [displays addObject:@(did)];
            }
        }

        for (NSNumber *d in displays) {
            CGDirectDisplayID did = [d unsignedIntValue];
            CGDisplayModeRef mode;
            if ([first isEqualToString:@"highest"]) {
                mode = findHighestMode(did);
                if (!mode) {
                    fprintf(stderr, "Error: No available mode for \"%s\"\n",
                            [displayTag(did) UTF8String]);
                    return 1;
                }
            } else {
                mode = findDefaultMode(did);
                if (!mode) {
                    fprintf(stderr, "Error: No default mode for \"%s\"\n",
                            [displayTag(did) UTF8String]);
                    return 1;
                }
            }
            if (!setDisplayMode(did, mode)) return 1;
        }
        return 0;
    }

    // res <width> <height> [scope...]
    if (args.count < 2) {
        fprintf(stderr, "Usage: display_manager res <width> <height> [scope...]\n");
        return 1;
    }

    size_t width = (size_t)[args[0] integerValue];
    size_t height = (size_t)[args[1] integerValue];
    if (width == 0 || height == 0) {
        fprintf(stderr, "Error: Invalid resolution %sx%s\n",
                [args[0] UTF8String], [args[1] UTF8String]);
        return 1;
    }

    NSMutableArray<NSNumber *> *displays = [NSMutableArray array];
    if (args.count == 2) {
        [displays addObject:@(CGMainDisplayID())];
    } else {
        for (NSUInteger i = 2; i < args.count; i++) {
            if ([args[i] isEqualToString:@"all"]) {
                DMDisplay all[32];
                int count = getAllDisplays(all, 32);
                [displays removeAllObjects];
                for (int j = 0; j < count; j++) {
                    [displays addObject:@(all[j].displayID)];
                }
                break;
            }
            CGDirectDisplayID did;
            if (!resolveDisplayTag(args[i], &did)) return 1;
            [displays addObject:@(did)];
        }
    }

    for (NSNumber *d in displays) {
        CGDirectDisplayID did = [d unsignedIntValue];
        CGDisplayModeRef mode = findClosestMode(did, width, height);
        if (!mode) {
            fprintf(stderr, "Error: Display \"%s\" cannot be set to %zux%zu\n",
                    [displayTag(did) UTF8String], width, height);
            return 1;
        }
        if (!setDisplayMode(did, mode)) return 1;
    }
    return 0;
}

static int handleMirror(NSArray<NSString *> *args) {
    if (args.count == 0) {
        fprintf(stderr, "Usage: display_manager mirror <enable|disable> ...\n");
        return 1;
    }

    NSString *subcommand = args[0];

    if ([subcommand isEqualToString:@"enable"]) {
        if (args.count < 3) {
            fprintf(stderr, "Usage: display_manager mirror enable <source> <target...>\n");
            return 1;
        }

        CGDirectDisplayID sourceID;
        if (!resolveDisplayTag(args[1], &sourceID)) return 1;

        for (NSUInteger i = 2; i < args.count; i++) {
            if ([args[i] isEqualToString:@"all"]) {
                DMDisplay all[32];
                int count = getAllDisplays(all, 32);
                for (int j = 0; j < count; j++) {
                    if (all[j].displayID == sourceID) continue;
                    CGDisplayConfigRef configRef;
                    if (CGBeginDisplayConfiguration(&configRef) != kCGErrorSuccess) {
                        fprintf(stderr, "Error: Failed to configure mirroring\n");
                        return 1;
                    }
                    CGConfigureDisplayMirrorOfDisplay(configRef, all[j].displayID, sourceID);
                    CGCompleteDisplayConfiguration(configRef, kCGConfigurePermanently);
                }
                return 0;
            }

            CGDirectDisplayID targetID;
            if (!resolveDisplayTag(args[i], &targetID)) return 1;

            CGDisplayConfigRef configRef;
            if (CGBeginDisplayConfiguration(&configRef) != kCGErrorSuccess) {
                fprintf(stderr, "Error: Failed to configure mirroring\n");
                return 1;
            }
            CGConfigureDisplayMirrorOfDisplay(configRef, targetID, sourceID);
            CGCompleteDisplayConfiguration(configRef, kCGConfigurePermanently);
        }
        return 0;
    }

    if ([subcommand isEqualToString:@"disable"]) {
        NSMutableArray<NSNumber *> *displays = [NSMutableArray array];

        if (args.count == 1) {
            // Default: all
            DMDisplay all[32];
            int count = getAllDisplays(all, 32);
            for (int i = 0; i < count; i++) {
                [displays addObject:@(all[i].displayID)];
            }
        } else {
            for (NSUInteger i = 1; i < args.count; i++) {
                if ([args[i] isEqualToString:@"all"]) {
                    DMDisplay all[32];
                    int count = getAllDisplays(all, 32);
                    [displays removeAllObjects];
                    for (int j = 0; j < count; j++) {
                        [displays addObject:@(all[j].displayID)];
                    }
                    break;
                }
                CGDirectDisplayID did;
                if (!resolveDisplayTag(args[i], &did)) return 1;
                [displays addObject:@(did)];
            }
        }

        for (NSNumber *d in displays) {
            CGDirectDisplayID did = [d unsignedIntValue];
            if (CGDisplayMirrorsDisplay(did) != kCGNullDirectDisplay) {
                CGDisplayConfigRef configRef;
                if (CGBeginDisplayConfiguration(&configRef) != kCGErrorSuccess) {
                    fprintf(stderr, "Error: Failed to configure mirroring\n");
                    return 1;
                }
                CGConfigureDisplayMirrorOfDisplay(configRef, did, kCGNullDirectDisplay);
                CGCompleteDisplayConfiguration(configRef, kCGConfigurePermanently);
            }
        }
        return 0;
    }

    fprintf(stderr, "Error: \"%s\" is not a valid mirror subcommand\n", [subcommand UTF8String]);
    return 1;
}

#pragma mark - Main

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        NSMutableArray<NSString *> *args = [NSMutableArray array];
        for (int i = 1; i < argc; i++) {
            [args addObject:[NSString stringWithUTF8String:argv[i]]];
        }

        if (args.count == 0) {
            fprintf(stderr, "Usage: display_manager <res|mirror> ...\n");
            return 1;
        }

        NSString *verb = args[0];
        NSArray<NSString *> *rest = [args subarrayWithRange:NSMakeRange(1, args.count - 1)];

        if ([verb isEqualToString:@"res"]) {
            return handleRes(rest);
        } else if ([verb isEqualToString:@"mirror"]) {
            return handleMirror(rest);
        } else {
            fprintf(stderr, "Error: Unknown command \"%s\". Available: res, mirror\n",
                    [verb UTF8String]);
            return 1;
        }
    }
}
