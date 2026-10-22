// LiteDisplay
// Copyright (c) 2026 Renato Asterio
// Licensed under the PolyForm Noncommercial License 1.0.0
//
// Private CoreGraphics virtual display classes (the mechanism behind BetterDummy / BetterDisplay virtual screens).
// Declarations match what the ObjC runtime reports on macOS 14–27. Every class is weakly imported so the app still
// launches on a macOS that drops them; VirtualDisplayService checks NSClassFromString before use.

#import <CoreGraphics/CoreGraphics.h>
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

__attribute__((weak_import))
@interface CGVirtualDisplayDescriptor : NSObject
@property (nonatomic, copy, nullable) NSString *name;
@property (nonatomic) uint32_t vendorID;
@property (nonatomic) uint32_t productID;
@property (nonatomic) uint32_t serialNum;
@property (nonatomic) uint32_t maxPixelsWide;
@property (nonatomic) uint32_t maxPixelsHigh;
@property (nonatomic) CGSize sizeInMillimeters;
@property (nonatomic) CGPoint redPrimary;
@property (nonatomic) CGPoint greenPrimary;
@property (nonatomic) CGPoint bluePrimary;
@property (nonatomic) CGPoint whitePoint;
@property (nonatomic, strong, nullable) dispatch_queue_t queue;
@property (nonatomic, copy, nullable) void (^terminationHandler)(id, id);
@end

__attribute__((weak_import))
@interface CGVirtualDisplayMode : NSObject
@property (nonatomic, readonly) uint32_t width;
@property (nonatomic, readonly) uint32_t height;
@property (nonatomic, readonly) double refreshRate;
- (instancetype)initWithWidth:(uint32_t)width height:(uint32_t)height refreshRate:(double)refreshRate;
@end

__attribute__((weak_import))
@interface CGVirtualDisplaySettings : NSObject
@property (nonatomic) uint32_t hiDPI;
@property (nonatomic, copy, nullable) NSArray<CGVirtualDisplayMode *> *modes;
@property (nonatomic) uint32_t rotation;
@end

__attribute__((weak_import))
@interface CGVirtualDisplay : NSObject
@property (nonatomic, readonly) CGDirectDisplayID displayID;
@property (nonatomic, readonly) uint32_t hiDPI;
@property (nonatomic, readonly, nullable) NSArray<CGVirtualDisplayMode *> *modes;
- (nullable instancetype)initWithDescriptor:(CGVirtualDisplayDescriptor *)descriptor;
- (BOOL)applySettings:(CGVirtualDisplaySettings *)settings;
@end

NS_ASSUME_NONNULL_END
