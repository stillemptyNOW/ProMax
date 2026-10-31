import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import '../../core/config/app_liquid_glass.dart';
import '../../core/config/app_native_glass.dart';
import 'motion_blur/motion_blur_box.dart';

@immutable
class NativeGlassParams {
  const NativeGlassParams({
    required this.topLeft,
    required this.topRight,
    required this.bottomLeft,
    required this.bottomRight,
    required this.dark,
    this.tint,
    this.clear = false,
  });

  factory NativeGlassParams.surface({
    required BorderRadius borderRadius,
    required Brightness brightness,
    GlassRole role = GlassRole.panel,
    Color? tint,
  }) {
    final dark = brightness == Brightness.dark;
    final overlay = role == GlassRole.overlay;
    return NativeGlassParams(
      topLeft: borderRadius.topLeft.x,
      topRight: borderRadius.topRight.x,
      bottomLeft: borderRadius.bottomLeft.x,
      bottomRight: borderRadius.bottomRight.x,
      dark: dark,
      clear: overlay,
      tint: tint != null && tint.a > 0 ? tint : _defaultTint(dark, overlay),
    );
  }

  static Color? _defaultTint(bool dark, bool overlay) {
    if (overlay) return dark ? const Color(0x47000000) : null;
    return dark ? const Color(0x06FFFFFF) : const Color(0x1AFFFFFF);
  }

  final double topLeft;
  final double topRight;
  final double bottomLeft;
  final double bottomRight;
  final bool dark;
  final Color? tint;
  final bool clear;

  Map<String, Object?> toMap() => {
    'radii': <double>[topLeft, topRight, bottomLeft, bottomRight],
    'dark': dark,
    'style': clear ? 'clear' : 'regular',
    'tint': tint?.toARGB32(),
  };

  @override
  bool operator ==(Object other) =>
      other is NativeGlassParams &&
      other.topLeft == topLeft &&
      other.topRight == topRight &&
      other.bottomLeft == bottomLeft &&
      other.bottomRight == bottomRight &&
      other.dark == dark &&
      other.tint == tint &&
      other.clear == clear;

  @override
  int get hashCode => Object.hash(
    topLeft,
    topRight,
    bottomLeft,
    bottomRight,
    dark,
    tint,
    clear,
  );
}

class NativeGlassView extends StatefulWidget {
  const NativeGlassView({super.key, required this.params, this.onCreated});

  final NativeGlassParams params;
  final VoidCallback? onCreated;

  @override
  State<NativeGlassView> createState() => _NativeGlassViewState();
}

class _NativeGlassViewState extends State<NativeGlassView> {
  late final NativeGlassParams _creationParams = widget.params;
  MethodChannel? _channel;
  NativeGlassParams? _applied;

  @override
  void didUpdateWidget(NativeGlassView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.params != widget.params) _push();
  }

  @override
  void dispose() {
    _channel = null;
    super.dispose();
  }

  void _created(int id) {
    if (!mounted) return;
    _channel = MethodChannel('${NativeGlass.glassViewType}/$id');
    _applied = _creationParams;
    _push();
    widget.onCreated?.call();
  }

  Future<void> _push() async {
    final channel = _channel;
    final params = widget.params;
    if (channel == null || _applied == params) return;
    _applied = params;
    try {
      await channel.invokeMethod<void>('update', params.toMap());
    } on PlatformException {
      _applied = null;
    } on MissingPluginException {
      _applied = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return MotionBlurExclusion(
      child: IgnorePointer(
        child: UiKitView(
          viewType: NativeGlass.glassViewType,
          creationParams: _creationParams.toMap(),
          creationParamsCodec: const StandardMessageCodec(),
          hitTestBehavior: PlatformViewHitTestBehavior.transparent,
          onPlatformViewCreated: _created,
        ),
      ),
    );
  }
}
