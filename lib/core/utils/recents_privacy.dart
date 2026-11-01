import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

abstract final class RecentsPrivacy {
  static const MethodChannel _channel = MethodChannel(
    'io.github.stillemptynow.promax/screen',
  );

  static bool get hasNativeShield =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  static Future<void> apply(bool hidden) async {
    if (!hasNativeShield) return;
    try {
      await _channel.invokeMethod<void>('setRecentsPrivacy', {
        'enabled': hidden,
      });
    } on PlatformException {
      return;
    } on MissingPluginException {
      return;
    }
  }
}
