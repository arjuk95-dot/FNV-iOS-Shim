#pragma once
#import <Foundation/Foundation.h>
#include "FNVTouchPolicy.h"

static NSString *const FNVTouchSettingsKey=@"FNVTouchControls.v3";
static double FNVNumber(NSDictionary *dict,NSString *key,double fallback,double low,double high){
    id value=dict[key];return [value respondsToSelector:@selector(doubleValue)]?FNVTouchClamp([value doubleValue],low,high):fallback;
}
static NSMutableDictionary *FNVCopySettings(NSDictionary *source){
    NSData *data=[NSPropertyListSerialization dataWithPropertyList:source format:NSPropertyListBinaryFormat_v1_0 options:0 error:NULL];
    return data?[NSPropertyListSerialization propertyListWithData:data options:NSPropertyListMutableContainersAndLeaves format:NULL error:NULL]:nil;
}
static NSMutableDictionary *FNVDefaultSettings(void){
    double game[][3]={{.91,.57,78},{.78,.57,58},{.78,.79,54},{.91,.80,60},{.94,.34,48},{.94,.12,44}};
    double menu[][3]={{.92,.58,58},{.80,.58,58},{.92,.80,50},{.92,.12,44},{.80,.80,46},{.68,.80,46},{.12,.49,44},{.12,.78,44},{.055,.64,44},{.19,.64,44}};
    NSMutableArray *gameButtons=[NSMutableArray new],*pipButtons=[NSMutableArray new];
    for(unsigned i=0;i<6;i++)[gameButtons addObject:[@{@"x":@(game[i][0]),@"y":@(game[i][1]),@"size":@(game[i][2]),@"opacity":@1,@"visible":@YES,@"label":@YES} mutableCopy]];
    for(unsigned i=0;i<10;i++)[pipButtons addObject:[@{@"x":@(menu[i][0]),@"y":@(menu[i][1]),@"size":@(menu[i][2]),@"opacity":@1,@"visible":@YES,@"label":@YES} mutableCopy]];
    return [@{@"version":@3,@"gameButtons":gameButtons,@"pipButtons":pipButtons,
        @"move":[@{@"x":@.03,@"y":@.18,@"w":@.39,@"h":@.70} mutableCopy],
        @"look":[@{@"x":@.43,@"y":@.15,@"w":@.54,@"h":@.75} mutableCopy],
        @"pipMove":[@{@"x":@.03,@"y":@.18,@"w":@.30,@"h":@.70} mutableCopy],
        @"pipLook":[@{@"x":@.38,@"y":@.15,@"w":@.55,@"h":@.75} mutableCopy],
        @"opacity":@.72,@"radius":@54,@"moveDeadzone":@.10,@"moveResponse":@1,
        @"lookX":@.20,@"lookY":@.20,@"ads":@.62,@"fireGain":@1,@"invertX":@NO,@"invertY":@NO,
        @"smoothing":@.025,@"stickDeadzone":@.24,@"stickResponse":@1.6,@"maxTurnRate":@360,
        @"aimHold":@NO,@"gyro":@NO,@"gyroAiming":@YES,@"gyroX":@1,@"gyroY":@1,@"gyroInvertX":@NO,@"gyroInvertY":@NO,
        @"radialX":@.72,@"radialY":@.43,@"radialSize":@250,@"hold":@.38,
        @"radialOrder":[@[@0,@1,@2,@3,@4,@5,@6] mutableCopy]} mutableCopy];
}

// Shared production loader: isolated Foundation tests exercise a real cold reload.
static NSMutableDictionary *FNVTouchLoadSettings(NSUserDefaults *defaults){
    NSMutableDictionary *settings=FNVDefaultSettings();
    id saved=[defaults objectForKey:FNVTouchSettingsKey]?:[defaults objectForKey:@"FNVTouchControls.v2"]?:[defaults objectForKey:@"FNVTouchControls"];
    if([saved isKindOfClass:NSDictionary.class]){
        NSMutableDictionary *copy=FNVCopySettings(saved);
        if([copy[@"version"] integerValue]<=3){
            for(NSString *key in [settings.allKeys copy]){id value=copy[key],expected=settings[key];BOOL compatible=([expected isKindOfClass:NSNumber.class]&&[value isKindOfClass:NSNumber.class])||([expected isKindOfClass:NSArray.class]&&[value isKindOfClass:NSArray.class])||([expected isKindOfClass:NSDictionary.class]&&[value isKindOfClass:NSDictionary.class]);if(compatible)settings[key]=value;}
            settings[@"version"]=@3;
        }
    }
    for(NSString *key in @[@"gameButtons",@"pipButtons"]){
        NSMutableArray *buttonDefaults=FNVDefaultSettings()[key],*loaded=settings[key];
        if(![loaded isKindOfClass:NSMutableArray.class]||loaded.count!=buttonDefaults.count)settings[key]=buttonDefaults;
        else for(NSUInteger i=0;i<loaded.count;i++){
            if(![loaded[i] isKindOfClass:NSMutableDictionary.class])loaded[i]=buttonDefaults[i];
            else for(NSString *field in buttonDefaults[i])if(![loaded[i][field] isKindOfClass:NSNumber.class])loaded[i][field]=buttonDefaults[i][field];
        }
    }
    NSArray *order=settings[@"radialOrder"];NSMutableSet *unique=[NSMutableSet new];BOOL valid=order.count==7;
    for(id item in order){if(![item isKindOfClass:NSNumber.class]||[item integerValue]<0||[item integerValue]>6){valid=NO;break;}[unique addObject:item];}
    if(!valid||unique.count!=7)settings[@"radialOrder"]=[@[@0,@1,@2,@3,@4,@5,@6] mutableCopy];
    for(NSString *key in @[@"move",@"look",@"pipMove",@"pipLook"]){
        NSMutableDictionary *region=settings[key];
        FNVTouchRect r=FNVTouchRegion((FNVTouchRect){0,0,1,1},FNVNumber(region,@"x",0,0,1),FNVNumber(region,@"y",0,0,1),FNVNumber(region,@"w",.4,.08,1),FNVNumber(region,@"h",.7,.08,1));
        region[@"x"]=@(r.x);region[@"y"]=@(r.y);region[@"w"]=@(r.w);region[@"h"]=@(r.h);
    }
    return settings;
}
