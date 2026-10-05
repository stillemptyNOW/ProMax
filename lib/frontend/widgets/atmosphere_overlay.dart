import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../core/config/promax_atmosphere.dart';

@immutable
class AtmosphereStyle {
  const AtmosphereStyle({
    required this.effect,
    this.density = 1,
    this.speed = 1,
    this.size = 1,
    this.opacity = 0.7,
    this.wind = 0,
    this.color = 0,
  });

  factory AtmosphereStyle.fromSettings(AtmosphereEffect effect) =>
      AtmosphereStyle(
        effect: effect,
        density: ProMaxAtmosphere.density.value,
        speed: ProMaxAtmosphere.speed.value,
        size: ProMaxAtmosphere.size.value,
        opacity: ProMaxAtmosphere.opacity.value,
        wind: ProMaxAtmosphere.wind.value,
        color: ProMaxAtmosphere.color.value,
      );

  final AtmosphereEffect effect;
  final double density;
  final double speed;
  final double size;
  final double opacity;
  final double wind;
  final int color;

  @override
  bool operator ==(Object other) =>
      other is AtmosphereStyle &&
      other.effect == effect &&
      other.density == density &&
      other.speed == speed &&
      other.size == size &&
      other.opacity == opacity &&
      other.wind == wind &&
      other.color == color;

  @override
  int get hashCode =>
      Object.hash(effect, density, speed, size, opacity, wind, color);
}

class GlobalAtmosphereOverlay extends StatelessWidget {
  const GlobalAtmosphereOverlay({super.key});

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: ProMaxAtmosphere.listenable,
    builder: (context, _) {
      if (!ProMaxAtmosphere.showsGlobally) return const SizedBox.shrink();
      return AtmosphereLayer(
        style: AtmosphereStyle.fromSettings(ProMaxAtmosphere.effect.value),
      );
    },
  );
}

class ChatAtmosphereOverlay extends StatelessWidget {
  const ChatAtmosphereOverlay({super.key, required this.chatId});

  final int chatId;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([
      ProMaxAtmosphere.listenable,
      ProMaxAtmosphere.chatEffects,
      ProMaxAtmosphere.burst,
    ]),
    builder: (context, _) {
      final effect = ProMaxAtmosphere.chatLayerEffect(chatId);
      final burst = ProMaxAtmosphere.burst.value;
      final showsAmbient =
          effect != AtmosphereEffect.none &&
          !(ProMaxAtmosphere.showsGlobally &&
              ProMaxAtmosphere.chatEffect(chatId) == null);
      return Stack(
        fit: StackFit.expand,
        children: [
          if (showsAmbient)
            AtmosphereLayer(style: AtmosphereStyle.fromSettings(effect)),
          if (burst != null && burst.chatId == chatId)
            AtmosphereLayer(
              key: ValueKey('burst_${burst.serial}'),
              style: AtmosphereStyle.fromSettings(
                burst.effect,
              ).withBurstDefaults(),
              burst: const Duration(milliseconds: 4200),
            ),
        ],
      );
    },
  );
}

extension on AtmosphereStyle {
  AtmosphereStyle withBurstDefaults() => AtmosphereStyle(
    effect: effect,
    density: math.max(density, 1.6),
    speed: speed,
    size: size,
    opacity: math.max(opacity, 0.85),
    wind: wind,
    color: color,
  );
}

class AtmosphereLayer extends StatefulWidget {
  const AtmosphereLayer({super.key, required this.style, this.burst});

  final AtmosphereStyle style;
  final Duration? burst;

  @override
  State<AtmosphereLayer> createState() => _AtmosphereLayerState();
}

class _AtmosphereLayerState extends State<AtmosphereLayer>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker = createTicker(_tick);
  final ValueNotifier<double> _seconds = ValueNotifier(0);
  bool _finished = false;

  @override
  void initState() {
    super.initState();
    _ticker.start();
  }

  void _tick(Duration elapsed) {
    final seconds = elapsed.inMicroseconds / Duration.microsecondsPerSecond;
    final burst = widget.burst;
    if (burst != null && elapsed >= burst) {
      _ticker.stop();
      setState(() => _finished = true);
      return;
    }
    _seconds.value = seconds;
  }

  @override
  void dispose() {
    _ticker.dispose();
    _seconds.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_finished || widget.style.effect == AtmosphereEffect.none) {
      return const SizedBox.shrink();
    }
    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (reduceMotion && widget.burst != null) return const SizedBox.shrink();
    return IgnorePointer(
      child: RepaintBoundary(
        child: CustomPaint(
          size: Size.infinite,
          painter: AtmospherePainter(
            style: widget.style,
            seconds: _seconds,
            frozen: reduceMotion,
            burst: widget.burst,
          ),
        ),
      ),
    );
  }
}

class _Particle {
  _Particle(math.Random random)
    : x = random.nextDouble(),
      y = random.nextDouble(),
      scale = 0.55 + random.nextDouble() * 0.9,
      speed = 0.6 + random.nextDouble() * 0.8,
      phase = random.nextDouble() * math.pi * 2,
      spin = (random.nextDouble() - 0.5) * 4,
      tone = random.nextInt(1 << 16);

  final double x;
  final double y;
  final double scale;
  final double speed;
  final double phase;
  final double spin;
  final int tone;
}

class AtmospherePainter extends CustomPainter {
  AtmospherePainter({
    required this.style,
    required this.seconds,
    this.frozen = false,
    this.burst,
  }) : super(repaint: seconds);

  final AtmosphereStyle style;
  final ValueNotifier<double> seconds;
  final bool frozen;
  final Duration? burst;

  static const Map<AtmosphereEffect, int> _baseCount = {
    AtmosphereEffect.snow: 70,
    AtmosphereEffect.rain: 90,
    AtmosphereEffect.stars: 60,
    AtmosphereEffect.leaves: 22,
    AtmosphereEffect.sakura: 30,
    AtmosphereEffect.hearts: 22,
    AtmosphereEffect.confetti: 70,
    AtmosphereEffect.sparkles: 34,
    AtmosphereEffect.bubbles: 26,
    AtmosphereEffect.fireflies: 26,
  };

  static const List<Color> _confettiPalette = [
    Color(0xFFFF5D73),
    Color(0xFFFFC23D),
    Color(0xFF4FD1C5),
    Color(0xFF7B5CFF),
    Color(0xFF4F8EFF),
    Color(0xFF7EE081),
  ];
  static const List<Color> _leafPalette = [
    Color(0xFFE8833A),
    Color(0xFFD4572A),
    Color(0xFFF2B33D),
    Color(0xFFB5441F),
  ];
  static const List<Color> _sakuraPalette = [
    Color(0xFFFFC1D9),
    Color(0xFFFFA8C8),
    Color(0xFFFFD9E6),
  ];
  static const List<Color> _heartPalette = [
    Color(0xFFFF4D6D),
    Color(0xFFFF8FAB),
    Color(0xFFE5383B),
  ];

  List<_Particle> _particles = const [];
  AtmosphereEffect? _preparedFor;
  int _preparedCount = 0;

  final Paint _fill = Paint()..isAntiAlias = true;
  final Paint _glow = Paint()
    ..isAntiAlias = true
    ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
  final Paint _stroke = Paint()
    ..isAntiAlias = true
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round;

  static final Path _heartPath = _buildHeart();
  static final Path _leafPath = _buildLeaf();
  static final Path _petalPath = _buildPetal();
  static final Path _sparklePath = _buildSparkle();

  static Path _buildHeart() => Path()
    ..moveTo(0, 0.35)
    ..cubicTo(-0.05, 0.3, -0.5, 0.05, -0.5, -0.2)
    ..cubicTo(-0.5, -0.45, -0.2, -0.55, 0, -0.3)
    ..cubicTo(0.2, -0.55, 0.5, -0.45, 0.5, -0.2)
    ..cubicTo(0.5, 0.05, 0.05, 0.3, 0, 0.35)
    ..close();

  static Path _buildLeaf() => Path()
    ..moveTo(0, -0.5)
    ..quadraticBezierTo(0.42, -0.1, 0, 0.5)
    ..quadraticBezierTo(-0.42, -0.1, 0, -0.5)
    ..close();

  static Path _buildPetal() => Path()
    ..moveTo(0, -0.45)
    ..cubicTo(0.35, -0.35, 0.35, 0.3, 0, 0.45)
    ..cubicTo(-0.35, 0.3, -0.35, -0.35, 0, -0.45)
    ..close();

  static Path _buildSparkle() {
    final path = Path()..moveTo(0, -0.5);
    path
      ..quadraticBezierTo(0.06, -0.06, 0.5, 0)
      ..quadraticBezierTo(0.06, 0.06, 0, 0.5)
      ..quadraticBezierTo(-0.06, 0.06, -0.5, 0)
      ..quadraticBezierTo(-0.06, -0.06, 0, -0.5)
      ..close();
    return path;
  }

  int get _count {
    final base = _baseCount[style.effect] ?? 0;
    return (base * style.density).round().clamp(0, 320);
  }

  void _prepare() {
    final count = _count;
    if (_preparedFor == style.effect && _preparedCount == count) return;
    _preparedFor = style.effect;
    _preparedCount = count;
    final random = math.Random(style.effect.index * 7919 + 17);
    _particles = List.generate(count, (_) => _Particle(random));
  }

  Color _tint(Color fallback) =>
      style.color == 0 ? fallback : Color(style.color);

  Color _pick(List<Color> palette, _Particle particle) => style.color == 0
      ? palette[particle.tone % palette.length]
      : _tint(palette[0]);

  double _wrap(double value) => value - value.floorToDouble();

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty || style.effect == AtmosphereEffect.none) return;
    _prepare();
    final t = frozen ? 0.0 : seconds.value * style.speed;
    final alpha = style.opacity * _burstFade();
    if (alpha <= 0) return;
    final unit = style.size * math.min(size.width, size.height) / 400;
    switch (style.effect) {
      case AtmosphereEffect.none:
        return;
      case AtmosphereEffect.snow:
        _paintSnow(canvas, size, t, unit, alpha);
      case AtmosphereEffect.rain:
        _paintRain(canvas, size, t, unit, alpha);
      case AtmosphereEffect.stars:
        _paintStars(canvas, size, t, unit, alpha);
      case AtmosphereEffect.leaves:
        _paintFalling(canvas, size, t, unit, alpha, _leafPath, _leafPalette, 9);
      case AtmosphereEffect.sakura:
        _paintFalling(
          canvas,
          size,
          t,
          unit,
          alpha,
          _petalPath,
          _sakuraPalette,
          7,
        );
      case AtmosphereEffect.hearts:
        _paintHearts(canvas, size, t, unit, alpha);
      case AtmosphereEffect.confetti:
        _paintConfetti(canvas, size, t, unit, alpha);
      case AtmosphereEffect.sparkles:
        _paintSparkles(canvas, size, t, unit, alpha);
      case AtmosphereEffect.bubbles:
        _paintBubbles(canvas, size, t, unit, alpha);
      case AtmosphereEffect.fireflies:
        _paintFireflies(canvas, size, t, unit, alpha);
    }
  }

  double _burstFade() {
    final burst = this.burst;
    if (burst == null) return 1;
    final total = burst.inMilliseconds / 1000;
    final left = total - seconds.value;
    if (left < 1) return left.clamp(0.0, 1.0).toDouble();
    return 1;
  }

  double _burstProgress(_Particle particle, double rate) {
    if (burst == null) return _wrap(particle.y + seconds.value * rate);
    return particle.y * -0.6 + seconds.value * rate * 1.4;
  }

  void _paintSnow(Canvas canvas, Size size, double t, double unit, double a) {
    _fill.color = _tint(Colors.white).withValues(alpha: a * 0.85);
    for (final p in _particles) {
      final progress = _wrap(p.y + t * 0.05 * p.speed);
      final dy = progress * (size.height + 20) - 10;
      final sway = math.sin(t * 0.7 + p.phase) * 14 * unit;
      final dx = _wrap(p.x + style.wind * progress * 0.25) * size.width + sway;
      canvas.drawCircle(Offset(dx, dy), (1.1 + p.scale * 1.6) * unit, _fill);
    }
  }

  void _paintRain(Canvas canvas, Size size, double t, double unit, double a) {
    _stroke
      ..color = _tint(const Color(0xFFBFD7FF)).withValues(alpha: a * 0.55)
      ..strokeWidth = 1.1 * unit;
    final slant = style.wind * 10 * unit - 3 * unit;
    for (final p in _particles) {
      final progress = _wrap(p.y + t * 0.75 * p.speed);
      final dy = progress * (size.height + 40) - 20;
      final dx = _wrap(p.x + style.wind * progress * 0.2) * size.width;
      final length = (10 + p.scale * 12) * unit;
      canvas.drawLine(Offset(dx, dy), Offset(dx + slant, dy + length), _stroke);
    }
  }

  void _paintStars(Canvas canvas, Size size, double t, double unit, double a) {
    final base = _tint(const Color(0xFFFFF6D8));
    for (final p in _particles) {
      final twinkle =
          0.35 + 0.65 * (0.5 + 0.5 * math.sin(t * 1.6 * p.speed + p.phase));
      final center = Offset(p.x * size.width, p.y * size.height);
      final radius = (0.7 + p.scale * 1.1) * unit;
      _glow.color = base.withValues(alpha: a * twinkle * 0.45);
      canvas.drawCircle(center, radius * 2.2, _glow);
      _fill.color = base.withValues(alpha: a * twinkle);
      canvas.drawCircle(center, radius, _fill);
    }
    final cycle = 7.0;
    final shot = t % cycle;
    if (shot < 0.9) {
      final lane = ((t / cycle).floor() * 0.37) % 1;
      final progress = shot / 0.9;
      final start = Offset(
        size.width * (0.15 + lane * 0.6),
        size.height * 0.08,
      );
      final head = start + Offset(progress * 180 * unit, progress * 90 * unit);
      final tail = head - Offset(46 * unit, 23 * unit);
      _stroke
        ..strokeWidth = 1.6 * unit
        ..shader = LinearGradient(
          colors: [
            base.withValues(alpha: 0),
            base.withValues(alpha: a),
          ],
        ).createShader(Rect.fromPoints(tail, head));
      canvas.drawLine(tail, head, _stroke);
      _stroke.shader = null;
    }
  }

  void _paintFalling(
    Canvas canvas,
    Size size,
    double t,
    double unit,
    double a,
    Path shape,
    List<Color> palette,
    double dimension,
  ) {
    for (final p in _particles) {
      final progress = burst == null
          ? _wrap(p.y + t * 0.035 * p.speed)
          : _burstProgress(p, 0.18 * p.speed);
      if (progress > 1.1) continue;
      final dy = progress * (size.height + 40) - 20;
      final sway = math.sin(t * 0.9 + p.phase) * 30 * unit;
      final dx = _wrap(p.x + style.wind * progress * 0.3) * size.width + sway;
      final extent = dimension * (0.7 + p.scale) * unit * 1.6;
      canvas.save();
      canvas.translate(dx, dy);
      canvas.rotate(t * p.spin * 0.6 + p.phase);
      canvas.scale(
        extent * (0.35 + 0.65 * math.cos(t * 1.3 + p.phase).abs()),
        extent,
      );
      _fill.color = _pick(palette, p).withValues(alpha: a * 0.9);
      canvas.drawPath(shape, _fill);
      canvas.restore();
    }
  }

  void _paintHearts(Canvas canvas, Size size, double t, double unit, double a) {
    for (final p in _particles) {
      final progress = burst == null
          ? _wrap(p.y + t * 0.04 * p.speed)
          : _burstProgress(p, 0.22 * p.speed);
      if (progress > 1.1) continue;
      final dy = size.height + 20 - progress * (size.height + 40);
      final dx =
          _wrap(p.x + style.wind * progress * 0.2) * size.width +
          math.sin(t * 1.2 + p.phase) * 18 * unit;
      final extent = (12 + p.scale * 12) * unit;
      final fade = progress > 0.75 ? (1 - progress) / 0.25 : 1.0;
      canvas.save();
      canvas.translate(dx, dy);
      canvas.rotate(math.sin(t + p.phase) * 0.25);
      canvas.scale(extent);
      _fill.color = _pick(
        _heartPalette,
        p,
      ).withValues(alpha: (a * fade).clamp(0.0, 1.0).toDouble());
      canvas.drawPath(_heartPath, _fill);
      canvas.restore();
    }
  }

  void _paintConfetti(
    Canvas canvas,
    Size size,
    double t,
    double unit,
    double a,
  ) {
    for (final p in _particles) {
      final progress = burst == null
          ? _wrap(p.y + t * 0.06 * p.speed)
          : _burstProgress(p, 0.3 * p.speed);
      if (progress > 1.1) continue;
      final dy = progress * (size.height + 40) - 20;
      final dx =
          _wrap(p.x + style.wind * progress * 0.3) * size.width +
          math.sin(t * 2 + p.phase) * 12 * unit;
      final width = (5 + p.scale * 4) * unit;
      final height = width * 0.45;
      canvas.save();
      canvas.translate(dx, dy);
      canvas.rotate(t * p.spin + p.phase);
      canvas.scale(math.cos(t * 3 * p.speed + p.phase), 1);
      _fill.color = _pick(_confettiPalette, p).withValues(alpha: a);
      canvas.drawRect(
        Rect.fromCenter(center: Offset.zero, width: width, height: height),
        _fill,
      );
      canvas.restore();
    }
  }

  void _paintSparkles(
    Canvas canvas,
    Size size,
    double t,
    double unit,
    double a,
  ) {
    for (final p in _particles) {
      final pulse = math.sin(t * 1.4 * p.speed + p.phase);
      if (pulse <= 0) continue;
      final cycle = ((t * 1.4 * p.speed + p.phase) / (math.pi * 2)).floor();
      final jitter = math.Random(p.tone + cycle * 31);
      final center = Offset(
        _wrap(p.x + jitter.nextDouble() * 0.3) * size.width,
        _wrap(p.y + jitter.nextDouble() * 0.3) * size.height,
      );
      final extent = (8 + p.scale * 10) * unit * pulse;
      canvas.save();
      canvas.translate(center.dx, center.dy);
      canvas.rotate(t * 0.4 + p.phase);
      canvas.scale(extent);
      _fill.color = _tint(const Color(0xFFFFF1B8)).withValues(alpha: a * pulse);
      canvas.drawPath(_sparklePath, _fill);
      canvas.restore();
    }
  }

  void _paintBubbles(
    Canvas canvas,
    Size size,
    double t,
    double unit,
    double a,
  ) {
    final base = _tint(const Color(0xFFBDE6FF));
    for (final p in _particles) {
      final progress = _wrap(p.y + t * 0.03 * p.speed);
      final dy = size.height + 20 - progress * (size.height + 40);
      final dx =
          _wrap(p.x + style.wind * progress * 0.2) * size.width +
          math.sin(t * 0.8 + p.phase) * 16 * unit;
      final radius = (4 + p.scale * 9) * unit;
      _stroke
        ..strokeWidth = 1.1 * unit
        ..color = base.withValues(alpha: a * 0.7);
      canvas.drawCircle(Offset(dx, dy), radius, _stroke);
      _fill.color = base.withValues(alpha: a * 0.12);
      canvas.drawCircle(Offset(dx, dy), radius, _fill);
      _fill.color = Colors.white.withValues(alpha: a * 0.7);
      canvas.drawCircle(
        Offset(dx - radius * 0.35, dy - radius * 0.35),
        radius * 0.18,
        _fill,
      );
    }
  }

  void _paintFireflies(
    Canvas canvas,
    Size size,
    double t,
    double unit,
    double a,
  ) {
    final base = _tint(const Color(0xFFE6FF7A));
    for (final p in _particles) {
      final dx =
          _wrap(p.x + math.sin(t * 0.25 * p.speed + p.phase) * 0.06) *
          size.width;
      final dy =
          _wrap(p.y + math.cos(t * 0.2 * p.speed + p.phase * 1.3) * 0.05) *
          size.height;
      final glow =
          0.25 + 0.75 * (0.5 + 0.5 * math.sin(t * 2.2 * p.speed + p.phase));
      final radius = (1.6 + p.scale * 1.4) * unit;
      _glow.color = base.withValues(alpha: a * glow * 0.5);
      canvas.drawCircle(Offset(dx, dy), radius * 3.2, _glow);
      _fill.color = base.withValues(alpha: a * glow);
      canvas.drawCircle(Offset(dx, dy), radius, _fill);
    }
  }

  @override
  bool shouldRepaint(covariant AtmospherePainter oldDelegate) =>
      oldDelegate.style != style ||
      oldDelegate.frozen != frozen ||
      oldDelegate.seconds != seconds;
}
