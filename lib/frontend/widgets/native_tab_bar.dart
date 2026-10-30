import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/config/app_native_glass.dart';
import '../../core/config/app_visual_style.dart';

abstract final class NativeTabBarPolicy {
  static bool shouldUse({
    required bool nativeActive,
    required VisualStyle visualStyle,
  }) {
    return nativeActive && visualStyle != VisualStyle.materialYou;
  }

  static bool get current => shouldUse(
    nativeActive: NativeGlass.active,
    visualStyle: AppVisualStyle.current.value,
  );

  static Listenable get listenable =>
      Listenable.merge([NativeGlass.enabled, AppVisualStyle.current]);
}

@immutable
class NativeTabItem {
  const NativeTabItem({
    required this.title,
    required this.symbol,
    required this.selectedSymbol,
    this.badge,
    this.avatarKey,
    this.avatar,
  });

  final String title;
  final String symbol;
  final String selectedSymbol;
  final String? badge;
  final String? avatarKey;
  final Uint8List? avatar;

  bool get hasAvatar => avatarKey != null && avatar != null;

  Map<String, Object?> toMap({required bool withAvatar}) => {
    'title': title,
    'symbol': symbol,
    'selectedSymbol': selectedSymbol,
    'badge': badge,
    'avatarKey': hasAvatar ? avatarKey : null,
    if (withAvatar && hasAvatar) 'avatar': avatar,
  };

  @override
  bool operator ==(Object other) =>
      other is NativeTabItem &&
      other.title == title &&
      other.symbol == symbol &&
      other.selectedSymbol == selectedSymbol &&
      other.badge == badge &&
      other.avatarKey == avatarKey &&
      other.hasAvatar == hasAvatar;

  @override
  int get hashCode =>
      Object.hash(title, symbol, selectedSymbol, badge, avatarKey, hasAvatar);
}

@immutable
class NativeTabBarConfig {
  const NativeTabBarConfig({
    required this.items,
    required this.selectedIndex,
    required this.dark,
    required this.tint,
  });

  final List<NativeTabItem> items;
  final int selectedIndex;
  final bool dark;
  final Color tint;

  NativeTabBarConfig withSelected(int index) => NativeTabBarConfig(
    items: items,
    selectedIndex: index,
    dark: dark,
    tint: tint,
  );

  Map<String, Object?> _style() => {'dark': dark, 'tint': tint.toARGB32()};

  Map<String, Object?> creationParams() => {
    ..._style(),
    'items': [for (final item in items) item.toMap(withAvatar: true)],
    'selectedIndex': selectedIndex,
  };

  List<MethodCall> updatesFrom(NativeTabBarConfig previous) {
    final calls = <MethodCall>[];
    if (previous.dark != dark || previous.tint != tint) {
      calls.add(MethodCall('setStyle', _style()));
    }
    if (!listEquals(previous.items, items)) {
      calls.add(
        MethodCall('setItems', {
          'items': [
            for (var i = 0; i < items.length; i++)
              items[i].toMap(
                withAvatar:
                    i >= previous.items.length ||
                    previous.items[i].avatarKey != items[i].avatarKey ||
                    !previous.items[i].hasAvatar,
              ),
          ],
          'selectedIndex': selectedIndex,
        }),
      );
    } else if (previous.selectedIndex != selectedIndex) {
      calls.add(MethodCall('select', {'index': selectedIndex}));
    }
    return calls;
  }

  int? acceptSelection(Object? arguments) {
    if (arguments is! Map) return null;
    final index = arguments['index'];
    if (index is! int || index < 0 || index >= items.length) return null;
    return index;
  }
}

class NativeTabBar extends StatefulWidget {
  const NativeTabBar({
    super.key,
    required this.items,
    required this.selectedIndex,
    required this.onSelected,
    this.onLongPress,
  });

  static const double fallbackHeight = 62;

  final List<NativeTabItem> items;
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final void Function(int index, Offset globalPosition)? onLongPress;

  @override
  State<NativeTabBar> createState() => _NativeTabBarState();
}

class _NativeTabBarState extends State<NativeTabBar> {
  static const double _minHeight = 44;
  static const double _maxHeight = 110;

  static final Set<Factory<OneSequenceGestureRecognizer>> _gestures = {
    Factory<OneSequenceGestureRecognizer>(EagerGestureRecognizer.new),
  };

  MethodChannel? _channel;
  NativeTabBarConfig? _creation;
  NativeTabBarConfig? _synced;
  double _height = NativeTabBar.fallbackHeight;

  NativeTabBarConfig _configFor(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return NativeTabBarConfig(
      items: widget.items,
      selectedIndex: widget.selectedIndex,
      dark: cs.brightness == Brightness.dark,
      tint: cs.primary,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _creation ??= _configFor(context);
    _sync();
  }

  @override
  void didUpdateWidget(NativeTabBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  @override
  void dispose() {
    _channel?.setMethodCallHandler(null);
    _channel = null;
    super.dispose();
  }

  void _created(int id) {
    if (!mounted) return;
    final channel = MethodChannel('${NativeGlass.tabBarViewType}/$id');
    channel.setMethodCallHandler(_onNativeCall);
    _channel = channel;
    _synced = _creation;
    _sync();
    _measure(channel);
  }

  Future<void> _measure(MethodChannel channel) async {
    final height = await _invoke<double>(channel, 'intrinsicHeight');
    if (!mounted || height == null || height <= 0) return;
    final clamped = height.clamp(_minHeight, _maxHeight).toDouble();
    if (clamped != _height) setState(() => _height = clamped);
  }

  void _sync() {
    final channel = _channel;
    final synced = _synced;
    if (channel == null || synced == null) return;
    final next = _configFor(context);
    final calls = next.updatesFrom(synced);
    _synced = next;
    for (final call in calls) {
      _invoke<void>(channel, call.method, call.arguments);
    }
  }

  Future<T?> _invoke<T>(
    MethodChannel channel,
    String method, [
    Object? arguments,
  ]) async {
    try {
      return await channel.invokeMethod<T>(method, arguments);
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  Future<void> _onNativeCall(MethodCall call) async {
    final synced = _synced;
    if (!mounted || synced == null) return;
    switch (call.method) {
      case 'selected':
        final index = synced.acceptSelection(call.arguments);
        if (index == null) return;
        _synced = synced.withSelected(index);
        if (index != widget.selectedIndex) widget.onSelected(index);
      case 'longPress':
        final index = synced.acceptSelection(call.arguments);
        final onLongPress = widget.onLongPress;
        final args = call.arguments;
        if (index == null || onLongPress == null || args is! Map) return;
        final box = context.findRenderObject();
        if (box is! RenderBox || !box.hasSize) return;
        final local = Offset(
          (args['x'] as num?)?.toDouble() ?? 0,
          (args['y'] as num?)?.toDouble() ?? 0,
        );
        onLongPress(index, box.localToGlobal(local));
    }
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: _height,
      child: UiKitView(
        viewType: NativeGlass.tabBarViewType,
        creationParams: _creation?.creationParams(),
        creationParamsCodec: const StandardMessageCodec(),
        gestureRecognizers: _gestures,
        onPlatformViewCreated: _created,
      ),
    );
  }
}
