import 'package:flutter/foundation.dart';

abstract final class PlatformSettings {
  static const platforms = {
    'android',
    'ios',
    'windows',
    'macos',
    'linux',
    'web',
    'fuchsia',
  };
  static String get current => kIsWeb
      ? 'web'
      : switch (defaultTargetPlatform) {
          TargetPlatform.iOS => 'ios',
          TargetPlatform.macOS => 'macos',
          final platform => platform.name,
        };

  static String get label => switch (current) {
    'android' => 'Android',
    'ios' => 'iOS',
    'windows' => 'Windows',
    'macos' => 'macOS',
    'linux' => 'Linux',
    'web' => 'Web',
    _ => 'Fuchsia',
  };

  static const mobile = {'android', 'ios'};
  static const allKeys = {
    'app_performance_mode',
    'app_native_glass',
    'call_pip_enabled',
    'dev_video_note_resolution',
    'dev_video_note_fps',
    'dev_video_note_rear_camera',
  };

  static Map<String, Object> defaults(String platform) => {
    'app_performance_mode': 'auto',
    if (platform == 'ios') 'app_native_glass': true,
    if (mobile.contains(platform)) ...{
      'call_pip_enabled': true,
      'dev_video_note_resolution': 480,
      'dev_video_note_fps': 30,
      'dev_video_note_rear_camera': false,
    },
  };

  static bool valid(String platform, String key, Object? value) {
    if (!defaults(platform).containsKey(key)) return false;
    return switch (key) {
      'app_performance_mode' => {'auto', 'smooth', 'beauty'}.contains(value),
      'dev_video_note_resolution' =>
        value is int && {480, 720, 1080}.contains(value),
      'dev_video_note_fps' => value is int && {30, 60}.contains(value),
      _ => value is bool,
    };
  }
}
