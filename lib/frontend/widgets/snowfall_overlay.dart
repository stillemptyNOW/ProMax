import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/config/promax_settings.dart';

/// Subtle, non-interactive snowfall that can be toggled in ProMax settings.
class SnowfallOverlay extends StatefulWidget {
  const SnowfallOverlay({super.key});

  @override
  State<SnowfallOverlay> createState() => _SnowfallOverlayState();
}

class _SnowfallOverlayState extends State<SnowfallOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animation = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 18),
  );

  @override
  void initState() {
    super.initState();
    ProMaxSettings.snowEffect.addListener(_syncAnimation);
    _syncAnimation();
  }

  void _syncAnimation() {
    if (ProMaxSettings.snowEffect.value) {
      if (!_animation.isAnimating) _animation.repeat();
    } else if (_animation.isAnimating) {
      _animation.stop();
    }
  }

  @override
  void dispose() {
    ProMaxSettings.snowEffect.removeListener(_syncAnimation);
    _animation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: ValueListenableBuilder<bool>(
      valueListenable: ProMaxSettings.snowEffect,
      builder: (context, enabled, _) {
        if (!enabled) return const SizedBox.shrink();
        return RepaintBoundary(
          child: CustomPaint(
            painter: _SnowPainter(_animation),
            size: Size.infinite,
          ),
        );
      },
    ),
  );
}

class _SnowParticle {
  const _SnowParticle(this.x, this.y, this.radius, this.speed, this.drift);

  final double x;
  final double y;
  final double radius;
  final double speed;
  final double drift;
}

class _SnowPainter extends CustomPainter {
  _SnowPainter(this.animation) : super(repaint: animation);

  final Animation<double> animation;
  Size? _cachedSize;
  List<_SnowParticle> _particles = const [];

  void _prepare(Size size) {
    if (_cachedSize == size) return;
    _cachedSize = size;
    final random = math.Random(1701);
    _particles = List.generate(
      64,
      (_) => _SnowParticle(
        random.nextDouble(),
        random.nextDouble(),
        0.7 + random.nextDouble() * 1.5,
        0.22 + random.nextDouble() * 0.58,
        4 + random.nextDouble() * 18,
      ),
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    _prepare(size);
    final progress = animation.value;
    final paint = Paint()..color = Colors.white.withValues(alpha: 0.52);
    for (var i = 0; i < _particles.length; i++) {
      final flake = _particles[i];
      final y = ((flake.y + progress * flake.speed) % 1) * size.height;
      final phase = progress * math.pi * 2 + i * 1.73;
      final x = (flake.x * size.width + math.sin(phase) * flake.drift).clamp(
        0.0,
        size.width,
      );
      canvas.drawCircle(Offset(x, y), flake.radius, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _SnowPainter oldDelegate) =>
      oldDelegate.animation != animation;
}
