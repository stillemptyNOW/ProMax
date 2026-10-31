import 'package:flutter/foundation.dart';

import 'motion_blur/motion_blur_plugin.dart';

abstract interface class NativePlugin {
  String get id;

  String get version;

  ValueListenable<bool> get enabled;

  Future<void> load();

  Future<void> setEnabled(bool value);
}

abstract final class NativePlugins {
  static final List<NativePlugin> all = List.unmodifiable(<NativePlugin>[
    MotionBlurPlugin.instance,
  ]);

  static Future<void> load() =>
      Future.wait([for (final plugin in all) plugin.load()]);
}
