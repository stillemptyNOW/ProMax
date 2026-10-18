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

enum ScreenShareFailure { denied, service, capture }

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
    degradation: RTCDegradationPreference.MAINTAIN_FRAMERATE,
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
