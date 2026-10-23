#import "ProMaxMaskProcessor.h"
#import "ProMaxFaceTracker.h"
#import "ProMaxMaskRenderer.h"
#include <mutex>

static CGImagePropertyOrientation ProMaxOrientation(RTCVideoRotation rotation) {
  switch (rotation) {
    case RTCVideoRotation_90:
      return kCGImagePropertyOrientationRight;
    case RTCVideoRotation_180:
      return kCGImagePropertyOrientationDown;
    case RTCVideoRotation_270:
      return kCGImagePropertyOrientationLeft;
    default:
      return kCGImagePropertyOrientationUp;
  }
}

@implementation ProMaxMaskProcessor {
  std::mutex _lock;
  ProMaxMaskStyle *_style;
  ProMaxFaceTracker *_tracker;
  ProMaxMaskRenderer *_renderer;
}

- (instancetype)init {
  if ((self = [super init])) {
    _tracker = [[ProMaxFaceTracker alloc] init];
    _renderer = [[ProMaxMaskRenderer alloc] init];
  }
  return self;
}

- (void)setStyle:(ProMaxMaskStyle *)style {
  std::lock_guard<std::mutex> guard(_lock);
  _style = style;
}

- (ProMaxMaskStyle *)currentStyle {
  std::lock_guard<std::mutex> guard(_lock);
  return _style;
}

- (void)reset {
  [self setStyle:nil];
  [_tracker reset];
}

- (RTCVideoFrame *)onFrame:(RTCVideoFrame *)frame {
  ProMaxMaskStyle *style = [self currentStyle];
  if (!style || ![frame.buffer isKindOfClass:[RTCCVPixelBuffer class]]) return frame;
  @autoreleasepool {
    CVPixelBufferRef input = ((RTCCVPixelBuffer *)frame.buffer).pixelBuffer;
    const CGImagePropertyOrientation orientation = ProMaxOrientation(frame.rotation);
    const CGFloat width = static_cast<CGFloat>(CVPixelBufferGetWidth(input));
    const CGFloat height = static_cast<CGFloat>(CVPixelBufferGetHeight(input));
    const bool sideways =
        orientation == kCGImagePropertyOrientationRight || orientation == kCGImagePropertyOrientationLeft;
    const CGSize upright = sideways ? CGSizeMake(height, width) : CGSizeMake(width, height);
    const double time = static_cast<double>(frame.timeStampNs) * 1e-9;
    [_tracker submitPixelBuffer:input orientation:orientation uprightSize:upright time:time];
    ProMaxFacePose poses[ProMaxMaskTracker::kCapacity];
    const std::size_t count = [_tracker posesAtTime:time into:poses capacity:ProMaxMaskTracker::kCapacity];
    if (count == 0 && !style.pixelate) return frame;
    CVPixelBufferRef output = [_renderer renderFrame:input
                                         orientation:orientation
                                               style:style
                                               poses:poses
                                               count:count];
    if (!output) return frame;
    RTCCVPixelBuffer *buffer = [[RTCCVPixelBuffer alloc] initWithPixelBuffer:output];
    CVPixelBufferRelease(output);
    return [[RTCVideoFrame alloc] initWithBuffer:buffer rotation:frame.rotation timeStampNs:frame.timeStampNs];
  }
}

@end
