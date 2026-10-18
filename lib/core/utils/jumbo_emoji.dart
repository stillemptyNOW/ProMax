import 'dart:math' as math;

const int jumboEmojiLimit = 30;

const List<double> _telegramEmojiScale = [.68, .46, .34, .28, .22, .19];
const double _telegramEmojiBase = 120;
const double _telegramEmojiInset = 4;
const double _singleAnimojiShare = 0.5;
const double _singleAnimojiZoom = 0.625;
const double _singleAnimojiMax = 180;

double _paintSize(int index) =>
    _telegramEmojiScale[index] * _telegramEmojiBase + _telegramEmojiInset;

double jumboEmojiFontSize(int count) => _paintSize(switch (count) {
  <= 2 => 2,
  3 => 3,
  4 => 4,
  _ => 5,
});

double jumboAnimojiSize(int count, double shortestSide) {
  if (count <= 1) {
    return math.min(
      shortestSide * _singleAnimojiShare * _singleAnimojiZoom,
      _singleAnimojiMax,
    );
  }
  return _paintSize(switch (count) {
    2 => 0,
    3 => 1,
    4 => 2,
    5 => 3,
    6 => 4,
    _ => 5,
  });
}
