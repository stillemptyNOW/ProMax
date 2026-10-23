import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';

import '../../../l10n/app_localizations.dart';
import '../../widgets/native_tab_bar.dart';

class NativeMainTabBar extends StatefulWidget {
  const NativeMainTabBar({
    super.key,
    required this.selectedIndex,
    required this.onSelected,
    this.chatsBadge,
    this.avatarUrl,
    this.onLongPress,
  });

  static const int settingsIndex = 3;

  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final String? chatsBadge;
  final String? avatarUrl;
  final void Function(int index, Offset globalPosition)? onLongPress;

  static String? unreadBadge(int count) {
    if (count <= 0) return null;
    return count > 99 ? '99+' : '$count';
  }

  static List<NativeTabItem> itemsFor(
    AppLocalizations l10n, {
    String? chatsBadge,
    String? avatarKey,
    Uint8List? avatar,
  }) => [
    NativeTabItem(
      title: l10n.chatListNavChats,
      symbol: 'bubble.left.and.bubble.right',
      selectedSymbol: 'bubble.left.and.bubble.right.fill',
      badge: chatsBadge,
    ),
    NativeTabItem(
      title: l10n.chatListNavCalls,
      symbol: 'phone',
      selectedSymbol: 'phone.fill',
    ),
    NativeTabItem(
      title: l10n.chatListNavContacts,
      symbol: 'person.crop.circle',
      selectedSymbol: 'person.crop.circle.fill',
    ),
    NativeTabItem(
      title: l10n.attachSheetSettings,
      symbol: 'gearshape',
      selectedSymbol: 'gearshape.fill',
      avatarKey: avatar == null ? null : avatarKey,
      avatar: avatar,
    ),
  ];

  @override
  State<NativeMainTabBar> createState() => _NativeMainTabBarState();
}

class _NativeMainTabBarState extends State<NativeMainTabBar> {
  static const int _maxAvatarBytes = 4 * 1024 * 1024;

  String? _avatarKey;
  Uint8List? _avatar;
  int _avatarRequest = 0;

  @override
  void initState() {
    super.initState();
    _loadAvatar(widget.avatarUrl);
  }

  @override
  void didUpdateWidget(NativeMainTabBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.avatarUrl != widget.avatarUrl) _loadAvatar(widget.avatarUrl);
  }

  Future<void> _loadAvatar(String? url) async {
    final request = ++_avatarRequest;
    if (url == null || url.isEmpty) {
      if (_avatar != null) {
        setState(() {
          _avatar = null;
          _avatarKey = null;
        });
      }
      return;
    }
    Uint8List? bytes;
    try {
      final file = await DefaultCacheManager().getSingleFile(url);
      if (await file.length() <= _maxAvatarBytes) {
        bytes = await file.readAsBytes();
      }
    } catch (_) {
      bytes = null;
    }
    if (!mounted || request != _avatarRequest) return;
    setState(() {
      _avatar = bytes;
      _avatarKey = bytes == null ? null : url;
    });
  }

  @override
  Widget build(BuildContext context) {
    return NativeTabBar(
      items: NativeMainTabBar.itemsFor(
        AppLocalizations.of(context)!,
        chatsBadge: widget.chatsBadge,
        avatarKey: _avatarKey,
        avatar: _avatar,
      ),
      selectedIndex: widget.selectedIndex,
      onSelected: widget.onSelected,
      onLongPress: widget.onLongPress,
    );
  }
}
