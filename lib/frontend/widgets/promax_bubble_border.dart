import 'dart:ui' as ui;

import 'package:flutter/material.dart';

enum BubbleTail { none, left, right }

class ProMaxBubbleBorder extends ShapeBorder {
  const ProMaxBubbleBorder({
    required this.radius,
    this.tail = BubbleTail.none,
    this.side = BorderSide.none,
  });

  final BorderRadius radius;
  final BubbleTail tail;
  final BorderSide side;

  static const double tailWidth = 7;

  @override
  EdgeInsetsGeometry get dimensions => EdgeInsets.zero;

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) =>
      getOuterPath(rect, textDirection: textDirection);

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) {
    final body = Path()..addRRect(radius.toRRect(rect));
    if (tail == BubbleTail.none || rect.height < 20) return body;
    final bottom = rect.bottom;
    final sign = tail == BubbleTail.right ? 1.0 : -1.0;
    final edge = tail == BubbleTail.right ? rect.right : rect.left;
    double x(double dx) => edge + sign * dx;
    final curl = Path()
      ..moveTo(x(0), bottom - 22)
      ..cubicTo(x(0), bottom - 7, x(2.5), bottom - 1.5, x(tailWidth), bottom)
      ..cubicTo(x(1.5), bottom + 0.6, x(-5), bottom - 0.8, x(-11), bottom - 4)
      ..lineTo(x(-11), bottom - 22)
      ..close();
    return Path.combine(ui.PathOperation.union, body, curl);
  }

  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {
    if (side.style == BorderStyle.none || side.width == 0) return;
    canvas.drawPath(
      getOuterPath(rect, textDirection: textDirection),
      side.toPaint(),
    );
  }

  @override
  ShapeBorder scale(double t) =>
      ProMaxBubbleBorder(radius: radius * t, tail: tail, side: side.scale(t));

  @override
  bool operator ==(Object other) =>
      other is ProMaxBubbleBorder &&
      other.radius == radius &&
      other.tail == tail &&
      other.side == side;

  @override
  int get hashCode => Object.hash(radius, tail, side);
}

Decoration promaxBubbleDecoration({
  required ColorScheme cs,
  required Color color,
  required bool isMe,
  required BorderRadius radius,
  required bool tail,
}) {
  final dark = cs.brightness == Brightness.dark;
  final gradient = isMe
      ? LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color.lerp(color, cs.primary, dark ? 0.22 : 0.16)!,
            color,
            Color.lerp(color, cs.tertiary, dark ? 0.16 : 0.12)!,
          ],
          stops: const [0, 0.55, 1],
        )
      : null;
  return ShapeDecoration(
    color: gradient == null ? color : null,
    gradient: gradient,
    shape: ProMaxBubbleBorder(
      radius: radius,
      tail: tail
          ? (isMe ? BubbleTail.right : BubbleTail.left)
          : BubbleTail.none,
      side: BorderSide(
        color: (dark ? Colors.white : Colors.black).withValues(
          alpha: isMe ? (dark ? 0.10 : 0.05) : (dark ? 0.07 : 0.06),
        ),
        width: 0.7,
      ),
    ),
  );
}
