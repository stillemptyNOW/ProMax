import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';

enum StickerMakeFailure { unavailable, modelDownloading, noSubject }

class StickerMakeResult {
  final File? file;
  final StickerMakeFailure? failure;

  const StickerMakeResult.success(File this.file) : failure = null;

  const StickerMakeResult.failure(StickerMakeFailure this.failure)
    : file = null;
}

class StickerMaker {
  StickerMaker._();

  static const MethodChannel _channel = MethodChannel(
    'io.github.stillemptynow.promax/sticker',
  );

  static const int maxSide = 512;
  static const int strokeWidth = 7;
  static const int _alphaThreshold = 12;

  static Future<bool>? _available;

  static bool get platformSupported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  static Future<bool> available() => _available ??= _probe();

  static Future<bool> _probe() async {
    if (!platformSupported) return false;
    try {
      return await _channel.invokeMethod<bool>('available') ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  static Future<StickerMakeResult> make(File source) async {
    if (!await available()) {
      return const StickerMakeResult.failure(StickerMakeFailure.unavailable);
    }
    String? liftedPath;
    try {
      liftedPath = await _channel.invokeMethod<String>('lift', {
        'path': source.path,
      });
    } on PlatformException catch (e) {
      return StickerMakeResult.failure(
        e.code == 'downloading'
            ? StickerMakeFailure.modelDownloading
            : StickerMakeFailure.noSubject,
      );
    } on MissingPluginException {
      return const StickerMakeResult.failure(StickerMakeFailure.unavailable);
    }
    if (liftedPath == null) {
      return const StickerMakeResult.failure(StickerMakeFailure.noSubject);
    }
    final lifted = File(liftedPath);
    final Uint8List bytes;
    try {
      bytes = await lifted.readAsBytes();
    } on FileSystemException {
      return const StickerMakeResult.failure(StickerMakeFailure.noSubject);
    }
    final png = await compute(buildStickerPng, bytes);
    lifted.delete().then((_) {}, onError: (_) {});
    if (png == null) {
      return const StickerMakeResult.failure(StickerMakeFailure.noSubject);
    }
    final dir = await getTemporaryDirectory();
    final out = File(
      '${dir.path}/sticker_${DateTime.now().millisecondsSinceEpoch}.png',
    );
    await out.writeAsBytes(png, flush: true);
    return StickerMakeResult.success(out);
  }

  static Uint8List? buildStickerPng(Uint8List encoded) {
    final decoded = img.decodeImage(encoded);
    if (decoded == null) return null;
    final rgba = decoded.convert(format: img.Format.uint8, numChannels: 4);
    final bounds = _opaqueBounds(rgba);
    if (bounds == null) return null;

    final cropped = img.copyCrop(
      rgba,
      x: bounds.left,
      y: bounds.top,
      width: bounds.width,
      height: bounds.height,
    );
    const pad = strokeWidth + 2;
    const inner = maxSide - pad * 2;
    final longest = math.max(cropped.width, cropped.height);
    final scale = math.min(inner / longest, 3.0);
    final width = math.max(1, (cropped.width * scale).round());
    final height = math.max(1, (cropped.height * scale).round());
    final subject = img.copyResize(
      cropped,
      width: width,
      height: height,
      interpolation: img.Interpolation.linear,
    );

    final outWidth = width + pad * 2;
    final outHeight = height + pad * 2;
    final src = subject.getBytes(order: img.ChannelOrder.rgba);
    final coverage = Uint8List(outWidth * outHeight);
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        coverage[(y + pad) * outWidth + x + pad] = src[(y * width + x) * 4 + 3];
      }
    }

    final distance = _distanceToSubject(coverage, outWidth, outHeight);
    final out = Uint8List(outWidth * outHeight * 4);
    for (var y = 0; y < outHeight; y++) {
      for (var x = 0; x < outWidth; x++) {
        final index = y * outWidth + x;
        final outline = (strokeWidth + 0.5 - distance[index]).clamp(0.0, 1.0);
        final sx = x - pad;
        final sy = y - pad;
        var r = 0.0, g = 0.0, b = 0.0, sa = 0.0;
        if (sx >= 0 && sy >= 0 && sx < width && sy < height) {
          final s = (sy * width + sx) * 4;
          r = src[s].toDouble();
          g = src[s + 1].toDouble();
          b = src[s + 2].toDouble();
          sa = src[s + 3] / 255.0;
        }
        final alpha = sa + outline * (1 - sa);
        final o = index * 4;
        if (alpha <= 0) continue;
        final white = 255.0 * outline * (1 - sa);
        out[o] = ((r * sa + white) / alpha).round().clamp(0, 255);
        out[o + 1] = ((g * sa + white) / alpha).round().clamp(0, 255);
        out[o + 2] = ((b * sa + white) / alpha).round().clamp(0, 255);
        out[o + 3] = (alpha * 255).round().clamp(0, 255);
      }
    }
    final image = img.Image.fromBytes(
      width: outWidth,
      height: outHeight,
      bytes: out.buffer,
      numChannels: 4,
    );
    return img.encodePng(image);
  }

  static ({int left, int top, int width, int height})? _opaqueBounds(
    img.Image image,
  ) {
    final bytes = image.getBytes(order: img.ChannelOrder.rgba);
    final w = image.width;
    final h = image.height;
    var left = w, top = h, right = -1, bottom = -1;
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        if (bytes[(y * w + x) * 4 + 3] <= _alphaThreshold) continue;
        if (x < left) left = x;
        if (x > right) right = x;
        if (y < top) top = y;
        if (y > bottom) bottom = y;
      }
    }
    if (right < 0) return null;
    return (
      left: left,
      top: top,
      width: right - left + 1,
      height: bottom - top + 1,
    );
  }

  static Float32List _distanceToSubject(
    Uint8List coverage,
    int width,
    int height,
  ) {
    const far = 1e6;
    const diagonal = math.sqrt2;
    final d = Float32List(width * height);
    for (var i = 0; i < d.length; i++) {
      d[i] = coverage[i] >= 128 ? 0 : far;
    }
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        final i = y * width + x;
        var v = d[i];
        if (x > 0) v = math.min(v, d[i - 1] + 1);
        if (y > 0) {
          v = math.min(v, d[i - width] + 1);
          if (x > 0) v = math.min(v, d[i - width - 1] + diagonal);
          if (x < width - 1) v = math.min(v, d[i - width + 1] + diagonal);
        }
        d[i] = v;
      }
    }
    for (var y = height - 1; y >= 0; y--) {
      for (var x = width - 1; x >= 0; x--) {
        final i = y * width + x;
        var v = d[i];
        if (x < width - 1) v = math.min(v, d[i + 1] + 1);
        if (y < height - 1) {
          v = math.min(v, d[i + width] + 1);
          if (x < width - 1) v = math.min(v, d[i + width + 1] + diagonal);
          if (x > 0) v = math.min(v, d[i + width - 1] + diagonal);
        }
        d[i] = v;
      }
    }
    return d;
  }
}
