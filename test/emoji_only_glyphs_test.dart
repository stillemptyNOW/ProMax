import 'package:flutter_test/flutter_test.dart';
import 'package:promax/core/utils/text_format.dart';

void main() {
  group('emojiOnlyGlyphs', () {
    test('takes one to three emoji with spaces around them', () {
      expect(emojiOnlyGlyphs('😂', const []), ['😂']);
      expect(emojiOnlyGlyphs(' 🙏 ', const []), ['🙏']);
      expect(emojiOnlyGlyphs('🔥 🔥🔥', const []), ['🔥', '🔥', '🔥']);
    });

    test('keeps combined emoji as single glyphs', () {
      expect(emojiOnlyGlyphs('👨‍👩‍👧', const []), ['👨‍👩‍👧']);
      expect(emojiOnlyGlyphs('👍🏽', const []), ['👍🏽']);
      expect(emojiOnlyGlyphs('🇷🇺', const []), ['🇷🇺']);
      expect(emojiOnlyGlyphs('#️⃣', const []), ['#️⃣']);
      expect(emojiOnlyGlyphs('❤️', const []), ['❤️']);
    });

    test('rejects text, digits, symbols and too many emoji', () {
      expect(emojiOnlyGlyphs('ок 👍', const []), isNull);
      expect(emojiOnlyGlyphs('12', const []), isNull);
      expect(emojiOnlyGlyphs('©', const []), isNull);
      expect(emojiOnlyGlyphs('😂😂😂😂', const []), isNull);
      expect(emojiOnlyGlyphs('   ', const []), isNull);
      expect(emojiOnlyGlyphs(null, const []), isNull);
    });

    test('formatted text stays a normal message', () {
      expect(
        emojiOnlyGlyphs('😂', const [
          FormatRange(start: 0, length: 2, format: TextFormat.strong),
        ]),
        isNull,
      );
    });
  });
}
