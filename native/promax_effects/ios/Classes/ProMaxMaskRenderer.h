#import <CoreVideo/CoreVideo.h>
#import <Foundation/Foundation.h>
#import <ImageIO/ImageIO.h>
#import "ProMaxMaskCatalog.h"
#include "MaskPose.h"

NS_ASSUME_NONNULL_BEGIN

@interface ProMaxMaskRenderer : NSObject
- (nullable CVPixelBufferRef)renderFrame:(CVPixelBufferRef)input
                             orientation:(CGImagePropertyOrientation)orientation
                                   style:(ProMaxMaskStyle *)style
                                   poses:(const ProMaxFacePose *)poses
                                   count:(std::size_t)count CF_RETURNS_RETAINED;
@end

NS_ASSUME_NONNULL_END
