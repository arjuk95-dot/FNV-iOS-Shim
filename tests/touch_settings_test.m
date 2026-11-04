#import "FNVTouchSettings.h"
#include <stdio.h>
static unsigned failed;
static void check(const char *name,BOOL value){printf("%s: %s\n",value?"PASS":"FAIL",name);failed+=!value;}
int main(void){@autoreleasepool{
    NSString *suite=[@"fnv-touch-test-" stringByAppendingString:NSUUID.UUID.UUIDString];
    NSUserDefaults *store=[[NSUserDefaults alloc] initWithSuiteName:suite];
    [store removePersistentDomainForName:suite];
    NSMutableDictionary *settings=FNVTouchLoadSettings(store);
    check("new installation has six gameplay controls and dedicated Jump",[settings[@"gameButtons"] count]==6&&[settings[@"gameButtons"][3][@"visible"] boolValue]);
    check("gyro is off and gun Aim toggles by default",![settings[@"gyro"] boolValue]&&![settings[@"aimHold"] boolValue]);
    check("Pip-Boy has its own editable layout",[settings[@"pipButtons"] count]==10&&settings[@"pipButtons"]!=settings[@"gameButtons"]);
    settings[@"gameButtons"][0][@"x"]=@.46;
    settings[@"gameButtons"][0][@"opacity"]=@.35;
    settings[@"pipButtons"][0][@"size"]=@72;
    settings[@"gyro"]=@YES;settings[@"gyroY"]=@1.7;
    settings[@"radialOrder"]=[@[@6,@1,@2,@3,@4,@5,@0] mutableCopy];
    [store setObject:settings forKey:FNVTouchSettingsKey];
    NSUserDefaults *cold=[[NSUserDefaults alloc] initWithSuiteName:suite];
    NSMutableDictionary *loaded=FNVTouchLoadSettings(cold);
    check("cold reload preserves button position and opacity",fabs([loaded[@"gameButtons"][0][@"x"] doubleValue]-.46)<.0001&&fabs([loaded[@"gameButtons"][0][@"opacity"] doubleValue]-.35)<.0001);
    check("Pip-Boy edits do not replace the gameplay layout",[loaded[@"pipButtons"][0][@"size"] intValue]==72&&[loaded[@"gameButtons"][0][@"size"] intValue]==78);
    check("gyro preference and sensitivities survive reload",[loaded[@"gyro"] boolValue]&&fabs([loaded[@"gyroY"] doubleValue]-1.7)<.0001);
    check("custom radial order survives reload",[loaded[@"radialOrder"][0] intValue]==6&&[loaded[@"radialOrder"][6] intValue]==0);
    NSMutableDictionary *before=FNVCopySettings(loaded),*edited=FNVCopySettings(loaded);
    edited[@"gameButtons"][0][@"x"]=@.2;
    check("editor snapshot remains independent of staged edits",[before isEqual:loaded]&&![before isEqual:edited]);
    [store removeObjectForKey:FNVTouchSettingsKey];
    NSMutableDictionary *legacy=FNVDefaultSettings();legacy[@"version"]=@2;
    for(NSMutableDictionary *button in legacy[@"gameButtons"])[button removeObjectsForKeys:@[@"visible",@"label",@"opacity"]];
    legacy[@"gameButtons"][0][@"x"]=@.31;
    [store setObject:legacy forKey:@"FNVTouchControls.v2"];
    loaded=FNVTouchLoadSettings(store);
    check("migration retains old positions and supplies visible control defaults",fabs([loaded[@"gameButtons"][0][@"x"] doubleValue]-.31)<.0001&&[loaded[@"gameButtons"][0][@"visible"] boolValue]&&[loaded[@"gameButtons"][0][@"label"] boolValue]&&[loaded[@"gameButtons"][0][@"opacity"] doubleValue]==1);
    check("migration does not mutate the stored older layout",store!=nil&&[[store objectForKey:@"FNVTouchControls.v2"] isEqual:legacy]);
    NSMutableDictionary *invalid=FNVDefaultSettings();
    invalid[@"radialOrder"]=@[@0,@0,@0,@0,@0,@0,@0];invalid[@"gameButtons"]=@[@"bad"];
    invalid[@"move"]=[@{@"x":@1,@"y":@1,@"w":@.7,@"h":@.8} mutableCopy];
    [store setObject:invalid forKey:FNVTouchSettingsKey];loaded=FNVTouchLoadSettings(store);
    check("malformed layouts recover defaults",[loaded[@"gameButtons"] count]==6&&[[NSSet setWithArray:loaded[@"radialOrder"]] count]==7);
    NSDictionary *region=loaded[@"move"];
    check("loaded activation regions fit the safe coordinate space",[region[@"x"] doubleValue]+[region[@"w"] doubleValue]<=1.00001&&[region[@"y"] doubleValue]+[region[@"h"] doubleValue]<=1.00001);
    [store removePersistentDomainForName:suite];
    return failed?1:0;
}}
