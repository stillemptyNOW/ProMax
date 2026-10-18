import 'package:flutter_test/flutter_test.dart';
import 'package:promax/core/utils/jumbo_emoji.dart';

void main() {
  test('plain emoji shrink with their count the way Telegram does', () {
    expect(jumboEmojiFontSize(1), closeTo(44.8, 0.01));
    expect(jumboEmojiFontSize(2), closeTo(44.8, 0.01));
    expect(jumboEmojiFontSize(3), closeTo(37.6, 0.01));
    expect(jumboEmojiFontSize(4), closeTo(30.4, 0.01));
    expect(jumboEmojiFontSize(5), closeTo(26.8, 0.01));
    expect(jumboEmojiFontSize(jumboEmojiLimit), closeTo(26.8, 0.01));
  });

  test('a lone animated emoji takes a share of the screen, capped', () {
    expect(jumboAnimojiSize(1, 390), closeTo(121.875, 0.01));
    expect(jumboAnimojiSize(1, 1200), 180);
  });

  test('several animated emoji use the large emoji sizes', () {
    expect(jumboAnimojiSize(2, 390), closeTo(85.6, 0.01));
    expect(jumboAnimojiSize(3, 390), closeTo(59.2, 0.01));
    expect(jumboAnimojiSize(4, 390), closeTo(44.8, 0.01));
    expect(jumboAnimojiSize(9, 390), closeTo(26.8, 0.01));
  });
}
