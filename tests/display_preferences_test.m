#import <Foundation/Foundation.h>
#import "FNVPreferences.h"
#include "FNVDisplay.h"
#include <stdio.h>
#include <string.h>

const char *display_preferences_guest_init(const char *root);
const char *display_preferences_guest_profile(const char *section, const char *key);

static unsigned failures;
static void check(BOOL value, NSString *caseName, NSString *condition) {
    if (!value) {
        fprintf(stderr, "FAIL: %s: %s\n", caseName.UTF8String, condition.UTF8String);
        ++failures;
    }
}
static NSString *profile(NSString *section, NSString *key) {
    return [NSString stringWithUTF8String:display_preferences_guest_profile(section.UTF8String, key.UTF8String)];
}

int main(int argc, const char **argv) {
    @autoreleasepool {
        if (argc != 3) return 2;
        BOOL reference = !strcmp(argv[2], "reference");
        NSString *root = [NSString stringWithUTF8String:argv[1]];
        NSString *folder = [root stringByAppendingPathComponent:@"UserDocuments/My Games/FalloutNV"];
        NSError *error = nil;
        if (![NSFileManager.defaultManager createDirectoryAtPath:folder withIntermediateDirectories:YES attributes:nil error:&error]) {
            fprintf(stderr, "Could not create fixture: %s\n", error.localizedDescription.UTF8String);
            return 2;
        }
        NSString *path = [folder stringByAppendingPathComponent:@"FalloutPrefs.ini"];
        NSString *adapter = [NSString stringWithUTF8String:display_preferences_guest_init(root.fileSystemRepresentation)];
        fnv_display_configure(1290, 2796);
        check(fnv_display_width() == 1440 && fnv_display_height() == 664, @"fixture", @"phone aspect is 1440x664");
        check([adapter isEqualToString:[NSString stringWithUTF8String:fnv_display_adapter_description()]], @"fixture", @"COM identifier agrees with shared backend identity");

        NSString *unrelated = @"; preserve this comment\n[Pathfinding]\nbBackgroundNavmeshUpdate=0\n[Audio]\nbEnableAudio=1\nfDefaultMasterVolume=0.73\n[Custom]\nsMarker=keep this exact value\n";
        NSString *controls = @"[Controls]\nbUse Joystick=0\nbInvertYValues=1\nfMouseSensitivity=0.0025\n";
        NSString *display = @"[dIsPlAy]\niSize W=800\niSize H=600\nbFull Screen=0\niMultiSample=2\n";
        NSArray<NSDictionary *> *cases = @[
            @{@"name": @"empty", @"text": @"", @"historicalMismatch": @YES},
            @{@"name": @"missing", @"text": [display stringByAppendingString:[controls stringByAppendingString:unrelated]], @"historicalMismatch": @YES},
            @{@"name": @"stale", @"text": [[display stringByAppendingString:@"  sD3DDevice = Previous graphics adapter  \n"] stringByAppendingString:[controls stringByAppendingString:unrelated]], @"historicalMismatch": @YES},
            @{@"name": @"quoted-stale", @"text": [[display stringByAppendingString:@"sD3DDevice=\"Previous graphics adapter\"\n"] stringByAppendingString:[controls stringByAppendingString:unrelated]], @"historicalMismatch": @YES},
            @{@"name": @"empty-device", @"text": [[display stringByAppendingString:@"sD3DDevice=\n"] stringByAppendingString:[controls stringByAppendingString:unrelated]], @"historicalMismatch": @YES},
            @{@"name": @"quoted-current", @"text": [[display stringByAppendingFormat:@"sD3DDevice=\"%@\"\n", adapter] stringByAppendingString:[controls stringByAppendingString:unrelated]], @"historicalMismatch": @NO},
            @{@"name": @"current", @"text": [[display stringByAppendingFormat:@"sD3DDevice=%@\n", adapter] stringByAppendingString:[controls stringByAppendingString:unrelated]], @"historicalMismatch": @NO}
        ];
        unsigned expectedMismatches = 0, observedMismatches = 0;
        for (NSDictionary *item in cases) {
            NSString *name = item[@"name"], *input = item[@"text"];
            NSString *output = fnv_display_preferences(input);
            check(output != nil, name, @"initializer returns preferences");
            if (!output) continue;
            check([output isEqualToString:fnv_display_preferences(output)], name, @"initialization is idempotent");
            error = nil;
            BOOL written = [output writeToFile:path atomically:YES encoding:NSISOLatin1StringEncoding error:&error];
            check(written, name, @"initialized file is persisted");
            if (!written) continue;
            NSString *persisted = [NSString stringWithContentsOfFile:path encoding:NSISOLatin1StringEncoding error:&error];
            check([output isEqualToString:persisted], name, @"persisted text matches initializer output");

            // This is the production GetPrivateProfileStringA over the persisted
            // file, compared with the actual COM Description field at +512.
            NSString *selectedAdapter = profile(@"DISPLAY", @"sd3ddevice");
            BOOL mismatch = ![selectedAdapter isEqualToString:adapter];
            BOOL expectedMismatch = reference && [item[@"historicalMismatch"] boolValue];
            expectedMismatches += expectedMismatch;
            observedMismatches += mismatch;
            check(mismatch == expectedMismatch, name, expectedMismatch ? @"historical adapter mismatch is reproduced" : @"persisted adapter matches actual COM identifier");
            if (reference && mismatch) printf("Historical adapter mismatch: %s -> '%s' versus '%s'\n", name.UTF8String, selectedAdapter.UTF8String, adapter.UTF8String);
            if (!reference) check([output containsString:[NSString stringWithFormat:@"sD3DDevice=%@", adapter]], name, @"adapter is stored in canonical unquoted form");

            check([profile(@"display", @"iSize W") isEqualToString:@"1440"], name, @"native landscape width is retained");
            check([profile(@"display", @"iSize H") isEqualToString:@"664"], name, @"native landscape height is retained");
            check([profile(@"display", @"bFull Screen") isEqualToString:@"1"], name, @"fullscreen is enabled");
            check([profile(@"controls", @"bUse Joystick") isEqualToString:@"1"], name, @"controller remains enabled");
            if (input.length) {
                check([output containsString:unrelated], name, @"unrelated sections and comments are preserved");
                check([profile(@"Pathfinding", @"bBackgroundNavmeshUpdate") isEqualToString:@"0"], name, @"working synchronous NavMesh setting is preserved");
                check([profile(@"Audio", @"bEnableAudio") isEqualToString:@"1"], name, @"audio remains enabled");
                check([profile(@"Audio", @"fDefaultMasterVolume") isEqualToString:@"0.73"], name, @"audio volume is unchanged");
                check([profile(@"display", @"iMultiSample") isEqualToString:@"2"], name, @"unowned display preference is unchanged");
                check([profile(@"controls", @"bInvertYValues") isEqualToString:@"1"], name, @"unowned controller preference is unchanged");
                check([profile(@"controls", @"fMouseSensitivity") isEqualToString:@"0.0025"], name, @"mouse sensitivity is unchanged");
            }
            printf("Checked %s: adapter=%s\n", name.UTF8String, selectedAdapter.UTF8String);
        }
        check(observedMismatches == expectedMismatches, @"suite", @"only the declared historical adapter mismatches occur");
        printf("%s: %lu preference scenarios; %u expected historical identity mismatches; %u failures\n", failures ? "FAIL" : "PASS", (unsigned long)cases.count, expectedMismatches, failures);
        return failures ? 1 : 0;
    }
}
