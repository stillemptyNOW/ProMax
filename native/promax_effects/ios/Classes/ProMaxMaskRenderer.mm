#import "ProMaxMaskRenderer.h"
#import <CoreImage/CoreImage.h>
#import <Metal/Metal.h>
#include <algorithm>

static const int kProMaxPoolMinimum = 3;

static CGImagePropertyOrientation ProMaxInverseOrientation(CGImagePropertyOrientation orientation) {
  switch (orientation) {
    case kCGImagePropertyOrientationRight:
      return kCGImagePropertyOrientationLeft;
    case kCGImagePropertyOrientationLeft:
      return kCGImagePropertyOrientationRight;
    default:
      return orientation;
  }
}

static CIImage *ProMaxAtOrigin(CIImage *image) {
  const CGRect extent = image.extent;
  return [image imageByApplyingTransform:CGAffineTransformMakeTranslation(-extent.origin.x, -extent.origin.y)];
}

static bool ProMaxRenderableFormat(OSType format) {
  return format == kCVPixelFormatType_32BGRA || format == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange ||
         format == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange;
}

static CIVector *ProMaxPoint(double x, double y) { return [CIVector vectorWithX:x Y:y]; }

static CGRect ProMaxQuadBounds(const ProMaxMaskQuad &quad) {
  const double xs[] = {quad.topLeftX, quad.topRightX, quad.bottomRightX, quad.bottomLeftX};
  const double ys[] = {quad.topLeftY, quad.topRightY, quad.bottomRightY, quad.bottomLeftY};
  const double left = *std::min_element(xs, xs + 4);
  const double right = *std::max_element(xs, xs + 4);
  const double bottom = *std::min_element(ys, ys + 4);
  const double top = *std::max_element(ys, ys + 4);
  return CGRectMake(left, bottom, right - left, top - bottom);
}

@implementation ProMaxMaskRenderer {
  CIContext *_context;
  CVPixelBufferPoolRef _pool;
  OSType _poolFormat;
  size_t _poolWidth;
  size_t _poolHeight;
}

- (instancetype)init {
  if ((self = [super init])) {
    NSDictionary<CIContextOption, id> *options = @{
      kCIContextWorkingColorSpace : [NSNull null],
      kCIContextCacheIntermediates : @NO,
    };
    id<MTLDevice> device = MTLCreateSystemDefaultDevice();
    _context = device ? [CIContext contextWithMTLDevice:device options:options] : [CIContext contextWithOptions:options];
    _pool = NULL;
    _poolFormat = 0;
    _poolWidth = 0;
    _poolHeight = 0;
  }
  return self;
}

- (void)dealloc {
  if (_pool) CFRelease(_pool);
}

- (CVPixelBufferRef)createBufferWithFormat:(OSType)format
                                     width:(size_t)width
                                    height:(size_t)height {
  if (!_pool || _poolFormat != format || _poolWidth != width || _poolHeight != height) {
    if (_pool) {
      CFRelease(_pool);
      _pool = NULL;
    }
    NSDictionary *attributes = @{
      (id)kCVPixelBufferPixelFormatTypeKey : @(format),
      (id)kCVPixelBufferWidthKey : @(width),
      (id)kCVPixelBufferHeightKey : @(height),
      (id)kCVPixelBufferIOSurfacePropertiesKey : @{},
      (id)kCVPixelBufferMetalCompatibilityKey : @YES,
    };
    NSDictionary *poolAttributes = @{(id)kCVPixelBufferPoolMinimumBufferCountKey : @(kProMaxPoolMinimum)};
    CVPixelBufferPoolRef pool = NULL;
    if (CVPixelBufferPoolCreate(kCFAllocatorDefault, (__bridge CFDictionaryRef)poolAttributes,
                                (__bridge CFDictionaryRef)attributes, &pool) != kCVReturnSuccess ||
        !pool) {
      return NULL;
    }
    _pool = pool;
    _poolFormat = format;
    _poolWidth = width;
    _poolHeight = height;
  }
  CVPixelBufferRef buffer = NULL;
  if (CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, _pool, &buffer) != kCVReturnSuccess) return NULL;
  return buffer;
}

- (CIImage *)decorate:(CIImage *)frame
                style:(ProMaxMaskStyle *)style
                poses:(const ProMaxFacePose *)poses
                count:(std::size_t)count {
  CIImage *sticker = style.image;
  if (!sticker) return nil;
  const ProMaxMaskSpec spec = style.spec;
  CIImage *result = frame;
  ProMaxMaskQuad quads[2];
  for (std::size_t face = 0; face < count; ++face) {
    const std::size_t placed = promaxMaskQuads(spec, poses[face], quads, 2);
    for (std::size_t index = 0; index < placed; ++index) {
      const ProMaxMaskQuad &quad = quads[index];
      CIImage *layer = sticker;
      if (quad.alpha < 0.999) {
        layer = [layer imageByApplyingFilter:@"CIColorMatrix"
                         withInputParameters:@{@"inputAVector" : [CIVector vectorWithX:0 Y:0 Z:0 W:quad.alpha]}];
      }
      layer = [layer imageByApplyingFilter:@"CIPerspectiveTransform"
                       withInputParameters:@{
                         @"inputTopLeft" : ProMaxPoint(quad.topLeftX, quad.topLeftY),
                         @"inputTopRight" : ProMaxPoint(quad.topRightX, quad.topRightY),
                         @"inputBottomRight" : ProMaxPoint(quad.bottomRightX, quad.bottomRightY),
                         @"inputBottomLeft" : ProMaxPoint(quad.bottomLeftX, quad.bottomLeftY),
                       }];
      result = [layer imageByCompositingOverImage:result];
    }
  }
  return result;
}

- (CIImage *)pixelate:(CIImage *)frame
                style:(ProMaxMaskStyle *)style
                poses:(const ProMaxFacePose *)poses
                count:(std::size_t)count {
  const CGRect extent = frame.extent;
  const double block = std::max(24.0, std::min(extent.size.width, extent.size.height) / 18.0);
  CIImage *pixelated = [[frame imageByClampingToExtent] imageByApplyingFilter:@"CIPixellate"
                                                          withInputParameters:@{
                                                            kCIInputScaleKey : @(block),
                                                            kCIInputCenterKey : ProMaxPoint(0, 0),
                                                          }];
  pixelated = [pixelated imageByCroppingToRect:extent];
  if (count == 0) return pixelated;
  const ProMaxMaskSpec spec = style.spec;
  CIImage *result = frame;
  for (std::size_t face = 0; face < count; ++face) {
    ProMaxMaskQuad quad;
    if (promaxMaskQuads(spec, poses[face], &quad, 1) == 0) continue;
    const CGRect region = CGRectIntersection(extent, ProMaxQuadBounds(quad));
    if (CGRectIsNull(region) || CGRectIsEmpty(region)) continue;
    result = [[pixelated imageByCroppingToRect:region] imageByCompositingOverImage:result];
  }
  return result;
}

- (CVPixelBufferRef)renderFrame:(CVPixelBufferRef)input
                    orientation:(CGImagePropertyOrientation)orientation
                          style:(ProMaxMaskStyle *)style
                          poses:(const ProMaxFacePose *)poses
                          count:(std::size_t)count {
  const size_t width = CVPixelBufferGetWidth(input);
  const size_t height = CVPixelBufferGetHeight(input);
  if (width == 0 || height == 0) return NULL;
  CIImage *frame = ProMaxAtOrigin([[CIImage imageWithCVPixelBuffer:input] imageByApplyingCGOrientation:orientation]);
  const CGRect extent = frame.extent;
  CIImage *composed = style.pixelate ? [self pixelate:frame style:style poses:poses count:count]
                                     : [self decorate:frame style:style poses:poses count:count];
  if (!composed) return NULL;
  composed = [composed imageByCroppingToRect:extent];
  CIImage *output = ProMaxAtOrigin([composed imageByApplyingCGOrientation:ProMaxInverseOrientation(orientation)]);
  const OSType inputFormat = CVPixelBufferGetPixelFormatType(input);
  const OSType format = ProMaxRenderableFormat(inputFormat) ? inputFormat : kCVPixelFormatType_32BGRA;
  CVPixelBufferRef buffer = [self createBufferWithFormat:format width:width height:height];
  if (!buffer) return NULL;
  CVBufferPropagateAttachments(input, buffer);
  [_context render:output toCVPixelBuffer:buffer bounds:CGRectMake(0, 0, static_cast<CGFloat>(width), static_cast<CGFloat>(height))
          colorSpace:nil];
  return buffer;
}

@end
