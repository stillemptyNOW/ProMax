import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

enum ProMaxVoice { normal, deep, helium, robot, radio }

enum ProMaxMask {
  none(null),
  sunglasses('sunglasses.png'),
  goggles('goggles.png'),
  heartEyes('heartEyes.png'),
  crown('crown.png'),
  topHat('topHat.png'),
  pigNose('pigNose.png'),
  mustache('mustache.png'),
  cat('cat.png'),
  fox('fox.png'),
  panda('panda.png'),
  alien('alien.png'),
  robot('robot.png'),
  pixels(null);

  const ProMaxMask(this.asset);

  static const package = 'promax_effects';
  static const directory = 'ios/Resources/masks';
  static const manifest = '$directory/masks.json';

  final String? asset;

  String get id => name;

  String? get assetPath => asset == null ? null : '$directory/$asset';
}

class ProMaxEffects {
  static const _channel = MethodChannel('promax/effects');

  static bool supportedOn(TargetPlatform platform, {required bool web}) =>
      !web &&
      (platform == TargetPlatform.iOS || platform == TargetPlatform.android);

  static bool get supported => supportedOn(defaultTargetPlatform, web: kIsWeb);

  static Future<void> setVoice(ProMaxVoice voice) =>
      _channel.invokeMethod('setVoice', {'voice': voice.index});

  static Future<void> setMask(String trackId, ProMaxMask mask) =>
      _channel.invokeMethod('setMask', {'trackId': trackId, 'mask': mask.id});

  static Future<void> reset() => _channel.invokeMethod('reset');

  static Future<void> setScreenLight(double brightness) =>
      _channel.invokeMethod('setScreenLight', {'brightness': brightness});

  static Future<void> restoreScreenBrightness() =>
      _channel.invokeMethod('restoreScreenBrightness');
}
