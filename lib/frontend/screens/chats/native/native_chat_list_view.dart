import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/config/native_ios_ui.dart';
import '../../../widgets/motion_blur/motion_blur_box.dart';
import 'native_chat_list_bridge.dart';

class NativeChatListStrings {
  const NativeChatListStrings({
    required this.pin,
    required this.unpin,
    required this.mute,
    required this.unmute,
    required this.archive,
    required this.delete,
    required this.select,
    required this.search,
    required this.empty,
    required this.draft,
  });

  final String pin;
  final String unpin;
  final String mute;
  final String unmute;
  final String archive;
  final String delete;
  final String select;
  final String search;
  final String empty;
  final String draft;

  Map<String, Object?> toJson() => {
    'pin': pin,
    'unpin': unpin,
    'mute': mute,
    'unmute': unmute,
    'archive': archive,
    'delete': delete,
    'select': select,
    'search': search,
    'empty': empty,
    'draft': draft,
  };
}

NativeChatListTheme nativeChatListThemeOf(ColorScheme cs) =>
    NativeChatListTheme(
      dark: cs.brightness == Brightness.dark,
      primary: cs.primary.toARGB32(),
      surface: cs.surface.toARGB32(),
      onSurface: cs.onSurface.toARGB32(),
      onSurfaceVariant: cs.onSurfaceVariant.toARGB32(),
      outline: cs.outlineVariant.toARGB32(),
    );

class NativeChatListView extends StatefulWidget {
  const NativeChatListView({
    super.key,
    required this.rows,
    required this.selecting,
    required this.handlers,
    required this.theme,
    required this.strings,
    required this.topInset,
    required this.bottomInset,
  });

  final List<NativeChatRow> rows;
  final bool selecting;
  final NativeChatListHandlers handlers;
  final NativeChatListTheme theme;
  final NativeChatListStrings strings;
  final double topInset;
  final double bottomInset;

  @override
  State<NativeChatListView> createState() => _NativeChatListViewState();
}

class _NativeChatListViewState extends State<NativeChatListView> {
  NativeChatListBridge? _bridge;

  @override
  void didUpdateWidget(NativeChatListView oldWidget) {
    super.didUpdateWidget(oldWidget);
    final bridge = _bridge;
    if (bridge == null) return;
    if (oldWidget.theme != widget.theme) bridge.setTheme(widget.theme);
    if (oldWidget.topInset != widget.topInset ||
        oldWidget.bottomInset != widget.bottomInset) {
      bridge.setInsets(top: widget.topInset, bottom: widget.bottomInset);
    }
    bridge.sync(widget.rows, selecting: widget.selecting);
  }

  @override
  void dispose() {
    _bridge?.dispose();
    super.dispose();
  }

  void _onCreated(int viewId) {
    final bridge = NativeChatListBridge(
      channel: MethodChannel('${NativeIosUi.chatListViewType}/$viewId'),
      handlers: widget.handlers,
      onReady: _resync,
    );
    _bridge = bridge;
    _resync();
  }

  void _resync() {
    final bridge = _bridge;
    if (bridge == null || !mounted) return;
    bridge.setTheme(widget.theme);
    bridge.setInsets(top: widget.topInset, bottom: widget.bottomInset);
    bridge.sync(widget.rows, selecting: widget.selecting);
  }

  @override
  Widget build(BuildContext context) {
    return MotionBlurExclusion(
      child: UiKitView(
        viewType: NativeIosUi.chatListViewType,
        layoutDirection: Directionality.of(context),
        creationParams: <String, Object?>{
          'theme': widget.theme.toJson(),
          'strings': widget.strings.toJson(),
          'top': widget.topInset,
          'bottom': widget.bottomInset,
        },
        creationParamsCodec: const StandardMessageCodec(),
        onPlatformViewCreated: _onCreated,
      ),
    );
  }
}
