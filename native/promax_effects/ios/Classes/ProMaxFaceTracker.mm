#import "ProMaxFaceTracker.h"
#import <Vision/Vision.h>
#include <atomic>
#include <mutex>

static const double kProMaxDetectInterval = 1.0 / 15;
static const double kProMaxHotDetectInterval = 1.0 / 8;

static bool ProMaxCentroid(VNFaceLandmarkRegion2D *region, CGSize size, double &x, double &y) {
  if (!region || region.pointCount == 0) return false;
  const CGPoint *points = [region pointsInImageOfSize:size];
  if (!points) return false;
  double sumX = 0;
  double sumY = 0;
  for (NSUInteger index = 0; index < region.pointCount; ++index) {
    sumX += points[index].x;
    sumY += points[index].y;
  }
  const double count = static_cast<double>(region.pointCount);
  x = sumX / count;
  y = sumY / count;
  return std::isfinite(x) && std::isfinite(y);
}

static double ProMaxDistance(CGRect a, CGRect b) {
  return std::hypot(CGRectGetMidX(a) - CGRectGetMidX(b), CGRectGetMidY(a) - CGRectGetMidY(b));
}

static bool ProMaxSampleFace(VNFaceObservation *face, NSArray<VNFaceObservation *> *rectangles, CGSize size,
                             ProMaxFaceSample &sample) {
  VNFaceLandmarks2D *landmarks = face.landmarks;
  if (!landmarks) return false;
  if (!ProMaxCentroid(landmarks.leftPupil, size, sample.leftX, sample.leftY) &&
      !ProMaxCentroid(landmarks.leftEye, size, sample.leftX, sample.leftY)) {
    return false;
  }
  if (!ProMaxCentroid(landmarks.rightPupil, size, sample.rightX, sample.rightY) &&
      !ProMaxCentroid(landmarks.rightEye, size, sample.rightX, sample.rightY)) {
    return false;
  }
  if (!ProMaxCentroid(landmarks.nose, size, sample.noseX, sample.noseY)) return false;
  if (!ProMaxCentroid(landmarks.outerLips, size, sample.mouthX, sample.mouthY) &&
      !ProMaxCentroid(landmarks.innerLips, size, sample.mouthX, sample.mouthY)) {
    return false;
  }
  NSNumber *pitch = face.pitch;
  if (!pitch) {
    VNFaceObservation *nearest = nil;
    for (VNFaceObservation *candidate in rectangles) {
      if (!nearest || ProMaxDistance(candidate.boundingBox, face.boundingBox) <
                          ProMaxDistance(nearest.boundingBox, face.boundingBox)) {
        nearest = candidate;
      }
    }
    pitch = nearest.pitch;
  }
  sample.pitch = pitch ? pitch.doubleValue : NAN;
  return true;
}

@implementation ProMaxFaceTracker {
  dispatch_queue_t _queue;
  VNSequenceRequestHandler *_handler;
  std::atomic<bool> _busy;
  std::atomic<unsigned long long> _generation;
  std::atomic<double> _lastSubmit;
  std::mutex _lock;
  ProMaxMaskTracker _tracker;
}

- (instancetype)init {
  if ((self = [super init])) {
    dispatch_queue_attr_t attributes =
        dispatch_queue_attr_make_with_qos_class(DISPATCH_QUEUE_SERIAL, QOS_CLASS_USER_INITIATED, 0);
    _queue = dispatch_queue_create("promax.effects.faces", attributes);
    _handler = [[VNSequenceRequestHandler alloc] init];
    _busy.store(false);
    _generation.store(0);
    _lastSubmit.store(-1);
  }
  return self;
}

- (void)submitPixelBuffer:(CVPixelBufferRef)buffer
              orientation:(CGImagePropertyOrientation)orientation
              uprightSize:(CGSize)size
                     time:(double)time {
  const double interval = NSProcessInfo.processInfo.thermalState >= NSProcessInfoThermalStateSerious
                              ? kProMaxHotDetectInterval
                              : kProMaxDetectInterval;
  const double last = _lastSubmit.load();
  if (last >= 0 && time >= last && time - last < interval) return;
  bool idle = false;
  if (!_busy.compare_exchange_strong(idle, true)) return;
  _lastSubmit.store(time);
  const unsigned long long generation = _generation.load();
  CVPixelBufferRetain(buffer);
  dispatch_async(_queue, ^{
    [self detect:buffer orientation:orientation size:size time:time generation:generation];
    CVPixelBufferRelease(buffer);
    [self finishDetection];
  });
}

- (void)finishDetection {
  _busy.store(false);
}

- (void)detect:(CVPixelBufferRef)buffer
    orientation:(CGImagePropertyOrientation)orientation
           size:(CGSize)size
           time:(double)time
     generation:(unsigned long long)generation {
  @autoreleasepool {
    ProMaxFaceSample samples[ProMaxMaskTracker::kCapacity];
    std::size_t count = 0;
    VNDetectFaceRectanglesRequest *rectangles = [[VNDetectFaceRectanglesRequest alloc] init];
    rectangles.revision = VNDetectFaceRectanglesRequestRevision3;
    NSError *error = nil;
    if ([_handler performRequests:@[rectangles] onCVPixelBuffer:buffer orientation:orientation error:&error]) {
      NSMutableArray<VNFaceObservation *> *faces = [NSMutableArray array];
      for (id item in rectangles.results) {
        if ([item isKindOfClass:[VNFaceObservation class]]) [faces addObject:item];
      }
      [faces sortUsingComparator:^NSComparisonResult(VNFaceObservation *a, VNFaceObservation *b) {
        const CGFloat first = a.boundingBox.size.width * a.boundingBox.size.height;
        const CGFloat second = b.boundingBox.size.width * b.boundingBox.size.height;
        if (first > second) return NSOrderedAscending;
        if (first < second) return NSOrderedDescending;
        return NSOrderedSame;
      }];
      if (faces.count > ProMaxMaskTracker::kCapacity) {
        [faces removeObjectsInRange:NSMakeRange(ProMaxMaskTracker::kCapacity,
                                                faces.count - ProMaxMaskTracker::kCapacity)];
      }
      if (faces.count > 0) {
        VNDetectFaceLandmarksRequest *landmarks = [[VNDetectFaceLandmarksRequest alloc] init];
        landmarks.revision = VNDetectFaceLandmarksRequestRevision3;
        landmarks.inputFaceObservations = faces;
        if ([_handler performRequests:@[landmarks] onCVPixelBuffer:buffer orientation:orientation error:&error]) {
          for (id item in landmarks.results) {
            if (count >= ProMaxMaskTracker::kCapacity) break;
            if (![item isKindOfClass:[VNFaceObservation class]]) continue;
            if (ProMaxSampleFace((VNFaceObservation *)item, faces, size, samples[count])) ++count;
          }
        }
      }
    }
    std::lock_guard<std::mutex> guard(_lock);
    if (_generation.load() != generation) return;
    _tracker.update(samples, count, time);
  }
}

- (std::size_t)posesAtTime:(double)time into:(ProMaxFacePose *)poses capacity:(std::size_t)capacity {
  std::lock_guard<std::mutex> guard(_lock);
  return _tracker.poses(time, poses, capacity);
}

- (void)reset {
  std::lock_guard<std::mutex> guard(_lock);
  _generation.fetch_add(1);
  _tracker.reset();
  _lastSubmit.store(-1);
}

@end
