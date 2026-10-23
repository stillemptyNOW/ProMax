#import "ProMaxEffectsPlugin.h"
#import "ProMaxMaskCatalog.h"
#import "ProMaxMaskProcessor.h"
#import "VoiceProcessor.h"
#import <flutter_webrtc/FlutterWebRTCPlugin.h>
#import <flutter_webrtc/LocalVideoTrack.h>
#import <flutter_webrtc/AudioManager.h>
#import <UIKit/UIKit.h>
#include <atomic>
#include <cmath>

static NSString *const kProMaxNoMask = @"none";

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

@implementation ProMaxEffectsPlugin {
  ProMaxAudioProcessor *_audio;
  ProMaxMaskProcessor *_face;
  ProMaxMaskCatalog *_masks;
  LocalVideoTrack *_track;
  BOOL _audioAttached;
  NSNumber *_originalBrightness;
  NSNumber *_lightBrightness;
}
+ (void)registerWithRegistrar:(NSObject<FlutterPluginRegistrar> *)registrar {
  FlutterMethodChannel *channel = [FlutterMethodChannel methodChannelWithName:@"promax/effects" binaryMessenger:registrar.messenger];
  ProMaxEffectsPlugin *instance = [[ProMaxEffectsPlugin alloc] init];
  [registrar addMethodCallDelegate:instance channel:channel];
}
- (instancetype)init {
  if ((self = [super init])) {
    _audio = [[ProMaxAudioProcessor alloc] init];
    _face = [[ProMaxMaskProcessor alloc] init];
    _masks = [[ProMaxMaskCatalog alloc] init];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(pauseLight) name:UIApplicationWillResignActiveNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(resumeLight) name:UIApplicationDidBecomeActiveNotification object:nil];
  }
  return self;
}
- (void)pauseLight {
  if (_originalBrightness) UIScreen.mainScreen.brightness = _originalBrightness.doubleValue;
}
- (void)resumeLight {
  if (_lightBrightness) UIScreen.mainScreen.brightness = _lightBrightness.doubleValue;
}
- (void)restoreBrightness {
  [self pauseLight];
  _originalBrightness = nil;
  _lightBrightness = nil;
}
- (void)dealloc { [[NSNotificationCenter defaultCenter] removeObserver:self]; }
- (void)handleMethodCall:(FlutterMethodCall *)call result:(FlutterResult)result {
  NSDictionary *args = [call.arguments isKindOfClass:[NSDictionary class]] ? call.arguments : @{};
  if ([call.method isEqualToString:@"setScreenLight"]) {
    NSNumber *value = args[@"brightness"];
    if (![value isKindOfClass:[NSNumber class]] || !std::isfinite(value.doubleValue) || value.doubleValue < 0.1 || value.doubleValue > 1) {
      result([FlutterError errorWithCode:@"BAD_BRIGHTNESS" message:@"Некорректная яркость" details:nil]); return;
    }
    if (!_originalBrightness) _originalBrightness = @(UIScreen.mainScreen.brightness);
    _lightBrightness = value;
    [self resumeLight];
  } else if ([call.method isEqualToString:@"restoreScreenBrightness"]) {
    [self restoreBrightness];
  } else if ([call.method isEqualToString:@"setVoice"]) {
    NSNumber *value = args[@"voice"];
    if (![value isKindOfClass:[NSNumber class]] || value.intValue < 0 || value.intValue > 4) {
      result([FlutterError errorWithCode:@"BAD_VOICE" message:@"Unknown voice effect" details:nil]); return;
    }
    if (!_audioAttached) { [[AudioManager sharedInstance].capturePostProcessingAdapter addProcessing:_audio]; _audioAttached = YES; }
    [_audio setMode:value.intValue];
  } else if ([call.method isEqualToString:@"setMask"]) {
    NSString *mask = args[@"mask"];
    NSString *trackId = args[@"trackId"];
    if (![mask isKindOfClass:[NSString class]] || ![trackId isKindOfClass:[NSString class]]) {
      result([FlutterError errorWithCode:@"BAD_MASK" message:@"Unknown face mask" details:nil]); return;
    }
    ProMaxMaskStyle *style = nil;
    if (![mask isEqualToString:kProMaxNoMask]) {
      style = [_masks styleWithIdentifier:mask];
      if (!style) {
        result([FlutterError errorWithCode:@"BAD_MASK" message:@"Unknown face mask" details:mask]); return;
      }
    }
    id track = [FlutterWebRTCPlugin sharedSingleton].localTracks[trackId];
    if (![track isKindOfClass:[LocalVideoTrack class]]) {
      result([FlutterError errorWithCode:@"NO_CAMERA" message:@"Camera track is unavailable" details:nil]); return;
    }
    if (_track != track) { [_track removeProcessing:_face]; _track = track; [_track addProcessing:_face]; }
    [_face setStyle:style];
  } else if ([call.method isEqualToString:@"reset"]) {
    [self restoreBrightness];
    [_audio setMode:0];
    [_face reset];
    [_track removeProcessing:_face];
    _track = nil;
    if (_audioAttached) { [[AudioManager sharedInstance].capturePostProcessingAdapter removeProcessing:_audio]; _audioAttached = NO; }
  } else { result(FlutterMethodNotImplemented); return; }
  result(nil);
}
@end
