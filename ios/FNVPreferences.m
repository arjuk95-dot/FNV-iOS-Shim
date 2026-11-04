#import "FNVPreferences.h"
#include "FNVDisplay.h"

NSString *fnv_display_preferences(NSString *text) {
    NSMutableArray<NSString *> *lines = [[text componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet] mutableCopy];
    NSDictionary *settings = @{
        @"display": @{
            @"isize w": @[@"iSize W", @(fnv_display_width())],
            @"isize h": @[@"iSize H", @(fnv_display_height())],
            @"bfull screen": @[@"bFull Screen", @1],
            @"sd3ddevice": @[@"sD3DDevice", [NSString stringWithUTF8String:fnv_display_adapter_description()]]
        },
        @"controls": @{@"buse joystick": @[@"bUse Joystick", @1]}
    };
    for (NSString *section in settings) {
        NSDictionary *keys = settings[section];
        NSMutableSet *pending = [NSMutableSet setWithArray:keys.allKeys];
        BOOL inside = NO;
        NSInteger insert = -1;
        for (NSUInteger i = 0; i < lines.count; i++) {
            NSString *line = [lines[i] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
            if ([line hasPrefix:@"["] && [line hasSuffix:@"]"]) {
                if (inside && insert < 0) insert = i;
                inside = [[[line substringWithRange:NSMakeRange(1, line.length - 2)] lowercaseString] isEqualToString:section];
            } else if (inside) {
                NSRange equal = [line rangeOfString:@"="];
                if (equal.location != NSNotFound) {
                    NSString *key = [[[line substringToIndex:equal.location] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet] lowercaseString];
                    NSArray *value = keys[key];
                    if (value) {
                        lines[i] = [NSString stringWithFormat:@"%@=%@", value[0], value[1]];
                        [pending removeObject:key];
                    }
                }
            }
        }
        if (insert < 0) {
            insert = lines.count;
            if (!inside) {
                [lines addObject:[NSString stringWithFormat:@"[%@]", section]];
                insert++;
            }
        }
        for (NSString *key in pending) {
            NSArray *value = keys[key];
            [lines insertObject:[NSString stringWithFormat:@"%@=%@", value[0], value[1]] atIndex:insert++];
        }
    }
    return [lines componentsJoinedByString:@"\n"];
}
