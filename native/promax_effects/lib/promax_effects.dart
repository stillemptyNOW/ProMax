import 'package:flutter/services.dart';

enum ProMaxVoice { normal, deep, helium, robot, radio }

enum ProMaxMask { none, glasses, visor, cat, pixels }

class ProMaxEffects {
  static const _channel = MethodChannel('promax/effects');

  static Future<void> setVoice(ProMaxVoice voice) =>
      _channel.invokeMethod('setVoice', {'voice': voice.index});

  static Future<void> setMask(String trackId, ProMaxMask mask) => _channel
      .invokeMethod('setMask', {'trackId': trackId, 'mask': mask.index});

  static Future<void> reset() => _channel.invokeMethod('reset');

  static Future<void> setScreenLight(double brightness) =>
      _channel.invokeMethod('setScreenLight', {'brightness': brightness});

  static Future<void> restoreScreenBrightness() =>
      _channel.invokeMethod('restoreScreenBrightness');
}
