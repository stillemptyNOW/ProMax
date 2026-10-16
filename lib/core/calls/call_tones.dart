import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

import '../media/desktop_audio_backend.dart';
import '../utils/logger.dart';

enum CallTone { ringtone, ringback }

class CallTones {
  CallTones._();

  static final CallTones instance = CallTones._();

  AudioPlayer? _player;
  CallTone? _playing;

  bool get supported {
    if (kIsWeb) return false;
    return defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.linux;
  }

  static String assetFor(CallTone tone) => 'assets/sounds/${tone.name}.wav';

  Future<void> play(CallTone tone) async {
    if (!supported || _playing == tone) return;
    _playing = tone;
    try {
      DesktopAudioBackend.ensureRegistered();
      final player = _player ??= AudioPlayer();
      await player.stop();
      await player.setAsset(assetFor(tone));
      if (_playing != tone) return;
      await player.setLoopMode(LoopMode.one);
      if (_playing != tone) return;
      unawaited(player.play());
    } catch (e) {
      logger.w('CallTones.play($tone): $e');
    }
  }

  Future<void> stop() async {
    if (_playing == null) return;
    _playing = null;
    try {
      await _player?.stop();
    } catch (e) {
      logger.w('CallTones.stop: $e');
    }
  }
}
