import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/config/call_lighting.dart';

class CallScreenLight extends StatelessWidget {
  const CallScreenLight({super.key, required this.lighting});

  final CallLighting lighting;

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: CustomPaint(
      painter: _ScreenLightPainter(lighting),
      child: const SizedBox.expand(),
    ),
  );
}

class _ScreenLightPainter extends CustomPainter {
  const _ScreenLightPainter(this.lighting);

  final CallLighting lighting;

  @override
  void paint(Canvas canvas, Size size) {
    final width = lighting.width.clamp(
      0.0,
      math.min(size.width, size.height) / 2,
    );
    final path = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Offset.zero & size)
      ..addRRect(
        RRect.fromRectAndRadius(
          (Offset.zero & size).deflate(width),
          Radius.circular(lighting.radius),
        ),
      );
    canvas.drawPath(
      path,
      Paint()..color = lighting.color.withValues(alpha: lighting.opacity),
    );
  }

  @override
  bool shouldRepaint(_ScreenLightPainter oldDelegate) =>
      oldDelegate.lighting != lighting;
}
