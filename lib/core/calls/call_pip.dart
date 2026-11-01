import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' show MediaStream;

import '../config/call_pip_setting.dart';
import '../push/fkm_bridge.dart';
import '../push/native_event_stream.dart';
import '../utils/logger.dart';
import 'active_call.dart';
import 'call_session.dart';

@immutable
class CallPipConfig {
  const CallPipConfig({
    required this.eligible,
    required this.muted,
    required this.width,
    required this.height,
    this.trackId,
  });

  static const defaultWidth = 9;
  static const defaultHeight = 16;
  static const maxRatio = 239 / 100;

  static const off = CallPipConfig(
    eligible: false,
    muted: false,
    width: defaultWidth,
    height: defaultHeight,
  );

  final bool eligible;
  final bool muted;
  final int width;
  final int height;
  final String? trackId;

  static CallPipConfig resolve({
    required bool enabled,
    required CallSessionState? state,
    required bool remoteVideo,
    required bool localVideo,
    required bool muted,
    int? videoWidth,
    int? videoHeight,
    String? trackId,
  }) {
    final live = state != null && state != CallSessionState.ended;
    final eligible = enabled && live && (remoteVideo || localVideo);
    if (!eligible) return off;
    final (width, height) = remoteVideo
        ? aspect(videoWidth, videoHeight)
        : (defaultWidth, defaultHeight);
    return CallPipConfig(
      eligible: true,
      muted: muted,
      width: width,
      height: height,
      trackId: remoteVideo ? trackId : null,
    );
  }

  static (int, int) aspect(int? width, int? height) {
    if (width == null || height == null || width <= 0 || height <= 0) {
      return (defaultWidth, defaultHeight);
    }
    final ratio = width / height;
    if (ratio > maxRatio) return (239, 100);
    if (ratio < 1 / maxRatio) return (100, 239);
    return (width, height);
  }

  Map<String, Object?> toMap() => {
    'eligible': eligible,
    'muted': muted,
    'width': width,
    'height': height,
    'trackId': trackId,
  };

  @override
  bool operator ==(Object other) =>
      other is CallPipConfig &&
      other.eligible == eligible &&
      other.muted == muted &&
      other.width == width &&
      other.height == height &&
      other.trackId == trackId;

  @override
  int get hashCode => Object.hash(eligible, muted, width, height, trackId);
}

sealed class CallPipEvent {
  const CallPipEvent();

  static CallPipEvent? parse(Object? raw) {
    if (raw is! Map) return null;
    switch (raw['event']) {
      case 'mode':
        final pip = raw['pip'];
        return pip is bool ? CallPipModeChanged(pip) : null;
      case 'action':
        return switch (raw['action']) {
          'mute' => const CallPipToggleMute(),
          'hangup' => const CallPipHangUp(),
          _ => null,
        };
    }
    return null;
  }
}

class CallPipModeChanged extends CallPipEvent {
  const CallPipModeChanged(this.active);

  final bool active;
}

class CallPipToggleMute extends CallPipEvent {
  const CallPipToggleMute();
}

class CallPipHangUp extends CallPipEvent {
  const CallPipHangUp();
}

abstract class CallPipPlatform {
  Future<void> update(CallPipConfig config);

  void listen(void Function(Object? event) onEvent);

  Stream<void> get reattached;
}

class MethodChannelCallPipPlatform implements CallPipPlatform {
  static const _method = MethodChannel(
    'io.github.stillemptynow.promax/call_pip',
  );
  static const _events = EventChannel(
    'io.github.stillemptynow.promax/call_pip_events',
  );

  @override
  Future<void> update(CallPipConfig config) async {
    try {
      await _method.invokeMethod<void>('update', config.toMap());
    } on MissingPluginException {
      return;
    } catch (e) {
      logger.w('CallPip.update: $e');
    }
  }

  @override
  void listen(void Function(Object? event) onEvent) {
    if (!Platform.isAndroid) return;
    NativeEventStream(_events, 'CallPip').listen(onEvent);
  }

  @override
  Stream<void> get reattached => FkmBridge.instance.attached;
}

class CallPip extends ChangeNotifier {
  CallPip._(this._platform, this._presentation, this._enabled, this._supported);

  @visibleForTesting
  CallPip.test({
    required CallPipPlatform platform,
    required ValueListenable<ActiveCallPresentation?> presentation,
    required ValueListenable<bool> enabled,
  }) : this._(platform, presentation, enabled, true);

  static final CallPip instance = CallPip._(
    MethodChannelCallPipPlatform(),
    ActiveCall.instance.current,
    CallPipSetting.current,
    platformSupported,
  );

  static bool get platformSupported {
    if (kIsWeb) return false;
    return defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS;
  }

  final CallPipPlatform _platform;
  final ValueListenable<ActiveCallPresentation?> _presentation;
  final ValueListenable<bool> _enabled;
  final bool _supported;

  bool _started = false;
  bool _active = false;
  CallSession? _session;
  CallPipConfig _sent = CallPipConfig.off;
  int? _videoWidth;
  int? _videoHeight;
  final List<StreamSubscription<Object?>> _sessionSubs = [];
  StreamSubscription<void>? _reattachSub;

  bool get active => _active;
  CallPipConfig get config => _sent;
  ActiveCallPresentation? get presentation => _presentation.value;
  CallSession? get session => _session;

  MediaStream? get videoStream {
    final session = _session;
    if (session == null || !session.peerVideo) return null;
    final main = session.remoteStream;
    if (main != null && main.getVideoTracks().isNotEmpty) return main;
    for (final stream in session.participantStreams.values) {
      if (stream.getVideoTracks().isNotEmpty) return stream;
    }
    return null;
  }

  void init() {
    if (_started) return;
    _started = true;
    _presentation.addListener(_onPresentation);
    _enabled.addListener(sync);
    _platform.listen(handleEvent);
    _reattachSub = _platform.reattached.listen((_) => _push());
    _onPresentation();
  }

  void reportVideoSize(int width, int height) {
    if (width <= 0 || height <= 0) return;
    if (width == _videoWidth && height == _videoHeight) return;
    _videoWidth = width;
    _videoHeight = height;
    sync();
  }

  void _onPresentation() {
    final next = _presentation.value?.session;
    if (!identical(next, _session)) _bindSession(next);
    sync();
    notifyListeners();
  }

  void _bindSession(CallSession? session) {
    for (final sub in _sessionSubs) {
      unawaited(sub.cancel());
    }
    _sessionSubs.clear();
    _session = session;
    _videoWidth = null;
    _videoHeight = null;
    if (session == null) return;
    _sessionSubs
      ..add(session.stateStream.listen((_) => _onSessionChanged()))
      ..add(session.infoUpdates.listen((_) => _onSessionChanged()))
      ..add(session.remoteStreamStream.listen((_) => _onSessionChanged()))
      ..add(
        session.participantStreamUpdates.listen((_) => _onSessionChanged()),
      );
  }

  void _onSessionChanged() {
    sync();
    notifyListeners();
  }

  void sync() {
    final session = _session;
    final stream = videoStream;
    final next = CallPipConfig.resolve(
      enabled: _enabled.value && _supported,
      state: session?.currentState,
      remoteVideo: stream != null,
      localVideo: session?.localVideo ?? false,
      muted: session?.isMuted ?? false,
      videoWidth: _videoWidth,
      videoHeight: _videoHeight,
      trackId: stream?.getVideoTracks().first.id,
    );
    if (next == _sent) return;
    _sent = next;
    if (!next.eligible) _setActive(false);
    _push();
  }

  void _push() {
    if (_started) unawaited(_platform.update(_sent));
  }

  void handleEvent(Object? raw) {
    final event = CallPipEvent.parse(raw);
    switch (event) {
      case CallPipModeChanged(:final active):
        _setActive(active && _sent.eligible);
      case CallPipToggleMute():
        final session = _session;
        if (session != null) unawaited(session.setMuted(!session.isMuted));
      case CallPipHangUp():
        unawaited(_session?.hangup());
      case null:
        return;
    }
  }

  void _setActive(bool value) {
    if (_active == value) return;
    _active = value;
    notifyListeners();
  }

  @override
  void dispose() {
    _presentation.removeListener(_onPresentation);
    _enabled.removeListener(sync);
    unawaited(_reattachSub?.cancel());
    for (final sub in _sessionSubs) {
      unawaited(sub.cancel());
    }
    _sessionSubs.clear();
    super.dispose();
  }
}
