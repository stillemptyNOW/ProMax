import 'dart:async';

import 'package:flutter/widgets.dart' show AppLifecycleState;
import 'package:flutter_webrtc/flutter_webrtc.dart';

enum OutgoingVideoSource { none, camera, screen }

OutgoingVideoSource outgoingVideoSource({
  required bool camera,
  required bool screen,
}) {
  if (screen) return OutgoingVideoSource.screen;
  if (camera) return OutgoingVideoSource.camera;
  return OutgoingVideoSource.none;
}

enum ScreenShareFailure { denied, service, capture, noPicture }

class ScreenShareException implements Exception {
  const ScreenShareException(this.failure, [this.cause]);

  final ScreenShareFailure failure;
  final Object? cause;

  @override
  String toString() => cause == null
      ? 'ScreenShareException(${failure.name})'
      : 'ScreenShareException(${failure.name}): $cause';
}

class ScreenCapturePipeline<T> {
  const ScreenCapturePipeline({
    required this.requestConsent,
    required this.setProjectionService,
    required this.capture,
  });

  final Future<bool> Function() requestConsent;
  final Future<bool> Function(bool enabled) setProjectionService;
  final Future<T> Function() capture;

  Future<T> open() async {
    final bool granted;
    try {
      granted = await requestConsent();
    } catch (e) {
      throw ScreenShareException(ScreenShareFailure.denied, e);
    }
    if (!granted) throw const ScreenShareException(ScreenShareFailure.denied);
    if (!await setProjectionService(true)) {
      throw const ScreenShareException(ScreenShareFailure.service);
    }
    try {
      return await capture();
    } on ScreenShareException {
      await setProjectionService(false);
      rethrow;
    } catch (e) {
      await setProjectionService(false);
      throw ScreenShareException(ScreenShareFailure.capture, e);
    }
  }

  Future<void> close(Future<void> Function() stopCapture) async {
    try {
      await stopCapture();
    } finally {
      await setProjectionService(false);
    }
  }
}

enum ScreenFrameOutcome { frame, declined, silent }

class ScreenFrameTimeouts {
  const ScreenFrameTimeouts({
    this.silent = const Duration(seconds: 10),
    this.afterPrompt = const Duration(seconds: 4),
    this.prompt = const Duration(minutes: 1),
  });

  final Duration silent;
  final Duration afterPrompt;
  final Duration prompt;
}

Future<ScreenFrameOutcome> waitForFirstScreenFrame({
  required Future<void> firstFrame,
  required Stream<AppLifecycleState> lifecycle,
  ScreenFrameTimeouts timeouts = const ScreenFrameTimeouts(),
}) {
  final outcome = Completer<ScreenFrameOutcome>();
  Timer? deadline;
  var prompted = false;

  void finish(ScreenFrameOutcome value) {
    if (outcome.isCompleted) return;
    deadline?.cancel();
    outcome.complete(value);
  }

  void arm(Duration after, ScreenFrameOutcome value) {
    deadline?.cancel();
    deadline = Timer(after, () => finish(value));
  }

  arm(timeouts.silent, ScreenFrameOutcome.silent);
  final subscription = lifecycle.listen((state) {
    if (state != AppLifecycleState.resumed) {
      prompted = true;
      arm(timeouts.prompt, ScreenFrameOutcome.declined);
    } else if (prompted) {
      arm(timeouts.afterPrompt, ScreenFrameOutcome.declined);
    }
  });
  firstFrame.then(
    (_) => finish(ScreenFrameOutcome.frame),
    onError: (Object _) => finish(ScreenFrameOutcome.silent),
  );
  return outcome.future.whenComplete(subscription.cancel);
}

abstract final class ScreenShareEncoding {
  static const int screenFramerate = 15;
  static const int screenBitrate = 1500000;
  static const int screenMaxSide = 1920;
  static const int cameraFramerate = 30;
  static const int cameraBitrate = 2500000;

  static double downscaleFor(int width, int height) {
    final longest = width > height ? width : height;
    if (longest <= screenMaxSide) return 1.0;
    return longest / screenMaxSide;
  }

  static RTCRtpParameters forScreen(
    RTCRtpParameters current, {
    double downscale = 1.0,
  }) => _tuned(
    current,
    degradation: RTCDegradationPreference.MAINTAIN_RESOLUTION,
    framerate: screenFramerate,
    bitrate: screenBitrate,
    downscale: downscale < 1.0 ? 1.0 : downscale,
  );

  static RTCRtpParameters forCamera(RTCRtpParameters current) => _tuned(
    current,
    degradation: RTCDegradationPreference.BALANCED,
    framerate: cameraFramerate,
    bitrate: cameraBitrate,
    downscale: 1.0,
  );

  static RTCRtpParameters _tuned(
    RTCRtpParameters current, {
    required RTCDegradationPreference degradation,
    required int framerate,
    required int bitrate,
    required double downscale,
  }) {
    final encodings = current.encodings ?? const <RTCRtpEncoding>[];
    return RTCRtpParameters(
      transactionId: current.transactionId,
      rtcp: current.rtcp,
      headerExtensions: current.headerExtensions,
      codecs: current.codecs,
      degradationPreference: degradation,
      encodings: [
        for (final encoding in encodings.isEmpty ? [null] : encodings)
          RTCRtpEncoding(
            rid: encoding?.rid,
            active: encoding?.active ?? true,
            minBitrate: encoding?.minBitrate,
            numTemporalLayers: encoding?.numTemporalLayers,
            ssrc: encoding?.ssrc,
            scalabilityMode: encoding?.scalabilityMode,
            priority: encoding?.priority ?? RTCPriorityType.low,
            networkPriority: encoding?.networkPriority,
            maxFramerate: framerate,
            maxBitrate: bitrate,
            scaleResolutionDownBy: downscale,
          ),
      ],
    );
  }
}
