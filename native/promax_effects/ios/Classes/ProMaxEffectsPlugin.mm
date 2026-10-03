#import "ProMaxEffectsPlugin.h"
#import "VoiceProcessor.h"
#import <flutter_webrtc/FlutterWebRTCPlugin.h>
#import <flutter_webrtc/LocalVideoTrack.h>
#import <flutter_webrtc/AudioManager.h>
#import <CoreImage/CoreImage.h>
#import <UIKit/UIKit.h>
#include <atomic>

@interface ProMaxAudioProcessor : NSObject<ExternalAudioProcessingDelegate>
- (void)setMode:(int)mode;
@end

@implementation ProMaxAudioProcessor {
  std::atomic<int> _mode;
  ProMaxVoiceProcessor _processor;
  double _rate;
}
- (instancetype)init {
  if ((self = [super init])) { _mode.store(0); _rate = 0; }
  return self;
}
- (void)setMode:(int)mode { _mode.store(mode); }
- (void)audioProcessingInitializeWithSampleRate:(size_t)rate channels:(size_t)channels {
  _rate = rate;
  _processor.configure(_mode.load(), _rate);
}
- (void)audioProcessingProcess:(RTCAudioBuffer *)buffer {
  if (buffer.channels > 2 || buffer.frames == 0) return;
  _processor.configure(_mode.load(), _rate > 0 ? _rate : buffer.frames * 100.0);
  float *channels[2] = {nullptr, nullptr};
  for (size_t channel = 0; channel < buffer.channels; ++channel) channels[channel] = [buffer rawBufferForChannel:channel];
  _processor.process(channels, buffer.channels, buffer.frames);
}
- (void)audioProcessingRelease { _rate = 0; }
@end

@interface ProMaxFaceProcessor : NSObject<ExternalVideoProcessingDelegate>
- (void)setMode:(int)mode;
@end

@implementation ProMaxFaceProcessor {
  std::atomic<int> _mode;
  CIContext *_context;
  CIDetector *_detector;
  NSArray<CIFaceFeature *> *_faces;
  CGRect _lastExtent;
  NSUInteger _frame;
}
- (instancetype)init {
  if ((self = [super init])) {
    _mode.store(0);
    _context = [CIContext contextWithOptions:@{kCIContextCacheIntermediates: @NO}];
    _detector = [CIDetector detectorOfType:CIDetectorTypeFace context:_context options:@{CIDetectorAccuracy: CIDetectorAccuracyLow}];
    _faces = @[];
    _lastExtent = CGRectZero;
  }
  return self;
}
- (void)setMode:(int)mode { _mode.store(mode); }
- (RTCVideoFrame *)onFrame:(RTCVideoFrame *)frame {
  const int mode = _mode.load();
  if (mode == 0 || ![frame.buffer isKindOfClass:[RTCCVPixelBuffer class]]) return frame;
  @autoreleasepool {
    CVPixelBufferRef input = ((RTCCVPixelBuffer *)frame.buffer).pixelBuffer;
    CIImage *image = [CIImage imageWithCVPixelBuffer:input];
    int orientation = frame.rotation == RTCVideoRotation_90 ? 6 : frame.rotation == RTCVideoRotation_180 ? 3 : frame.rotation == RTCVideoRotation_270 ? 8 : 1;
    image = [image imageByApplyingOrientation:orientation];
    image = [image imageByApplyingTransform:CGAffineTransformMakeTranslation(-image.extent.origin.x, -image.extent.origin.y)];
    if (_frame++ % 4 == 0 || !CGRectEqualToRect(image.extent, _lastExtent)) {
      _faces = (NSArray<CIFaceFeature *> *)[_detector featuresInImage:image];
      _lastExtent = image.extent;
    }
    if (_faces.count == 0) return frame;
    const size_t width = static_cast<size_t>(image.extent.size.width);
    const size_t height = static_cast<size_t>(image.extent.size.height);
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGContextRef canvas = CGBitmapContextCreate(NULL, width, height, 8, 0, space, kCGImageAlphaPremultipliedLast);
    if (!canvas) { CGColorSpaceRelease(space); return frame; }
    for (CIFaceFeature *face in _faces) {
      if (!face.hasLeftEyePosition || !face.hasRightEyePosition) continue;
      CGPoint left = face.leftEyePosition;
      CGPoint right = face.rightEyePosition;
      if (left.x > right.x) std::swap(left, right);
      CGFloat eyeDistance = hypot(right.x - left.x, right.y - left.y);
      CGPoint center = CGPointMake((left.x + right.x) / 2, (left.y + right.y) / 2);
      CGFloat radius = eyeDistance * 0.36;
      CGContextSaveGState(canvas);
      CGContextTranslateCTM(canvas, center.x, center.y);
      CGContextRotateCTM(canvas, atan2(right.y - left.y, right.x - left.x));
      if (mode == 1) {
        CGContextSetRGBFillColor(canvas, 0.04, 0.06, 0.10, 0.92);
        CGContextSetRGBStrokeColor(canvas, 0.55, 0.80, 1, 1);
        CGContextSetLineWidth(canvas, eyeDistance * 0.045);
        for (int side : {-1, 1}) {
          CGRect lens = CGRectMake(side * eyeDistance * 0.5 - radius, -radius * 0.65, radius * 2, radius * 1.3);
          CGContextAddEllipseInRect(canvas, lens);
          CGContextDrawPath(canvas, kCGPathFillStroke);
        }
        CGContextMoveToPoint(canvas, -eyeDistance * 0.14, 0);
        CGContextAddLineToPoint(canvas, eyeDistance * 0.14, 0);
        CGContextStrokePath(canvas);
      } else if (mode == 2) {
        CGContextSetRGBFillColor(canvas, 0.20, 0.60, 1, 0.72);
        CGContextFillRect(canvas, CGRectMake(-eyeDistance * 0.95, -radius * 0.6, eyeDistance * 1.9, radius * 1.5));
        CGContextSetRGBStrokeColor(canvas, 0.80, 0.95, 1, 1);
        CGContextSetLineWidth(canvas, eyeDistance * 0.025);
        CGContextStrokeRect(canvas, CGRectMake(-eyeDistance * 0.95, -radius * 0.6, eyeDistance * 1.9, radius * 1.5));
      } else {
        CGContextSetRGBFillColor(canvas, 0.95, 0.55, 0.73, 0.94);
        for (int side : {-1, 1}) {
          CGFloat x = side * eyeDistance * 0.78;
          CGContextMoveToPoint(canvas, x - eyeDistance * 0.28, eyeDistance * 0.65);
          CGContextAddLineToPoint(canvas, x, eyeDistance * 1.34);
          CGContextAddLineToPoint(canvas, x + eyeDistance * 0.28, eyeDistance * 0.65);
          CGContextClosePath(canvas);
          CGContextFillPath(canvas);
        }
        CGContextSetRGBStrokeColor(canvas, 1, 1, 1, 0.95);
        CGContextSetLineWidth(canvas, eyeDistance * 0.025);
        for (int side : {-1, 1}) {
          for (int whisker = -1; whisker <= 1; ++whisker) {
            CGContextMoveToPoint(canvas, side * eyeDistance * 0.35, -eyeDistance * 0.65);
            CGContextAddLineToPoint(canvas, side * eyeDistance * 0.95, -eyeDistance * (0.65 + whisker * 0.16));
            CGContextStrokePath(canvas);
          }
        }
      }
      CGContextRestoreGState(canvas);
    }
    CGImageRef overlay = CGBitmapContextCreateImage(canvas);
    CGContextRelease(canvas);
    if (!overlay) { CGColorSpaceRelease(space); return frame; }
    image = [[CIImage imageWithCGImage:overlay] imageByCompositingOverImage:image];
    CGImageRelease(overlay);
    CVPixelBufferRef output = NULL;
    CVReturn status = CVPixelBufferCreate(kCFAllocatorDefault, width, height, kCVPixelFormatType_32BGRA, (__bridge CFDictionaryRef)@{(id)kCVPixelBufferIOSurfacePropertiesKey: @{}}, &output);
    if (status != kCVReturnSuccess || !output) { CGColorSpaceRelease(space); return frame; }
    [_context render:image toCVPixelBuffer:output bounds:image.extent colorSpace:space];
    CGColorSpaceRelease(space);
    RTCVideoFrame *processed = [[RTCVideoFrame alloc] initWithBuffer:[[RTCCVPixelBuffer alloc] initWithPixelBuffer:output] rotation:RTCVideoRotation_0 timeStampNs:frame.timeStampNs];
    CVPixelBufferRelease(output);
    return processed;
  }
}
@end

@implementation ProMaxEffectsPlugin {
  ProMaxAudioProcessor *_audio;
  ProMaxFaceProcessor *_face;
  LocalVideoTrack *_track;
  BOOL _audioAttached;
}
+ (void)registerWithRegistrar:(NSObject<FlutterPluginRegistrar> *)registrar {
  FlutterMethodChannel *channel = [FlutterMethodChannel methodChannelWithName:@"promax/effects" binaryMessenger:registrar.messenger];
  ProMaxEffectsPlugin *instance = [[ProMaxEffectsPlugin alloc] init];
  [registrar addMethodCallDelegate:instance channel:channel];
}
- (instancetype)init {
  if ((self = [super init])) { _audio = [[ProMaxAudioProcessor alloc] init]; _face = [[ProMaxFaceProcessor alloc] init]; }
  return self;
}
- (void)handleMethodCall:(FlutterMethodCall *)call result:(FlutterResult)result {
  NSDictionary *args = [call.arguments isKindOfClass:[NSDictionary class]] ? call.arguments : @{};
  if ([call.method isEqualToString:@"setVoice"]) {
    NSNumber *value = args[@"voice"];
    if (![value isKindOfClass:[NSNumber class]] || value.intValue < 0 || value.intValue > 4) {
      result([FlutterError errorWithCode:@"BAD_VOICE" message:@"Unknown voice effect" details:nil]); return;
    }
    if (!_audioAttached) { [[AudioManager sharedInstance].capturePostProcessingAdapter addProcessing:_audio]; _audioAttached = YES; }
    [_audio setMode:value.intValue];
  } else if ([call.method isEqualToString:@"setMask"]) {
    NSNumber *value = args[@"mask"];
    NSString *trackId = args[@"trackId"];
    if (![value isKindOfClass:[NSNumber class]] || value.intValue < 0 || value.intValue > 3 || ![trackId isKindOfClass:[NSString class]]) {
      result([FlutterError errorWithCode:@"BAD_MASK" message:@"Unknown face mask" details:nil]); return;
    }
    id track = [FlutterWebRTCPlugin sharedSingleton].localTracks[trackId];
    if (![track isKindOfClass:[LocalVideoTrack class]]) {
      result([FlutterError errorWithCode:@"NO_CAMERA" message:@"Camera track is unavailable" details:nil]); return;
    }
    if (_track != track) { [_track removeProcessing:_face]; _track = track; [_track addProcessing:_face]; }
    [_face setMode:value.intValue];
  } else if ([call.method isEqualToString:@"reset"]) {
    [_audio setMode:0];
    [_face setMode:0];
    [_track removeProcessing:_face];
    _track = nil;
    if (_audioAttached) { [[AudioManager sharedInstance].capturePostProcessingAdapter removeProcessing:_audio]; _audioAttached = NO; }
  } else { result(FlutterMethodNotImplemented); return; }
  result(nil);
}
@end
