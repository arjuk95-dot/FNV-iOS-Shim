#pragma once
#import <Metal/Metal.h>
#import <QuartzCore/CAMetalLayer.h>
CAMetalLayer *fnv_surface(id<MTLDevice> device, CGSize size);
void fnv_resize_surface(CGSize size);
void fnv_wait_active(void);
