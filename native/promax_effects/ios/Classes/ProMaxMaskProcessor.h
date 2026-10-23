#import <Foundation/Foundation.h>
#import <flutter_webrtc/VideoProcessingAdapter.h>
#import "ProMaxMaskCatalog.h"

NS_ASSUME_NONNULL_BEGIN

@interface ProMaxMaskProcessor : NSObject <ExternalVideoProcessingDelegate>
- (void)setStyle:(nullable ProMaxMaskStyle *)style;
- (void)reset;
@end

NS_ASSUME_NONNULL_END
