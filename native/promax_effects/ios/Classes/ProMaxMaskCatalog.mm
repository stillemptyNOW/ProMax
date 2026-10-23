#import "ProMaxMaskCatalog.h"
#import <ImageIO/ImageIO.h>
#include <cmath>

static NSString *const kProMaxMaskBundleName = @"promax_effects_masks";

static double ProMaxNumber(id value, double fallback) {
  if (![value isKindOfClass:[NSNumber class]]) return fallback;
  const double number = [(NSNumber *)value doubleValue];
  return std::isfinite(number) ? number : fallback;
}

static double ProMaxComponent(id value, NSUInteger index, double fallback) {
  if (![value isKindOfClass:[NSArray class]]) return fallback;
  NSArray *components = (NSArray *)value;
  return index < components.count ? ProMaxNumber(components[index], fallback) : fallback;
}

static NSBundle *ProMaxMaskBundle(void) {
  NSArray<NSBundle *> *hosts = @[ [NSBundle bundleForClass:[ProMaxMaskCatalog class]], NSBundle.mainBundle ];
  for (NSBundle *host in hosts) {
    NSURL *url = [host URLForResource:kProMaxMaskBundleName withExtension:@"bundle"];
    NSBundle *bundle = url ? [NSBundle bundleWithURL:url] : nil;
    if (bundle) return bundle;
  }
  return nil;
}

static NSDictionary<NSString *, NSDictionary *> *ProMaxMaskEntries(NSBundle *bundle) {
  NSMutableDictionary<NSString *, NSDictionary *> *entries = [NSMutableDictionary dictionary];
  NSURL *url = [bundle URLForResource:@"masks" withExtension:@"json"];
  NSData *data = url ? [NSData dataWithContentsOfURL:url] : nil;
  id root = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
  id masks = [root isKindOfClass:[NSDictionary class]] ? ((NSDictionary *)root)[@"masks"] : nil;
  if (![masks isKindOfClass:[NSArray class]]) return entries;
  for (id item in (NSArray *)masks) {
    if (![item isKindOfClass:[NSDictionary class]]) continue;
    NSDictionary *entry = (NSDictionary *)item;
    id identifier = entry[@"id"];
    if ([identifier isKindOfClass:[NSString class]]) entries[(NSString *)identifier] = entry;
  }
  return entries;
}

static CIImage *ProMaxMaskImage(NSBundle *bundle, NSString *asset) {
  NSURL *url = [bundle URLForResource:asset withExtension:nil];
  if (!url) return nil;
  CGImageSourceRef source = CGImageSourceCreateWithURL((__bridge CFURLRef)url, NULL);
  if (!source) return nil;
  NSDictionary *options = @{(id)kCGImageSourceShouldCacheImmediately : @YES};
  CGImageRef picture = CGImageSourceCreateImageAtIndex(source, 0, (__bridge CFDictionaryRef)options);
  CFRelease(source);
  if (!picture) return nil;
  CIImage *image = [CIImage imageWithCGImage:picture];
  CGImageRelease(picture);
  if (image.extent.size.width < 1 || image.extent.size.height < 1) return nil;
  return image;
}

@interface ProMaxMaskStyle ()
- (instancetype)initWithIdentifier:(NSString *)identifier
                              spec:(ProMaxMaskSpec)spec
                          pixelate:(BOOL)pixelate
                             image:(CIImage *)image;
@end

@implementation ProMaxMaskStyle

- (instancetype)initWithIdentifier:(NSString *)identifier
                              spec:(ProMaxMaskSpec)spec
                          pixelate:(BOOL)pixelate
                             image:(CIImage *)image {
  if ((self = [super init])) {
    _identifier = [identifier copy];
    _spec = spec;
    _pixelate = pixelate;
    _image = image;
  }
  return self;
}

@end

@implementation ProMaxMaskCatalog {
  NSBundle *_bundle;
  NSDictionary<NSString *, NSDictionary *> *_entries;
  NSMutableDictionary<NSString *, ProMaxMaskStyle *> *_styles;
}

- (instancetype)init {
  if ((self = [super init])) {
    _bundle = ProMaxMaskBundle();
    _entries = ProMaxMaskEntries(_bundle);
    _styles = [NSMutableDictionary dictionary];
  }
  return self;
}

- (ProMaxMaskStyle *)styleWithIdentifier:(NSString *)identifier {
  ProMaxMaskStyle *cached = _styles[identifier];
  if (cached) return cached;
  NSDictionary *entry = _entries[identifier];
  if (!entry) return nil;
  id anchorName = entry[@"anchor"];
  int anchor = ProMaxMaskAnchorEyes;
  if (![anchorName isKindOfClass:[NSString class]] ||
      !promaxMaskAnchorNamed([(NSString *)anchorName UTF8String], anchor)) {
    return nil;
  }
  ProMaxMaskSpec spec;
  spec.anchor = anchor;
  spec.width = ProMaxNumber(entry[@"scale"], 0);
  spec.offsetX = ProMaxComponent(entry[@"offset"], 0, 0);
  spec.offsetY = ProMaxComponent(entry[@"offset"], 1, 0);
  spec.pivotX = ProMaxComponent(entry[@"pivot"], 0, 0.5);
  spec.pivotY = ProMaxComponent(entry[@"pivot"], 1, 0.5);
  spec.depth = ProMaxNumber(entry[@"depth"], 0);
  const BOOL pixelate = [entry[@"effect"] isEqual:@"pixelate"];
  CIImage *image = nil;
  if (pixelate) {
    spec.aspect = ProMaxNumber(entry[@"aspect"], 1);
  } else {
    id asset = entry[@"asset"];
    image = [asset isKindOfClass:[NSString class]] ? ProMaxMaskImage(_bundle, (NSString *)asset) : nil;
    if (!image) return nil;
    spec.aspect = image.extent.size.height / image.extent.size.width;
  }
  if (!(spec.width > 0) || !(spec.aspect > 0)) return nil;
  ProMaxMaskStyle *style = [[ProMaxMaskStyle alloc] initWithIdentifier:identifier
                                                                   spec:spec
                                                               pixelate:pixelate
                                                                  image:image];
  _styles[identifier] = style;
  return style;
}

@end
