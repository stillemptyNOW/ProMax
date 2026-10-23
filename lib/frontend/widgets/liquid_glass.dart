import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';

import '../../core/config/app_frost.dart';
import '../../core/config/app_liquid_glass.dart';
import '../../core/config/app_native_glass.dart';
import '../../core/config/promax_glass.dart';
import 'native_glass_view.dart';

class LiquidGlass {
  static const String _asset = 'shaders/liquid_glass.frag';

  static ui.FragmentProgram? _program;
  static bool _loadAttempted = false;

  static bool get isSupported => _program != null || NativeGlass.isSupported;

  static bool get _shaded => _program != null;

  static bool get flipsBackdrop =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  static Future<void> load() async {
    if (_loadAttempted) return;
    _loadAttempted = true;
    if (!AppLiquidGlass.enabled) return;
    if (!ui.ImageFilter.isShaderFilterSupported) return;
    try {
      _program = await ui.FragmentProgram.fromAsset(_asset);
    } catch (_) {
      _program = null;
    }
  }
}

class GlassSurface extends StatelessWidget {
  final bool liquid;
  final BorderRadius borderRadius;
  final Color frostTint;
  final double? frostSigma;
  final GlassRole role;
  final Color? glassTint;
  final BoxBorder? border;
  final BackdropKey? backdropKey;
  final Widget child;

  const GlassSurface({
    super.key,
    this.liquid = false,
    this.borderRadius = BorderRadius.zero,
    required this.frostTint,
    this.frostSigma,
    this.role = GlassRole.panel,
    this.glassTint,
    this.border,
    this.backdropKey,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    if (liquid && LiquidGlass.isSupported) {
      return LiquidGlassSurface(
        borderRadius: borderRadius,
        role: role,
        tint: glassTint,
        backdropKey: backdropKey,
        shadow: borderRadius != BorderRadius.zero,
        child: DecoratedBox(
          decoration: BoxDecoration(border: border),
          child: child,
        ),
      );
    }
    return ClipRRect(
      borderRadius: borderRadius,
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(
          sigmaX: frostSigma ?? AppFrost.sigma,
          sigmaY: frostSigma ?? AppFrost.sigma,
        ),
        backdropGroupKey: backdropKey,
        child: DecoratedBox(
          decoration: BoxDecoration(color: frostTint, border: border),
          child: child,
        ),
      ),
    );
  }
}

class LiquidGlassSurface extends StatelessWidget {
  final BorderRadius borderRadius;
  final GlassRole role;
  final Color? tint;
  final BackdropKey? backdropKey;
  final bool shadow;
  final Widget child;

  const LiquidGlassSurface({
    super.key,
    required this.borderRadius,
    this.role = GlassRole.panel,
    this.tint,
    this.backdropKey,
    this.shadow = true,
    this.child = const SizedBox.expand(),
  });

  static final ui.ColorFilter _frostedSaturation = ui.ColorFilter.matrix(
    _saturationMatrix(AppLiquidGlass.saturation),
  );

  static List<double> _saturationMatrix(double s) {
    final r = 0.213 * (1 - s);
    final g = 0.715 * (1 - s);
    final b = 0.072 * (1 - s);
    return [
      r + s, g, b, 0, 0, //
      r, g + s, b, 0, 0, //
      r, g, b + s, 0, 0, //
      0, 0, 0, 1, 0, //
    ];
  }

  @override
  Widget build(BuildContext context) {
    if (!NativeGlass.isSupported) return _flutterGlass(context);
    return ValueListenableBuilder<bool>(
      valueListenable: NativeGlass.enabled,
      builder: (context, native, _) =>
          native ? _nativeGlass(context) : _flutterGlass(context),
    );
  }

  Widget _nativeGlass(BuildContext context) {
    return Stack(
      fit: StackFit.passthrough,
      children: [
        Positioned.fill(
          child: NativeGlassView(
            params: NativeGlassParams.surface(
              borderRadius: borderRadius,
              brightness: Theme.of(context).brightness,
              role: role,
              tint: tint,
            ),
          ),
        ),
        child,
      ],
    );
  }

  Widget _flutterGlass(BuildContext context) {
    final theme = Theme.of(context);
    final shaded = LiquidGlass._shaded;
    final material = AppLiquidGlass.material(
      theme.colorScheme,
      role,
      glass: theme.extension<ProMaxGlassTheme>(),
      tint: tint,
      frosted: !shaded,
    );
    final key = backdropKey ?? BackdropGroup.of(context)?.backdropKey;
    final rimmed = material.rim.visible
        ? CustomPaint(
            painter: _GlassRimPainter(borderRadius, material.rim),
            child: child,
          )
        : child;
    final Widget glass;
    if (shaded) {
      glass = _LiquidGlassBackdrop(
        borderRadius: borderRadius,
        material: material,
        backdropKey: key,
        devicePixelRatio: MediaQuery.devicePixelRatioOf(context),
        child: rimmed,
      );
    } else {
      final sigma = material.blurSigma;
      glass = ClipRRect(
        borderRadius: borderRadius,
        child: BackdropFilter(
          filter: sigma > 0
              ? ui.ImageFilter.compose(
                  outer: _frostedSaturation,
                  inner: ui.ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
                )
              : _frostedSaturation,
          backdropGroupKey: key,
          child: DecoratedBox(
            decoration: BoxDecoration(color: material.fill),
            child: rimmed,
          ),
        ),
      );
    }
    if (!shadow || !material.shadow.visible) return glass;
    return CustomPaint(
      painter: _GlassShadowPainter(borderRadius, material.shadow),
      child: glass,
    );
  }
}

RRect _shapeOf(BorderRadius radius, Rect rect) => radius.toRRect(rect);

class _GlassShadowPainter extends CustomPainter {
  const _GlassShadowPainter(this.borderRadius, this.shadow);

  final BorderRadius borderRadius;
  final GlassShadow shadow;

  static double _sigmaOfRadius(double radius) => radius * 0.57735 + 0.17;

  @override
  void paint(Canvas canvas, Size size) {
    final bounds = Offset.zero & size;
    final shape = _shapeOf(borderRadius, bounds);
    final outside = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(bounds.inflate(80))
      ..addRRect(shape);
    canvas
      ..save()
      ..clipPath(outside);
    if (shadow.ambient) {
      canvas
        ..drawRRect(
          shape,
          Paint()
            ..color = const Color(0x0B000000)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 15),
        )
        ..drawRRect(
          shape.shift(const Offset(0, 1)),
          Paint()
            ..color = const Color(0x0A000000)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 20),
        );
    }
    if (shadow.contact.a > 0) {
      canvas.drawRRect(
        shape.shift(Offset(0, shadow.contactOffset)),
        Paint()
          ..color = shadow.contact
          ..maskFilter = MaskFilter.blur(
            BlurStyle.normal,
            _sigmaOfRadius(shadow.contactBlur),
          ),
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_GlassShadowPainter oldDelegate) =>
      oldDelegate.borderRadius != borderRadius || oldDelegate.shadow != shadow;
}

class _GlassRimPainter extends CustomPainter {
  const _GlassRimPainter(this.borderRadius, this.rim);

  final BorderRadius borderRadius;
  final GlassRim rim;

  @override
  void paint(Canvas canvas, Size size) {
    final bounds = Offset.zero & size;
    final half = rim.width / 2;
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = rim.width
      ..isAntiAlias = true;
    canvas
      ..save()
      ..clipRRect(_shapeOf(borderRadius, bounds));
    final topReach = math.max(borderRadius.topLeft.y, borderRadius.topRight.y);
    if (rim.top.a > 0 && topReach > 0) {
      canvas
        ..save()
        ..clipRect(
          Rect.fromLTRB(
            -half,
            0,
            size.width + half,
            math.min(topReach * 2, size.height),
          ),
        )
        ..drawRRect(
          _shapeOf(
            borderRadius,
            Rect.fromLTRB(-half, half, size.width + half, size.height + half),
          ),
          stroke..color = rim.top,
        )
        ..restore();
    }
    final bottomReach = math.max(
      borderRadius.bottomLeft.y,
      borderRadius.bottomRight.y,
    );
    if (rim.bottom.a > 0 && bottomReach > 0) {
      canvas
        ..save()
        ..clipRect(
          Rect.fromLTRB(
            -half,
            math.max(size.height - bottomReach * 2, 0),
            size.width + half,
            size.height,
          ),
        )
        ..drawRRect(
          _shapeOf(
            borderRadius,
            Rect.fromLTRB(-half, -half, size.width + half, size.height - half),
          ),
          stroke..color = rim.bottom,
        )
        ..restore();
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_GlassRimPainter oldDelegate) =>
      oldDelegate.borderRadius != borderRadius || oldDelegate.rim != rim;
}

class _LiquidGlassBackdrop extends SingleChildRenderObjectWidget {
  final BorderRadius borderRadius;
  final GlassMaterial material;
  final BackdropKey? backdropKey;
  final double devicePixelRatio;

  const _LiquidGlassBackdrop({
    required this.borderRadius,
    required this.material,
    required this.backdropKey,
    required this.devicePixelRatio,
    required super.child,
  });

  @override
  _RenderLiquidGlass createRenderObject(BuildContext context) =>
      _RenderLiquidGlass(
        borderRadius: borderRadius,
        material: material,
        backdropKey: backdropKey,
        devicePixelRatio: devicePixelRatio,
      );

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderLiquidGlass renderObject,
  ) {
    renderObject
      ..borderRadius = borderRadius
      ..material = material
      ..backdropKey = backdropKey
      ..devicePixelRatio = devicePixelRatio;
  }
}

class _RenderLiquidGlass extends RenderProxyBox {
  _RenderLiquidGlass({
    required BorderRadius borderRadius,
    required GlassMaterial material,
    required BackdropKey? backdropKey,
    required double devicePixelRatio,
  }) : _borderRadius = borderRadius,
       _material = material,
       _backdropKey = backdropKey,
       _devicePixelRatio = devicePixelRatio;

  final LayerHandle<ClipRRectLayer> _clipHandle = LayerHandle<ClipRRectLayer>();
  final LayerHandle<BackdropFilterLayer> _backdropHandle =
      LayerHandle<BackdropFilterLayer>();

  ui.FragmentShader? _shader;

  BorderRadius _borderRadius;
  set borderRadius(BorderRadius value) {
    if (_borderRadius == value) return;
    _borderRadius = value;
    markNeedsPaint();
  }

  GlassMaterial _material;
  set material(GlassMaterial value) {
    if (_material == value) return;
    _material = value;
    markNeedsPaint();
  }

  BackdropKey? _backdropKey;
  set backdropKey(BackdropKey? value) {
    if (_backdropKey == value) return;
    _backdropKey = value;
    markNeedsPaint();
  }

  double _devicePixelRatio;
  set devicePixelRatio(double value) {
    if (_devicePixelRatio == value) return;
    _devicePixelRatio = value;
    markNeedsPaint();
  }

  @override
  bool get alwaysNeedsCompositing => true;

  Matrix4? _observedTransform;
  bool _observing = false;

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _observeTransform();
  }

  @override
  void detach() {
    _observedTransform = null;
    super.detach();
  }

  void _observeTransform() {
    if (_observing) return;
    _observing = true;
    SchedulerBinding.instance.addPostFrameCallback(
      _checkTransform,
      debugLabel: 'LiquidGlass.transform',
    );
  }

  void _checkTransform(Duration _) {
    _observing = false;
    if (!attached) return;
    if (hasSize) {
      final transform = getTransformTo(null);
      final previous = _observedTransform;
      if (previous != null && previous != transform) markNeedsPaint();
      _observedTransform = transform;
    }
    _observeTransform();
  }

  @override
  void dispose() {
    _clipHandle.layer = null;
    _backdropHandle.layer = null;
    _shader?.dispose();
    _shader = null;
    super.dispose();
  }

  ui.ImageFilter? _buildFilter() {
    final program = LiquidGlass._program;
    if (program == null) return null;
    final shader = _shader ??= program.fragmentShader();

    final dpr = _devicePixelRatio;
    final transform = getTransformTo(null);
    final screen = MatrixUtils.transformRect(transform, Offset.zero & size);
    final scaleX = screen.width / size.width;
    final scaleY = screen.height / size.height;
    final cornerScale = math.min(scaleX, scaleY) * dpr;
    final width = screen.width * dpr;
    final height = screen.height * dpr;
    final thickness = _material.thickness <= 0
        ? 0.0
        : math.max(
            math.min(
              _material.thickness * cornerScale,
              math.min(width, height) * AppLiquidGlass.thicknessShare,
            ),
            1.0,
          );
    final fill = _material.fill;
    final maxRadius = math.min(width, height) / 2;
    double corner(Radius radius) => math.min(radius.x * cornerScale, maxRadius);

    shader
      ..setFloat(2, screen.center.dx * dpr)
      ..setFloat(3, screen.center.dy * dpr)
      ..setFloat(4, width / 2)
      ..setFloat(5, height / 2)
      ..setFloat(6, corner(_borderRadius.bottomRight))
      ..setFloat(7, corner(_borderRadius.topRight))
      ..setFloat(8, corner(_borderRadius.bottomLeft))
      ..setFloat(9, corner(_borderRadius.topLeft))
      ..setFloat(10, thickness)
      ..setFloat(11, AppLiquidGlass.refractIndex)
      ..setFloat(12, AppLiquidGlass.refractIntensity)
      ..setFloat(13, _material.chroma)
      ..setFloat(14, AppLiquidGlass.saturation)
      ..setFloat(15, fill.r * fill.a)
      ..setFloat(16, fill.g * fill.a)
      ..setFloat(17, fill.b * fill.a)
      ..setFloat(18, fill.a)
      ..setFloat(19, LiquidGlass.flipsBackdrop ? 1 : 0);

    final refract = ui.ImageFilter.shader(shader);
    final sigma = _material.blurSigma;
    if (sigma <= 0) return refract;
    return ui.ImageFilter.compose(
      outer: refract,
      inner: ui.ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
    );
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final filter = size.isEmpty ? null : _buildFilter();
    if (filter == null) {
      _clipHandle.layer = null;
      _backdropHandle.layer = null;
      super.paint(context, offset);
      return;
    }
    final bounds = Offset.zero & size;
    _clipHandle.layer = context.pushClipRRect(
      needsCompositing,
      offset,
      bounds,
      _borderRadius.toRRect(bounds),
      (PaintingContext innerContext, Offset innerOffset) {
        final backdrop = _backdropHandle.layer ??= BackdropFilterLayer();
        backdrop
          ..filter = filter
          ..backdropKey = _backdropKey;
        innerContext.pushLayer(backdrop, super.paint, innerOffset);
      },
      oldLayer: _clipHandle.layer,
    );
  }
}

class GlassPressEffect extends StatefulWidget {
  const GlassPressEffect({
    super.key,
    required this.borderRadius,
    this.enabled = true,
    this.highlight = true,
    required this.child,
  });

  final BorderRadius borderRadius;
  final bool enabled;
  final bool highlight;
  final Widget child;

  @override
  State<GlassPressEffect> createState() => _GlassPressEffectState();
}

class _SpringChannel {
  _SpringChannel(this.value);

  double value;
  double velocity = 0;
  double _target = 0;
  SpringSimulation? _simulation;
  Duration _start = Duration.zero;

  bool get settled => _simulation == null;

  void retarget(double target, SpringDescription spring, Duration now) {
    if (_simulation == null && value == target) return;
    _target = target;
    _simulation = SpringSimulation(spring, value, target, velocity);
    _start = now;
  }

  void jump(double target) {
    value = target;
    velocity = 0;
    _simulation = null;
  }

  void tick(Duration now) {
    final simulation = _simulation;
    if (simulation == null) return;
    final t = (now - _start).inMicroseconds / Duration.microsecondsPerSecond;
    value = simulation.x(t);
    velocity = simulation.dx(t);
    if (simulation.isDone(t)) {
      value = _target;
      velocity = 0;
      _simulation = null;
    }
  }
}

class _GlassPressEffectState extends State<GlassPressEffect>
    with TickerProviderStateMixin {
  late final Ticker _ticker = createTicker(_onTick);
  late final AnimationController _glow = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 120),
    reverseDuration: const Duration(milliseconds: 220),
  );
  late final CurvedAnimation _glowCurve = CurvedAnimation(
    parent: _glow,
    curve: Curves.easeOut,
    reverseCurve: Curves.easeInOut,
  );

  final _scaleX = _SpringChannel(1);
  final _scaleY = _SpringChannel(1);
  final _shiftX = _SpringChannel(0);
  final _shiftY = _SpringChannel(0);

  int? _pointer;
  Offset _origin = Offset.zero;
  Offset _stretch = Offset.zero;
  Offset _touch = Offset.zero;
  Size _size = Size.zero;
  Duration _now = Duration.zero;

  List<_SpringChannel> get _channels => [_scaleX, _scaleY, _shiftX, _shiftY];

  @override
  void dispose() {
    _ticker.dispose();
    _glowCurve.dispose();
    _glow.dispose();
    super.dispose();
  }

  void _onTick(Duration elapsed) {
    _now = elapsed;
    for (final channel in _channels) {
      channel.tick(elapsed);
    }
    if (_channels.every((channel) => channel.settled)) _ticker.stop();
    setState(() {});
  }

  void _apply(SpringDescription spring) {
    final tracking = _pointer != null;
    final w = math.max(1.0, _size.width);
    final h = math.max(1.0, _size.height);
    final aspect = w / h;
    final base = tracking
        ? 1 + AppLiquidGlass.pressedSizeIncrease / math.max(w, h)
        : 1.0;
    var sx = base;
    var sy = base;
    var tx = 0.0;
    var ty = 0.0;
    final adjustedX = _stretch.dx / aspect;
    final length = math.sqrt(adjustedX * adjustedX + _stretch.dy * _stretch.dy);
    if (tracking && length != 0) {
      final nx = adjustedX / length;
      final ny = _stretch.dy / length;
      final k = -1 / ((length / h) / (5 * aspect) + 1) + 1;
      final additionalMaxScale = (h + 16 / aspect) / h - 1;
      final t = additionalMaxScale * k * aspect;
      if (nx.abs() > ny.abs()) {
        final diff = nx.abs() - ny.abs();
        sx = base * (1 + t * diff);
        sy = base / (1 + t * diff);
      } else {
        final diff = ny.abs() - nx.abs();
        sx = base / (1 + t * diff);
        sy = base * (1 + t * diff);
      }
      tx = nx * AppLiquidGlass.stretchOffset * k;
      ty = ny * AppLiquidGlass.stretchOffset * k;
    }
    final now = _ticker.isActive ? _now : Duration.zero;
    if (!_ticker.isActive) _now = Duration.zero;
    _scaleX.retarget(sx, spring, now);
    _scaleY.retarget(sy, spring, now);
    _shiftX.retarget(tx, spring, now);
    _shiftY.retarget(ty, spring, now);
    if (!_ticker.isActive && !_channels.every((c) => c.settled)) {
      _ticker.start();
    }
  }

  void _down(PointerDownEvent event) {
    if (!widget.enabled || _pointer != null) return;
    if (MediaQuery.disableAnimationsOf(context)) return;
    _pointer = event.pointer;
    _size = context.size ?? Size.zero;
    _origin = event.localPosition;
    _touch = event.localPosition;
    _stretch = Offset.zero;
    _apply(AppLiquidGlass.liftOn);
    if (widget.highlight) _glow.forward();
    setState(() {});
  }

  void _move(PointerMoveEvent event) {
    if (event.pointer != _pointer) return;
    _touch = event.localPosition;
    _stretch = event.localPosition - _origin;
    _apply(AppLiquidGlass.liftOff);
    setState(() {});
  }

  void _up(PointerEvent event) {
    if (event.pointer != _pointer) return;
    _pointer = null;
    _stretch = Offset.zero;
    _apply(AppLiquidGlass.liftOff);
    _glow.reverse();
  }

  @override
  void didUpdateWidget(GlassPressEffect oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.enabled && _pointer != null) {
      _pointer = null;
      for (final channel in _channels) {
        channel.jump(channel == _scaleX || channel == _scaleY ? 1 : 0);
      }
      _ticker.stop();
      _glow.value = 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    final transform = Matrix4.identity()
      ..setEntry(0, 0, _scaleX.value)
      ..setEntry(1, 1, _scaleY.value)
      ..setEntry(0, 3, _shiftX.value)
      ..setEntry(1, 3, _shiftY.value);
    Widget content = widget.child;
    if (widget.highlight) {
      content = Stack(
        fit: StackFit.passthrough,
        children: [
          content,
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(
                painter: _GlassHighlightPainter(
                  borderRadius: widget.borderRadius,
                  opacity: _glowCurve,
                  center: _touch,
                ),
              ),
            ),
          ),
        ],
      );
    }
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: _down,
      onPointerMove: _move,
      onPointerUp: _up,
      onPointerCancel: _up,
      child: Transform(
        alignment: Alignment.center,
        transform: transform,
        child: content,
      ),
    );
  }
}

class _GlassHighlightPainter extends CustomPainter {
  _GlassHighlightPainter({
    required this.borderRadius,
    required this.opacity,
    required this.center,
  }) : super(repaint: opacity);

  final BorderRadius borderRadius;
  final Animation<double> opacity;
  final Offset center;

  static const double _base = 0.5;
  static final List<double> _stops = [
    0.0,
    for (var i = 0; i < 7; i++) 0.5 + 0.5 * i / 6,
  ];
  static final List<double> _alphas = [
    1.0,
    for (var i = 0; i < 7; i++) _base * (1 - _easeInOut.transform(i / 6)),
  ];
  static const Cubic _easeInOut = Cubic(0.42, 0, 0.58, 1);

  @override
  void paint(Canvas canvas, Size size) {
    final strength = opacity.value * AppLiquidGlass.highlightOpacity;
    if (strength <= 0) return;
    final bounds = Offset.zero & size;
    final gradient = ui.Gradient.radial(
      center,
      AppLiquidGlass.highlightRadius,
      [
        for (final alpha in _alphas)
          Colors.white.withValues(alpha: alpha * strength),
      ],
      _stops,
    );
    canvas
      ..save()
      ..clipRRect(borderRadius.toRRect(bounds))
      ..drawRect(bounds, Paint()..shader = gradient)
      ..restore();
  }

  @override
  bool shouldRepaint(_GlassHighlightPainter oldDelegate) =>
      oldDelegate.center != center ||
      oldDelegate.borderRadius != borderRadius ||
      oldDelegate.opacity != opacity;
}
