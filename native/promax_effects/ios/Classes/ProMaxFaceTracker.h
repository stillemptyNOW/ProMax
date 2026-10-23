#import <CoreVideo/CoreVideo.h>
#import <Foundation/Foundation.h>
#import <ImageIO/ImageIO.h>
#include "MaskPose.h"

NS_ASSUME_NONNULL_BEGIN

@interface ProMaxFaceTracker : NSObject
- (void)submitPixelBuffer:(CVPixelBufferRef)buffer
              orientation:(CGImagePropertyOrientation)orientation
              uprightSize:(CGSize)size
                     time:(double)time;
- (std::size_t)posesAtTime:(double)time into:(ProMaxFacePose *)poses capacity:(std::size_t)capacity;
- (void)reset;
@end

NS_ASSUME_NONNULL_END
