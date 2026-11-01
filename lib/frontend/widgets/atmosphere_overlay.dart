import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../core/config/app_performance.dart';
import '../../core/config/promax_atmosphere.dart';
import 'ambient_clock.dart';

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

  AtmosphereStyle withBurstDefaults() => AtmosphereStyle(
    effect: effect,
    density: math.max(density, 1.6),
    speed: speed,
    size: size,
    opacity: math.max(opacity, 0.85),
    wind: wind,
    color: color,
  );

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

class ChatAtmosphereLayer extends StatelessWidget {
  const ChatAtmosphereLayer({super.key, required this.chatId});

  static const Duration burstDuration = Duration(milliseconds: 4200);

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
      final bursting = burst != null && burst.chatId == chatId;
      if (effect == AtmosphereEffect.none && !bursting) {
        return const SizedBox.shrink();
      }
      return Stack(
        fit: StackFit.expand,
        children: [
          if (effect != AtmosphereEffect.none)
            AtmosphereLayer(style: AtmosphereStyle.fromSettings(effect)),
          if (bursting)
            AtmosphereLayer(
              key: ValueKey('burst_${burst.serial}'),
              style: AtmosphereStyle.fromSettings(
                burst.effect,
              ).withBurstDefaults(),
              burst: burstDuration,
            ),
        ],
      );
    },
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
  late final AmbientClock _clock = AmbientClock(
    vsync: this,
    onTick: _tick,
    frameRate: AppPerformance.current.atmosphereFrameRate,
  );
  final ValueNotifier<double> _seconds = ValueNotifier(0);
  final AtmosphereField _field = AtmosphereField();
  bool _finished = false;
  bool _frozen = false;

  @override
  void initState() {
    super.initState();
    AppPerformance.budget.addListener(_onBudget);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _frozen = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    _syncClock();
  }

  @override
  void didUpdateWidget(AtmosphereLayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncClock();
  }

  void _onBudget() {
    _clock.frameRate = AppPerformance.current.atmosphereFrameRate;
    setState(() {});
  }

  void _syncClock() {
    final animates =
        !_finished && !_frozen && widget.style.effect != AtmosphereEffect.none;
    if (animates) {
      _clock.start();
    } else {
      _clock.stop();
    }
  }

  void _tick(Duration elapsed) {
    final burst = widget.burst;
    if (burst != null && elapsed >= burst) {
      _clock.stop();
      setState(() => _finished = true);
      return;
    }
    _seconds.value = elapsed.inMicroseconds / Duration.microsecondsPerSecond;
  }

  @override
  void dispose() {
    AppPerformance.budget.removeListener(_onBudget);
    _clock.dispose();
    _seconds.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_finished || widget.style.effect == AtmosphereEffect.none) {
      return const SizedBox.shrink();
    }
    if (_frozen && widget.burst != null) return const SizedBox.shrink();
    return IgnorePointer(
      child: RepaintBoundary(
        child: CustomPaint(
          size: Size.infinite,
          painter: AtmospherePainter(
            style: widget.style,
            seconds: _seconds,
            field: _field,
            budget: AppPerformance.current,
            frozen: _frozen,
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

@immutable
class AtmosphereSprite {
  const AtmosphereSprite(this.rect, this.extent);

  final Rect rect;
  final double extent;
}

class AtmosphereAtlas {
  AtmosphereAtlas._(this.image, this.sprites);

  static const int squashLevels = 4;
  static const List<double> squashes = [1.0, 0.72, 0.45, 0.18];
  static const double _shapeCell = 96;
  static const double _shapeUnit = 86;

  static AtmosphereAtlas? _instance;

  static AtmosphereAtlas get instance => _instance ??= _build();

  final ui.Image image;
  final Map<String, AtmosphereSprite> sprites;

  AtmosphereSprite operator [](String name) => sprites[name]!;

  static String squashed(String shape, double squash) {
    var best = 0;
    for (var i = 1; i < squashLevels; i++) {
      if ((squashes[i] - squash).abs() < (squashes[best] - squash).abs()) {
        best = i;
      }
    }
    return '$shape$best';
  }

  static AtmosphereAtlas _build() {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final sprites = <String, AtmosphereSprite>{};
    final white = Paint()
      ..isAntiAlias = true
      ..color = Colors.white;
    var x = 0.0;

    Rect cell(double width, double height) {
      final rect = Rect.fromLTWH(x, 0, width, height);
      x += width + 2;
      return rect;
    }

    final dot = cell(32, 32);
    canvas.drawCircle(
      dot.center,
      12,
      Paint()
        ..color = Colors.white
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.2),
    );
    sprites['dot'] = AtmosphereSprite(dot, 26);

    final glow = cell(64, 64);
    canvas.drawCircle(
      glow.center,
      32,
      Paint()
        ..shader = ui.Gradient.radial(
          glow.center,
          32,
          const [Colors.white, Color(0x66FFFFFF), Color(0x00FFFFFF)],
          const [0, 0.35, 1],
        ),
    );
    sprites['glow'] = AtmosphereSprite(glow, 64);

    final streak = cell(12, _shapeCell);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: streak.center, width: 6, height: _shapeUnit),
        const Radius.circular(3),
      ),
      white,
    );
    sprites['streak'] = AtmosphereSprite(streak, _shapeUnit);

    void shape(String name, Path path, double squash) {
      final rect = cell(_shapeCell, _shapeCell);
      canvas
        ..save()
        ..translate(rect.center.dx, rect.center.dy)
        ..scale(_shapeUnit * squash, _shapeUnit)
        ..drawPath(path, white)
        ..restore();
      sprites[name] = AtmosphereSprite(rect, _shapeUnit);
    }

    shape('heart', _heartPath, 1);
    shape('sparkle', _sparklePath, 1);
    for (var i = 0; i < squashLevels; i++) {
      shape('leaf$i', _leafPath, squashes[i]);
      shape('petal$i', _petalPath, squashes[i]);
      final rect = cell(48, 48);
      canvas.drawRect(
        Rect.fromCenter(
          center: rect.center,
          width: 40 * squashes[i],
          height: 18,
        ),
        white,
      );
      sprites['confetti$i'] = AtmosphereSprite(rect, 40);
    }

    final ring = cell(_shapeCell, _shapeCell);
    canvas
      ..drawCircle(
        ring.center,
        40,
        Paint()..color = Colors.white.withValues(alpha: 0.17),
      )
      ..drawCircle(
        ring.center,
        40,
        Paint()
          ..isAntiAlias = true
          ..style = PaintingStyle.stroke
          ..strokeWidth = 5
          ..color = Colors.white,
      );
    sprites['ring'] = AtmosphereSprite(ring, 80);

    final picture = recorder.endRecording();
    final image = picture.toImageSync(x.ceil(), _shapeCell.ceil());
    picture.dispose();
    return AtmosphereAtlas._(image, Map.unmodifiable(sprites));
  }

  static final Path _heartPath = Path()
    ..moveTo(0, 0.35)
    ..cubicTo(-0.05, 0.3, -0.5, 0.05, -0.5, -0.2)
    ..cubicTo(-0.5, -0.45, -0.2, -0.55, 0, -0.3)
    ..cubicTo(0.2, -0.55, 0.5, -0.45, 0.5, -0.2)
    ..cubicTo(0.5, 0.05, 0.05, 0.3, 0, 0.35)
    ..close();

  static final Path _leafPath = Path()
    ..moveTo(0, -0.5)
    ..quadraticBezierTo(0.42, -0.1, 0, 0.5)
    ..quadraticBezierTo(-0.42, -0.1, 0, -0.5)
    ..close();

  static final Path _petalPath = Path()
    ..moveTo(0, -0.45)
    ..cubicTo(0.35, -0.35, 0.35, 0.3, 0, 0.45)
    ..cubicTo(-0.35, 0.3, -0.35, -0.35, 0, -0.45)
    ..close();

  static final Path _sparklePath = Path()
    ..moveTo(0, -0.5)
    ..quadraticBezierTo(0.06, -0.06, 0.5, 0)
    ..quadraticBezierTo(0.06, 0.06, 0, 0.5)
    ..quadraticBezierTo(-0.06, 0.06, -0.5, 0)
    ..quadraticBezierTo(-0.06, -0.06, 0, -0.5)
    ..close();
}

class AtmosphereField {
  static const int spritesPerParticle = 2;

  List<_Particle> _particles = const [];
  AtmosphereEffect? _effect;
  int _count = -1;
  Float32List _transforms = Float32List(0);
  Float32List _rects = Float32List(0);
  Int32List _colors = Int32List(0);
  int _used = 0;

  int get particleCount => _particles.length;

  int get spriteCount => _used;

  int get capacity => _colors.length;

  void prepare(AtmosphereEffect effect, int count) {
    if (_effect == effect && _count == count) return;
    _effect = effect;
    _count = count;
    final random = math.Random(effect.index * 7919 + 17);
    _particles = List.generate(count, (_) => _Particle(random));
    final slots = count * spritesPerParticle + 1;
    if (slots > _colors.length) {
      _transforms = Float32List(slots * 4);
      _rects = Float32List(slots * 4);
      _colors = Int32List(slots);
    }
  }

  void begin() => _used = 0;

  void add(
    AtmosphereSprite sprite,
    double x,
    double y,
    double extent,
    int argb, {
    double rotation = 0,
  }) {
    if (_used >= _colors.length || extent <= 0 || (argb >>> 24) == 0) return;
    final scale = extent / sprite.extent;
    final scos = math.cos(rotation) * scale;
    final ssin = math.sin(rotation) * scale;
    final rect = sprite.rect;
    final ax = rect.width / 2;
    final ay = rect.height / 2;
    final i = _used * 4;
    _transforms[i] = scos;
    _transforms[i + 1] = ssin;
    _transforms[i + 2] = x - scos * ax + ssin * ay;
    _transforms[i + 3] = y - ssin * ax - scos * ay;
    _rects[i] = rect.left;
    _rects[i + 1] = rect.top;
    _rects[i + 2] = rect.right;
    _rects[i + 3] = rect.bottom;
    _colors[_used] = argb;
    _used++;
  }

  void flush(Canvas canvas, ui.Image atlas, Paint paint) {
    if (_used == 0) return;
    canvas.drawRawAtlas(
      atlas,
      Float32List.sublistView(_transforms, 0, _used * 4),
      Float32List.sublistView(_rects, 0, _used * 4),
      Int32List.sublistView(_colors, 0, _used),
      BlendMode.modulate,
      null,
      paint,
    );
  }
}

class AtmospherePainter extends CustomPainter {
  AtmospherePainter({
    required this.style,
    required this.seconds,
    required this.field,
    this.budget = EffectBudget.high,
    this.frozen = false,
    this.burst,
  }) : super(repaint: seconds);

  final AtmosphereStyle style;
  final ValueNotifier<double> seconds;
  final AtmosphereField field;
  final EffectBudget budget;
  final bool frozen;
  final Duration? burst;

  static const Map<AtmosphereEffect, int> baseCount = {
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

  static const List<int> _confettiPalette = [
    0xFF5D73,
    0xFFC23D,
    0x4FD1C5,
    0x7B5CFF,
    0x4F8EFF,
    0x7EE081,
  ];
  static const List<int> _leafPalette = [
    0xE8833A,
    0xD4572A,
    0xF2B33D,
    0xB5441F,
  ];
  static const List<int> _sakuraPalette = [0xFFC1D9, 0xFFA8C8, 0xFFD9E6];
  static const List<int> _heartPalette = [0xFF4D6D, 0xFF8FAB, 0xE5383B];

  static final Paint _atlasPaint = Paint()
    ..isAntiAlias = true
    ..filterQuality = FilterQuality.low;
  static final Paint _trail = Paint()
    ..isAntiAlias = true
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round;

  int get _count =>
      budget.particleCount(baseCount[style.effect] ?? 0, style.density);

  int _rgb(int fallback) =>
      style.color == 0 ? fallback : style.color & 0xFFFFFF;

  int _pick(List<int> palette, _Particle particle) => style.color == 0
      ? palette[particle.tone % palette.length]
      : style.color & 0xFFFFFF;

  static int _argb(int rgb, double alpha) {
    final a = (alpha.clamp(0.0, 1.0) * 255).round();
    return (a << 24) | (rgb & 0xFFFFFF);
  }

  static double _wrap(double value) => value - value.floorToDouble();

  static double _noise(double seed) {
    final v = math.sin(seed * 12.9898) * 43758.5453;
    return v - v.floorToDouble();
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty || style.effect == AtmosphereEffect.none) return;
    field.prepare(style.effect, _count);
    final t = frozen ? 0.0 : seconds.value * style.speed;
    final alpha = style.opacity * _burstFade();
    if (alpha <= 0) return;
    final unit = style.size * math.min(size.width, size.height) / 400;
    final atlas = AtmosphereAtlas.instance;
    field.begin();
    switch (style.effect) {
      case AtmosphereEffect.none:
        return;
      case AtmosphereEffect.snow:
        _snow(atlas, size, t, unit, alpha);
      case AtmosphereEffect.rain:
        _rain(atlas, size, t, unit, alpha);
      case AtmosphereEffect.stars:
        _stars(atlas, size, t, unit, alpha);
      case AtmosphereEffect.leaves:
        _falling(atlas, size, t, unit, alpha, 'leaf', _leafPalette, 9);
      case AtmosphereEffect.sakura:
        _falling(atlas, size, t, unit, alpha, 'petal', _sakuraPalette, 7);
      case AtmosphereEffect.hearts:
        _hearts(atlas, size, t, unit, alpha);
      case AtmosphereEffect.confetti:
        _confetti(atlas, size, t, unit, alpha);
      case AtmosphereEffect.sparkles:
        _sparkles(atlas, size, t, unit, alpha);
      case AtmosphereEffect.bubbles:
        _bubbles(atlas, size, t, unit, alpha);
      case AtmosphereEffect.fireflies:
        _fireflies(atlas, size, t, unit, alpha);
    }
    field.flush(canvas, atlas.image, _atlasPaint);
    if (style.effect == AtmosphereEffect.stars) {
      _shootingStar(canvas, size, t, unit, alpha);
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

  double _progress(_Particle particle, double t, double ambient, double rate) {
    if (burst == null) return _wrap(particle.y + t * ambient * particle.speed);
    return particle.y * -0.6 + seconds.value * rate * particle.speed * 1.4;
  }

  void _snow(
    AtmosphereAtlas atlas,
    Size size,
    double t,
    double unit,
    double a,
  ) {
    final dot = atlas['dot'];
    final color = _argb(_rgb(0xFFFFFF), a * 0.85);
    for (final p in field._particles) {
      final progress = _wrap(p.y + t * 0.05 * p.speed);
      final dy = progress * (size.height + 20) - 10;
      final sway = math.sin(t * 0.7 + p.phase) * 14 * unit;
      final dx = _wrap(p.x + style.wind * progress * 0.25) * size.width + sway;
      field.add(dot, dx, dy, 2 * (1.1 + p.scale * 1.6) * unit, color);
    }
  }

  void _rain(
    AtmosphereAtlas atlas,
    Size size,
    double t,
    double unit,
    double a,
  ) {
    final streak = atlas['streak'];
    final color = _argb(_rgb(0xBFD7FF), a * 0.55);
    final slant = style.wind * 10 * unit - 3 * unit;
    for (final p in field._particles) {
      final progress = _wrap(p.y + t * 0.75 * p.speed);
      final dy = progress * (size.height + 40) - 20;
      final dx = _wrap(p.x + style.wind * progress * 0.2) * size.width;
      final length = (10 + p.scale * 12) * unit;
      field.add(
        streak,
        dx + slant / 2,
        dy + length / 2,
        math.sqrt(slant * slant + length * length),
        color,
        rotation: math.atan2(-slant, length),
      );
    }
  }

  void _stars(
    AtmosphereAtlas atlas,
    Size size,
    double t,
    double unit,
    double a,
  ) {
    final glow = atlas['glow'];
    final dot = atlas['dot'];
    final rgb = _rgb(0xFFF6D8);
    for (final p in field._particles) {
      final twinkle =
          0.35 + 0.65 * (0.5 + 0.5 * math.sin(t * 1.6 * p.speed + p.phase));
      final cx = p.x * size.width;
      final cy = p.y * size.height;
      final radius = (0.7 + p.scale * 1.1) * unit;
      field
        ..add(glow, cx, cy, radius * 4.4 + 12, _argb(rgb, a * twinkle * 0.45))
        ..add(dot, cx, cy, radius * 2, _argb(rgb, a * twinkle));
    }
  }

  void _shootingStar(
    Canvas canvas,
    Size size,
    double t,
    double unit,
    double a,
  ) {
    const cycle = 7.0;
    final shot = t % cycle;
    if (shot >= 0.9) return;
    final lane = ((t / cycle).floor() * 0.37) % 1;
    final progress = shot / 0.9;
    final start = Offset(size.width * (0.15 + lane * 0.6), size.height * 0.08);
    final head = start + Offset(progress * 180 * unit, progress * 90 * unit);
    final tail = head - Offset(46 * unit, 23 * unit);
    final base = Color(_argb(_rgb(0xFFF6D8), 1));
    _trail
      ..strokeWidth = 1.6 * unit
      ..shader = ui.Gradient.linear(tail, head, [
        base.withValues(alpha: 0),
        base.withValues(alpha: a),
      ]);
    canvas.drawLine(tail, head, _trail);
    _trail.shader = null;
  }

  void _falling(
    AtmosphereAtlas atlas,
    Size size,
    double t,
    double unit,
    double a,
    String shape,
    List<int> palette,
    double dimension,
  ) {
    for (final p in field._particles) {
      final progress = _progress(p, t, 0.035, 0.18);
      if (progress > 1.1) continue;
      final dy = progress * (size.height + 40) - 20;
      final sway = math.sin(t * 0.9 + p.phase) * 30 * unit;
      final dx = _wrap(p.x + style.wind * progress * 0.3) * size.width + sway;
      final extent = dimension * (0.7 + p.scale) * unit * 1.6;
      final squash = 0.35 + 0.65 * math.cos(t * 1.3 + p.phase).abs();
      field.add(
        atlas[AtmosphereAtlas.squashed(shape, squash)],
        dx,
        dy,
        extent,
        _argb(_pick(palette, p), a * 0.9),
        rotation: t * p.spin * 0.6 + p.phase,
      );
    }
  }

  void _hearts(
    AtmosphereAtlas atlas,
    Size size,
    double t,
    double unit,
    double a,
  ) {
    final heart = atlas['heart'];
    for (final p in field._particles) {
      final progress = _progress(p, t, 0.04, 0.22);
      if (progress > 1.1) continue;
      final dy = size.height + 20 - progress * (size.height + 40);
      final dx =
          _wrap(p.x + style.wind * progress * 0.2) * size.width +
          math.sin(t * 1.2 + p.phase) * 18 * unit;
      final fade = progress > 0.75 ? (1 - progress) / 0.25 : 1.0;
      field.add(
        heart,
        dx,
        dy,
        (12 + p.scale * 12) * unit,
        _argb(_pick(_heartPalette, p), a * fade),
        rotation: math.sin(t + p.phase) * 0.25,
      );
    }
  }

  void _confetti(
    AtmosphereAtlas atlas,
    Size size,
    double t,
    double unit,
    double a,
  ) {
    for (final p in field._particles) {
      final progress = _progress(p, t, 0.06, 0.3);
      if (progress > 1.1) continue;
      final dy = progress * (size.height + 40) - 20;
      final dx =
          _wrap(p.x + style.wind * progress * 0.3) * size.width +
          math.sin(t * 2 + p.phase) * 12 * unit;
      final flip = math.cos(t * 3 * p.speed + p.phase).abs();
      field.add(
        atlas[AtmosphereAtlas.squashed('confetti', flip)],
        dx,
        dy,
        (5 + p.scale * 4) * unit,
        _argb(_pick(_confettiPalette, p), a),
        rotation: t * p.spin + p.phase,
      );
    }
  }

  void _sparkles(
    AtmosphereAtlas atlas,
    Size size,
    double t,
    double unit,
    double a,
  ) {
    final sparkle = atlas['sparkle'];
    final rgb = _rgb(0xFFF1B8);
    for (final p in field._particles) {
      final pulse = math.sin(t * 1.4 * p.speed + p.phase);
      if (pulse <= 0) continue;
      final cycle = ((t * 1.4 * p.speed + p.phase) / (math.pi * 2)).floor();
      final seed = (p.tone + cycle * 31).toDouble();
      field.add(
        sparkle,
        _wrap(p.x + _noise(seed) * 0.3) * size.width,
        _wrap(p.y + _noise(seed + 0.5) * 0.3) * size.height,
        (8 + p.scale * 10) * unit * pulse,
        _argb(rgb, a * pulse),
        rotation: t * 0.4 + p.phase,
      );
    }
  }

  void _bubbles(
    AtmosphereAtlas atlas,
    Size size,
    double t,
    double unit,
    double a,
  ) {
    final ring = atlas['ring'];
    final dot = atlas['dot'];
    final color = _argb(_rgb(0xBDE6FF), a * 0.7);
    final shine = _argb(0xFFFFFF, a * 0.7);
    for (final p in field._particles) {
      final progress = _wrap(p.y + t * 0.03 * p.speed);
      final dy = size.height + 20 - progress * (size.height + 40);
      final dx =
          _wrap(p.x + style.wind * progress * 0.2) * size.width +
          math.sin(t * 0.8 + p.phase) * 16 * unit;
      final radius = (4 + p.scale * 9) * unit;
      field
        ..add(ring, dx, dy, radius * 2, color)
        ..add(
          dot,
          dx - radius * 0.35,
          dy - radius * 0.35,
          radius * 0.36,
          shine,
        );
    }
  }

  void _fireflies(
    AtmosphereAtlas atlas,
    Size size,
    double t,
    double unit,
    double a,
  ) {
    final glow = atlas['glow'];
    final dot = atlas['dot'];
    final rgb = _rgb(0xE6FF7A);
    for (final p in field._particles) {
      final dx =
          _wrap(p.x + math.sin(t * 0.25 * p.speed + p.phase) * 0.06) *
          size.width;
      final dy =
          _wrap(p.y + math.cos(t * 0.2 * p.speed + p.phase * 1.3) * 0.05) *
          size.height;
      final light =
          0.25 + 0.75 * (0.5 + 0.5 * math.sin(t * 2.2 * p.speed + p.phase));
      final radius = (1.6 + p.scale * 1.4) * unit;
      field
        ..add(glow, dx, dy, radius * 6.4 + 12, _argb(rgb, a * light * 0.5))
        ..add(dot, dx, dy, radius * 2, _argb(rgb, a * light));
    }
  }

  @override
  bool shouldRepaint(covariant AtmospherePainter oldDelegate) =>
      oldDelegate.style != style ||
      oldDelegate.frozen != frozen ||
      oldDelegate.budget != budget ||
      !identical(oldDelegate.field, field) ||
      oldDelegate.seconds != seconds;
}
