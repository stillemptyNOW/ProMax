import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:promax/core/media/sticker_maker.dart';

void main() {
  test('transparent or corrupt input has no subject', () {
    expect(StickerMaker.buildStickerPng(Uint8List.fromList([1, 2, 3])), isNull);
    final empty = img.Image(width: 20, height: 20, numChannels: 4);
    expect(StickerMaker.buildStickerPng(img.encodePng(empty)), isNull);
  });

  test(
    'sticker fits 512 pixels, keeps transparency and adds a white outline',
    () {
      final input = img.Image(width: 900, height: 600, numChannels: 4);
      img.fillRect(
        input,
        x1: 100,
        y1: 100,
        x2: 799,
        y2: 499,
        color: img.ColorRgba8(200, 20, 40, 255),
      );
      final bytes = StickerMaker.buildStickerPng(img.encodePng(input))!;
      final output = img.decodePng(bytes)!;
      expect(output.width, lessThanOrEqualTo(512));
      expect(output.height, lessThanOrEqualTo(512));
      expect(output.getPixel(0, 0).a, 0);
      expect(output.getPixel(output.width ~/ 2, output.height ~/ 2).r, 200);
      expect(
        output.any((p) => p.r == 255 && p.g == 255 && p.b == 255 && p.a == 255),
        isTrue,
      );
    },
  );
}
