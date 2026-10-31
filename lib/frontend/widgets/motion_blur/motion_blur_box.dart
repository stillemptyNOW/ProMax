import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import '../../../core/plugins/motion_blur/motion_blur_curve.dart';
import '../../../core/plugins/motion_blur/motion_blur_plugin.dart';
import '../../../core/plugins/motion_blur/motion_blur_settings.dart';

class MotionBlurBox extends StatefulWidget {
  const MotionBlurBox({
    super.key,
    required this.target,
    this.motion = const [],
    this.position,
    this.preview = false,
    this.bounded = true,
    required this.child,
  }) : _scroll = false;

  const MotionBlurBox.scroll({
    super.key,
    this.preview = false,
    required this.child,
  }) : target = MotionBlurTarget.scrolling,
       motion = const [],
       position = null,
       bounded = true,
       _scroll = true;

  final MotionBlurTarget target;
  final List<Listenable> motion;
  final ValueGetter<Offset>? position;
  final bool preview;
  final bool bounded;
  final Widget child;
  final bool _scroll;

  @override
  State<MotionBlurBox> createState() => _MotionBlurBoxState();
}

class _MotionBlurBoxState extends State<MotionBlurBox>
    with SingleTickerProviderStateMixin {
  static const int _idleTicksBeforeRest = 2;

  final MotionBlurSignal _signal = MotionBlurSignal();
  final MotionBlurVelocity _velocity = MotionBlurVelocity();
  Ticker? _ticker;
  Duration _lastTick = Duration.zero;
  bool _freshStart = true;
  Offset _pending = Offset.zero;
  Offset? _lastPosition;
  int _idleTicks = 0;
  int _exclusions = 0;
  _MotionBlurBoxState? _parent;
  late MotionBlurTarget _target = widget.target;
  bool _reduceMotion = false;
  double _devicePixelRatio = 1;
  double _frameSeconds = 1 / 60;

  MotionBlurPlugin get _plugin => MotionBlurPlugin.instance;

  bool get _tracksPosition => !widget._scroll;

  bool get _canBlur =>
      !_reduceMotion &&
      _exclusions == 0 &&
      (widget.preview ? true : _plugin.allows(_target));

  @override
  void initState() {
    super.initState();
    _attachToParent();
    _listen(widget.motion);
  }

  @override
  void activate() {
    super.activate();
    _attachToParent();
  }

  @override
  void deactivate() {
    _parent?._exclude(-_exclusions);
    _parent = null;
    super.deactivate();
  }

  void _attachToParent() {
    _parent = context.getInheritedWidgetOfExactType<_MotionBlurScope>()?.host;
    _parent?._exclude(_exclusions);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    _devicePixelRatio = MediaQuery.maybeDevicePixelRatioOf(context) ?? 1;
    final refreshRate = View.maybeOf(context)?.display.refreshRate ?? 0;
    _frameSeconds = refreshRate >= 30 ? 1 / refreshRate : 1 / 60;
    if (!_canBlur) _settle();
  }

  @override
  void didUpdateWidget(MotionBlurBox oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!listEquals(oldWidget.motion, widget.motion)) {
      _unlisten(oldWidget.motion);
      _listen(widget.motion);
    }
    _target = widget._scroll ? _target : widget.target;
    if (_tracksPosition) _wake();
  }

  @override
  void dispose() {
    _unlisten(widget.motion);
    _ticker?.dispose();
    _signal.dispose();
    super.dispose();
  }

  void _listen(List<Listenable> motion) {
    for (final listenable in motion) {
      listenable.addListener(_wake);
    }
  }

  void _unlisten(List<Listenable> motion) {
    for (final listenable in motion) {
      listenable.removeListener(_wake);
    }
  }

  void _exclude(int delta) {
    if (delta == 0) return;
    _exclusions += delta;
    _parent?._exclude(delta);
    if (_exclusions > 0) _settle();
  }

  bool _onScroll(ScrollUpdateNotification notification) {
    if (notification.depth != 0) return false;
    final delta = notification.scrollDelta ?? 0;
    if (delta == 0) return false;
    _target = notification.metrics is PageMetrics
        ? MotionBlurTarget.pages
        : MotionBlurTarget.scrolling;
    if (!_canBlur) return false;
    _pending += notification.metrics.axis == Axis.vertical
        ? Offset(0, delta)
        : Offset(delta, 0);
    _wake();
    return false;
  }

  void _wake() {
    if (!mounted || !_canBlur) return;
    final ticker = _ticker ??= createTicker(_tick);
    if (ticker.isActive) return;
    _freshStart = true;
    _idleTicks = 0;
    ticker.start();
  }

  void _tick(Duration elapsed) {
    final seconds = _freshStart
        ? _frameSeconds
        : (elapsed - _lastTick).inMicroseconds / Duration.microsecondsPerSecond;
    _lastTick = elapsed;
    _freshStart = false;
    if (!_canBlur) {
      _settle();
      return;
    }
    var displacement = _pending;
    _pending = Offset.zero;
    if (_tracksPosition) {
      final position = _samplePosition();
      final last = _lastPosition;
      if (position != null && last != null) displacement += position - last;
      _lastPosition = position;
    }
    final velocity = _velocity.update(displacement, seconds);
    final settings = _plugin.settings.value;
    final budget = _plugin.budget;
    final streak = MotionBlurCurve.streak(velocity, settings, budget: budget);
    _idleTicks = displacement == Offset.zero ? _idleTicks + 1 : 0;
    if (streak == Offset.zero && _idleTicks >= _idleTicksBeforeRest) {
      _settle();
      return;
    }
    _signal.update(
      streak,
      MotionBlurCurve.taps(
        streak.distance * _devicePixelRatio,
        settings.quality,
        budget: budget,
      ),
    );
  }

  Offset? _samplePosition() {
    final sampler = widget.position;
    if (sampler != null) return sampler();
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) return null;
    return MatrixUtils.transformPoint(
      box.getTransformTo(null),
      box.size.center(Offset.zero),
    );
  }

  void _settle() {
    _ticker?.stop();
    _velocity.reset();
    _pending = Offset.zero;
    _lastPosition = null;
    _idleTicks = 0;
    _signal.clear();
  }

  @override
  Widget build(BuildContext context) {
    final Widget layer = _MotionBlurLayer(
      signal: _signal,
      devicePixelRatio: _devicePixelRatio,
      bounded: widget.bounded,
      child: widget.child,
    );
    return _MotionBlurScope(
      host: this,
      child: widget._scroll
          ? NotificationListener<ScrollUpdateNotification>(
              onNotification: _onScroll,
              child: layer,
            )
          : layer,
    );
  }
}

class _MotionBlurScope extends InheritedWidget {
  const _MotionBlurScope({required this.host, required super.child});

  final _MotionBlurBoxState host;

  @override
  bool updateShouldNotify(_MotionBlurScope oldWidget) => false;
}

class MotionBlurExclusion extends StatefulWidget {
  const MotionBlurExclusion({super.key, required this.child});

  final Widget child;

  @override
  State<MotionBlurExclusion> createState() => _MotionBlurExclusionState();
}

class _MotionBlurExclusionState extends State<MotionBlurExclusion> {
  _MotionBlurBoxState? _host;

  @override
  void initState() {
    super.initState();
    _attach();
  }

  @override
  void activate() {
    super.activate();
    _attach();
  }

  @override
  void deactivate() {
    _host?._exclude(-1);
    _host = null;
    super.deactivate();
  }

  void _attach() {
    _host = context.getInheritedWidgetOfExactType<_MotionBlurScope>()?.host;
    _host?._exclude(1);
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class MotionBlurSignal extends ChangeNotifier {
  static const double _streakEpsilon = 0.05;

  Offset _streak = Offset.zero;
  int _taps = 0;

  Offset get streak => _streak;

  int get taps => _taps;

  bool get blurring => _streak != Offset.zero;

  void update(Offset streak, int taps) {
    if (streak != Offset.zero &&
        taps == _taps &&
        (streak - _streak).distance < _streakEpsilon) {
      return;
    }
    if (streak == _streak && taps == _taps) return;
    _streak = streak;
    _taps = taps;
    notifyListeners();
  }

  void clear() => update(Offset.zero, 0);
}

class _MotionBlurLayer extends SingleChildRenderObjectWidget {
  const _MotionBlurLayer({
    required this.signal,
    required this.devicePixelRatio,
    required this.bounded,
    super.child,
  });

  final MotionBlurSignal signal;
  final double devicePixelRatio;
  final bool bounded;

  @override
  RenderMotionBlur createRenderObject(BuildContext context) => RenderMotionBlur(
    signal: signal,
    devicePixelRatio: devicePixelRatio,
    bounded: bounded,
  );

  @override
  void updateRenderObject(BuildContext context, RenderMotionBlur renderObject) {
    renderObject
      ..signal = signal
      ..devicePixelRatio = devicePixelRatio
      ..bounded = bounded;
  }
}

class RenderMotionBlur extends RenderProxyBox {
  RenderMotionBlur({
    required MotionBlurSignal signal,
    required double devicePixelRatio,
    bool bounded = true,
  }) : _signal = signal,
       _devicePixelRatio = devicePixelRatio,
       _bounded = bounded;

  final LayerHandle<ClipRectLayer> _clipHandle = LayerHandle<ClipRectLayer>();
  final LayerHandle<ImageFilterLayer> _filterHandle =
      LayerHandle<ImageFilterLayer>();
  late final PaintingContextCallback _paintFiltered = _paintFilteredChild;
  late final PaintingContextCallback _paintPlain = _paintPlainChild;
  ui.FragmentShader? _shader;
  ui.FragmentProgram? _shaderProgram;
  ui.ImageFilter? _filter;
  bool _wasBlurring = false;

  MotionBlurSignal get signal => _signal;
  MotionBlurSignal _signal;
  set signal(MotionBlurSignal value) {
    if (identical(value, _signal)) return;
    if (attached) _signal.removeListener(_signalChanged);
    _signal = value;
    if (attached) _signal.addListener(_signalChanged);
    _signalChanged();
  }

  double get devicePixelRatio => _devicePixelRatio;
  double _devicePixelRatio;
  set devicePixelRatio(double value) {
    if (value == _devicePixelRatio) return;
    _devicePixelRatio = value;
    _filter = null;
    if (_signal.blurring) markNeedsPaint();
  }

  bool get bounded => _bounded;
  bool _bounded;
  set bounded(bool value) {
    if (value == _bounded) return;
    _bounded = value;
    _filter = null;
    if (_signal.blurring) markNeedsPaint();
  }

  bool get isBlurring => _signal.blurring;

  @visibleForTesting
  ui.ImageFilter? get debugFilter => isBlurring ? _filter : null;

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _signal.addListener(_signalChanged);
    _wasBlurring = _signal.blurring;
  }

  @override
  void detach() {
    _signal.removeListener(_signalChanged);
    super.detach();
  }

  @override
  void dispose() {
    _clipHandle.layer = null;
    _filterHandle.layer = null;
    _shader?.dispose();
    _shader = null;
    super.dispose();
  }

  void _signalChanged() {
    final blurring = _signal.blurring;
    if (blurring != _wasBlurring) {
      _wasBlurring = blurring;
      markNeedsCompositingBitsUpdate();
    }
    _filter = null;
    markNeedsPaint();
  }

  @override
  bool get alwaysNeedsCompositing => child != null && _signal.blurring;

  @override
  void paint(PaintingContext context, Offset offset) {
    final child = this.child;
    if (child == null) return;
    if (!_signal.blurring) {
      _clipHandle.layer = null;
      _filterHandle.layer = null;
      context.paintChild(child, offset);
      return;
    }
    _filter ??= _buildFilter();
    if (!_bounded) {
      _clipHandle.layer = null;
      _paintFilteredChild(context, offset);
      return;
    }
    _clipHandle.layer = context.pushClipRect(
      needsCompositing,
      offset,
      Offset.zero & size,
      _paintFiltered,
      oldLayer: _clipHandle.layer,
    );
  }

  void _paintFilteredChild(PaintingContext context, Offset offset) {
    final layer = _filterHandle.layer ??= ImageFilterLayer();
    layer.imageFilter = _filter;
    context.pushLayer(layer, _paintPlain, offset);
  }

  void _paintPlainChild(PaintingContext context, Offset offset) {
    context.paintChild(child!, offset);
  }

  ui.ImageFilter _buildFilter() {
    final streak = _signal.streak;
    final program = _bounded ? MotionBlurPlugin.instance.program : null;
    if (program != null) {
      if (!identical(program, _shaderProgram)) {
        _shader?.dispose();
        _shader = program.fragmentShader();
        _shaderProgram = program;
      }
      final physical = streak * _devicePixelRatio;
      _shader!
        ..setFloat(2, physical.dx)
        ..setFloat(3, physical.dy)
        ..setFloat(4, _signal.taps.toDouble());
      return ui.ImageFilter.shader(_shader!);
    }
    return ui.ImageFilter.blur(
      sigmaX: MotionBlurCurve.gaussianSigma(streak.dx.abs()),
      sigmaY: MotionBlurCurve.gaussianSigma(streak.dy.abs()),
      tileMode: _bounded ? TileMode.clamp : TileMode.decal,
    );
  }
}
