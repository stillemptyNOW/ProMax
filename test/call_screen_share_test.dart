import 'dart:async';

import 'package:flutter/widgets.dart' show AppLifecycleState;
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:promax/core/calls/screen_share.dart';

class _Recorder {
  final List<String> calls = [];
  bool consent = true;
  bool service = true;
  Object? captureError;

  ScreenCapturePipeline<String> pipeline() => ScreenCapturePipeline<String>(
    requestConsent: () async {
      calls.add('consent');
      return consent;
    },
    setProjectionService: (enabled) async {
      calls.add('service:$enabled');
      return enabled ? service : true;
    },
    capture: () async {
      calls.add('capture');
      final error = captureError;
      if (error != null) throw error;
      return 'stream';
    },
  );
}

TypeMatcher<ScreenShareException> _failure(ScreenShareFailure failure) =>
    isA<ScreenShareException>().having((e) => e.failure, 'failure', failure);

void main() {
  group('outgoingVideoSource', () {
    test('screen wins over the camera', () {
      expect(
        outgoingVideoSource(camera: true, screen: true),
        OutgoingVideoSource.screen,
      );
      expect(
        outgoingVideoSource(camera: false, screen: true),
        OutgoingVideoSource.screen,
      );
    });

    test('camera only when not sharing', () {
      expect(
        outgoingVideoSource(camera: true, screen: false),
        OutgoingVideoSource.camera,
      );
      expect(
        outgoingVideoSource(camera: false, screen: false),
        OutgoingVideoSource.none,
      );
    });
  });

  group('ScreenCapturePipeline', () {
    test('asks consent, then upgrades the service, then captures', () async {
      final recorder = _Recorder();
      expect(await recorder.pipeline().open(), 'stream');
      expect(recorder.calls, ['consent', 'service:true', 'capture']);
    });

    test('denied consent never touches the service', () async {
      final recorder = _Recorder()..consent = false;
      await expectLater(
        recorder.pipeline().open(),
        throwsA(_failure(ScreenShareFailure.denied)),
      );
      expect(recorder.calls, ['consent']);
    });

    test('a consent error counts as denial', () async {
      final calls = <String>[];
      final pipeline = ScreenCapturePipeline<String>(
        requestConsent: () async => throw StateError('no activity'),
        setProjectionService: (enabled) async {
          calls.add('service:$enabled');
          return true;
        },
        capture: () async => 'stream',
      );
      await expectLater(
        pipeline.open(),
        throwsA(_failure(ScreenShareFailure.denied)),
      );
      expect(calls, isEmpty);
    });

    test('refused service upgrade skips the capture', () async {
      final recorder = _Recorder()..service = false;
      await expectLater(
        recorder.pipeline().open(),
        throwsA(_failure(ScreenShareFailure.service)),
      );
      expect(recorder.calls, ['consent', 'service:true']);
    });

    test('failed capture downgrades the service again', () async {
      final error = StateError('capture failed');
      final recorder = _Recorder()..captureError = error;
      await expectLater(
        recorder.pipeline().open(),
        throwsA(
          _failure(
            ScreenShareFailure.capture,
          ).having((e) => e.cause, 'cause', same(error)),
        ),
      );
      expect(recorder.calls, [
        'consent',
        'service:true',
        'capture',
        'service:false',
      ]);
    });

    test('a typed capture failure keeps its reason', () async {
      final recorder = _Recorder()
        ..captureError = const ScreenShareException(
          ScreenShareFailure.noPicture,
        );
      await expectLater(
        recorder.pipeline().open(),
        throwsA(_failure(ScreenShareFailure.noPicture)),
      );
      expect(recorder.calls, [
        'consent',
        'service:true',
        'capture',
        'service:false',
      ]);
    });

    test('close stops the capture before downgrading the service', () async {
      final recorder = _Recorder();
      await recorder.pipeline().close(() async => recorder.calls.add('stop'));
      expect(recorder.calls, ['stop', 'service:false']);
    });

    test('close downgrades the service even if stopping throws', () async {
      final recorder = _Recorder();
      await expectLater(
        recorder.pipeline().close(() async => throw StateError('stop')),
        throwsStateError,
      );
      expect(recorder.calls, ['service:false']);
    });
  });

  group('ScreenShareEncoding', () {
    RTCRtpParameters cameraParameters() => RTCRtpParameters(
      transactionId: 'tx-1',
      degradationPreference: RTCDegradationPreference.BALANCED,
      encodings: [
        RTCRtpEncoding(
          rid: 'r0',
          ssrc: 1234,
          numTemporalLayers: 2,
          priority: RTCPriorityType.medium,
        ),
      ],
    );

    test('screen keeps resolution at a low frame rate', () {
      final tuned = ScreenShareEncoding.forScreen(
        cameraParameters(),
        downscale: 1.25,
      );
      expect(tuned.transactionId, 'tx-1');
      expect(
        tuned.degradationPreference,
        RTCDegradationPreference.MAINTAIN_RESOLUTION,
      );
      final encoding = tuned.encodings!.single;
      expect(encoding.rid, 'r0');
      expect(encoding.ssrc, 1234);
      expect(encoding.numTemporalLayers, 2);
      expect(encoding.priority, RTCPriorityType.medium);
      expect(encoding.maxFramerate, ScreenShareEncoding.screenFramerate);
      expect(encoding.maxBitrate, ScreenShareEncoding.screenBitrate);
      expect(encoding.scaleResolutionDownBy, 1.25);
    });

    test('camera profile undoes the screen tuning', () {
      final screen = ScreenShareEncoding.forScreen(
        cameraParameters(),
        downscale: 2,
      );
      final camera = ScreenShareEncoding.forCamera(screen);
      expect(camera.degradationPreference, RTCDegradationPreference.BALANCED);
      final encoding = camera.encodings!.single;
      expect(encoding.rid, 'r0');
      expect(encoding.maxFramerate, ScreenShareEncoding.cameraFramerate);
      expect(encoding.maxBitrate, ScreenShareEncoding.cameraBitrate);
      expect(encoding.scaleResolutionDownBy, 1.0);
    });

    test('a sender without known encodings still gets one', () {
      final tuned = ScreenShareEncoding.forScreen(RTCRtpParameters());
      final encoding = tuned.encodings!.single;
      expect(encoding.active, isTrue);
      expect(encoding.numTemporalLayers, isNull);
      expect(encoding.maxFramerate, ScreenShareEncoding.screenFramerate);
      expect(encoding.scaleResolutionDownBy, 1.0);
    });

    test('downscale never upscales', () {
      final tuned = ScreenShareEncoding.forScreen(
        cameraParameters(),
        downscale: 0.5,
      );
      expect(tuned.encodings!.single.scaleResolutionDownBy, 1.0);
    });

    test('downscale caps the longest side', () {
      expect(ScreenShareEncoding.downscaleFor(720, 1280), 1.0);
      expect(ScreenShareEncoding.downscaleFor(1080, 1920), 1.0);
      expect(ScreenShareEncoding.downscaleFor(1080, 2400), 1.25);
      expect(ScreenShareEncoding.downscaleFor(3840, 2160), 2.0);
    });
  });

  group('waitForFirstScreenFrame', () {
    const timeouts = ScreenFrameTimeouts(
      silent: Duration(milliseconds: 120),
      afterPrompt: Duration(milliseconds: 60),
      prompt: Duration(milliseconds: 400),
    );

    late Completer<void> frame;
    late StreamController<AppLifecycleState> lifecycle;

    setUp(() {
      frame = Completer<void>();
      lifecycle = StreamController<AppLifecycleState>();
    });

    tearDown(() => lifecycle.close());

    Future<ScreenFrameOutcome> wait() => waitForFirstScreenFrame(
      firstFrame: frame.future,
      lifecycle: lifecycle.stream,
      timeouts: timeouts,
    );

    test('a frame means the capture runs', () async {
      final outcome = wait();
      frame.complete();
      expect(await outcome, ScreenFrameOutcome.frame);
      expect(lifecycle.hasListener, isFalse);
    });

    test('no prompt and no frame is a silent capture', () async {
      expect(await wait(), ScreenFrameOutcome.silent);
    });

    test('a frame after the accepted prompt wins', () async {
      final outcome = wait();
      lifecycle.add(AppLifecycleState.inactive);
      await Future<void>.delayed(const Duration(milliseconds: 200));
      lifecycle.add(AppLifecycleState.resumed);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      frame.complete();
      expect(await outcome, ScreenFrameOutcome.frame);
    });

    test('returning from the prompt without frames is a refusal', () async {
      final outcome = wait();
      lifecycle
        ..add(AppLifecycleState.inactive)
        ..add(AppLifecycleState.resumed);
      expect(await outcome, ScreenFrameOutcome.declined);
    });

    test('a prompt left open too long is a refusal', () async {
      final outcome = wait();
      lifecycle.add(AppLifecycleState.inactive);
      expect(await outcome, ScreenFrameOutcome.declined);
    });

    test('a failed frame check counts as silent', () async {
      final outcome = wait();
      frame.completeError(StateError('renderer'));
      expect(await outcome, ScreenFrameOutcome.silent);
    });
  });
}
