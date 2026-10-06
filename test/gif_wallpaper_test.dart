import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:promax/frontend/widgets/chat_wallpaper_sheet.dart';

void main() {
  test('gif signatures are recognised and other images are not', () {
    expect(isGifBytes(Uint8List.fromList('GIF89a....'.codeUnits)), isTrue);
    expect(isGifBytes(Uint8List.fromList('GIF87a....'.codeUnits)), isTrue);
    expect(
      isGifBytes(Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0, 0, 0, 0])),
      isFalse,
    );
    expect(isGifBytes(Uint8List.fromList('GIF8'.codeUnits)), isFalse);
  });
}
