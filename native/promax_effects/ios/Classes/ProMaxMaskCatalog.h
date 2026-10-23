#import <CoreImage/CoreImage.h>
#import <Foundation/Foundation.h>
#include "MaskPose.h"

NS_ASSUME_NONNULL_BEGIN

@interface ProMaxMaskStyle : NSObject
@property(nonatomic, readonly, copy) NSString *identifier;
@property(nonatomic, readonly) ProMaxMaskSpec spec;
@property(nonatomic, readonly) BOOL pixelate;
@property(nonatomic, readonly, nullable) CIImage *image;
@end

@interface ProMaxMaskCatalog : NSObject
- (nullable ProMaxMaskStyle *)styleWithIdentifier:(NSString *)identifier;
@end

NS_ASSUME_NONNULL_END
