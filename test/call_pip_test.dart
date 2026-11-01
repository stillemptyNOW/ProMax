import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promax/core/calls/active_call.dart';
import 'package:promax/core/calls/call_pip.dart';
import 'package:promax/core/calls/call_session.dart';
import 'package:promax/core/calls/ws2_signaling.dart';

class _FakePlatform implements CallPipPlatform {
  final List<CallPipConfig> sent = [];
  final StreamController<void> reattach = StreamController<void>.broadcast();
  void Function(Object? event)? onEvent;

  @override
  Future<void> update(CallPipConfig config) async => sent.add(config);

  @override
  VoidCallback listen(void Function(Object? event) onEvent) {
    this.onEvent = onEvent;
    return () => this.onEvent = null;
  }

  @override
  Stream<void> get reattached => reattach.stream;
}

CallSession _session() => CallSession(
  ws2Config: Ws2Config(uri: Uri.parse('wss://calls.invalid/ws2'), userId: 7),
  role: CallRole.caller,
);

CallPipConfig _resolve({
  bool enabled = true,
  CallSessionState? state = CallSessionState.active,
  bool remoteVideo = false,
  bool localVideo = false,
  bool muted = false,
  int? width,
  int? height,
  String? trackId,
}) => CallPipConfig.resolve(
  enabled: enabled,
  state: state,
  remoteVideo: remoteVideo,
  localVideo: localVideo,
  muted: muted,
  videoWidth: width,
  videoHeight: height,
  trackId: trackId,
);

void main() {
  group('CallPipConfig.resolve', () {
    test('audio-only call is not eligible', () {
      expect(_resolve(), CallPipConfig.off);
    });

    test('setting off disables pip even with video', () {
      expect(_resolve(enabled: false, remoteVideo: true), CallPipConfig.off);
    });

    test('ended or missing call is not eligible', () {
      expect(
        _resolve(state: CallSessionState.ended, remoteVideo: true),
        CallPipConfig.off,
      );
      expect(_resolve(state: null, remoteVideo: true), CallPipConfig.off);
    });

    test('remote video uses its size and track', () {
      final config = _resolve(
        remoteVideo: true,
        muted: true,
        width: 1280,
        height: 720,
        trackId: 'track-a',
      );
      expect(config.eligible, isTrue);
      expect(config.muted, isTrue);
      expect((config.width, config.height), (1280, 720));
      expect(config.trackId, 'track-a');
    });

    test('local video alone keeps the portrait default and no track', () {
      final config = _resolve(localVideo: true, width: 1280, height: 720);
      expect(config.eligible, isTrue);
      expect((config.width, config.height), (9, 16));
      expect(config.trackId, isNull);
    });

    test('toMap carries every field', () {
      final map = _resolve(remoteVideo: true, trackId: 't').toMap();
      expect(map, {
        'eligible': true,
        'muted': false,
        'width': 9,
        'height': 16,
        'trackId': 't',
      });
    });
  });

  group('CallPipConfig.aspect', () {
    test('falls back on unknown size', () {
      expect(CallPipConfig.aspect(null, 10), (9, 16));
      expect(CallPipConfig.aspect(0, 0), (9, 16));
    });

    test('clamps to the platform limits', () {
      expect(CallPipConfig.aspect(4000, 100), (239, 100));
      expect(CallPipConfig.aspect(100, 4000), (100, 239));
      expect(CallPipConfig.aspect(480, 640), (480, 640));
    });
  });

  group('CallPipEvent.parse', () {
    test('reads mode and actions', () {
      final mode = CallPipEvent.parse({'event': 'mode', 'pip': true});
      expect(mode, isA<CallPipModeChanged>());
      expect((mode! as CallPipModeChanged).active, isTrue);
      expect(
        CallPipEvent.parse({'event': 'action', 'action': 'mute'}),
        isA<CallPipToggleMute>(),
      );
      expect(
        CallPipEvent.parse({'event': 'action', 'action': 'hangup'}),
        isA<CallPipHangUp>(),
      );
    });

    test('ignores malformed payloads', () {
      expect(CallPipEvent.parse(null), isNull);
      expect(CallPipEvent.parse('mode'), isNull);
      expect(CallPipEvent.parse({'event': 'mode', 'pip': 'yes'}), isNull);
      expect(CallPipEvent.parse({'event': 'action', 'action': 'x'}), isNull);
    });
  });

  group('CallPip', () {
    late _FakePlatform platform;
    late ValueNotifier<ActiveCallPresentation?> presentation;
    late ValueNotifier<bool> enabled;
    late CallPip pip;

    setUp(() {
      platform = _FakePlatform();
      presentation = ValueNotifier(null);
      enabled = ValueNotifier(true);
      pip = CallPip.test(
        platform: platform,
        presentation: presentation,
        enabled: enabled,
      )..init();
    });

    tearDown(() {
      pip.dispose();
      platform.reattach.close();
    });

    test('stays off and silent without a video call', () {
      presentation.value = ActiveCallPresentation(
        session: _session(),
        name: 'Test Peer',
        avatarUrl: null,
        isGroup: false,
      );
      expect(pip.config, CallPipConfig.off);
      expect(platform.sent, isEmpty);
    });

    test('mode event is ignored while the call is not eligible', () {
      platform.onEvent!({'event': 'mode', 'pip': true});
      expect(pip.active, isFalse);
    });

    test('mute action toggles the bound session', () async {
      final session = _session();
      presentation.value = ActiveCallPresentation(
        session: session,
        name: 'Test Peer',
        avatarUrl: null,
        isGroup: false,
      );
      expect(session.isMuted, isFalse);
      platform.onEvent!({'event': 'action', 'action': 'mute'});
      await Future<void>.delayed(Duration.zero);
      expect(session.isMuted, isTrue);
    });

    test('reattach resends the current config', () async {
      platform.reattach.add(null);
      await Future<void>.delayed(Duration.zero);
      expect(platform.sent, [CallPipConfig.off]);
    });

    test('presentation removal drops the session', () {
      presentation.value = ActiveCallPresentation(
        session: _session(),
        name: 'Test Peer',
        avatarUrl: null,
        isGroup: false,
      );
      expect(pip.session, isNotNull);
      presentation.value = null;
      expect(pip.session, isNull);
      expect(pip.active, isFalse);
    });
  });
}
