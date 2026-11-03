import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../../../core/utils/logger.dart';

@immutable
class NativeChatRow {
  const NativeChatRow({
    required this.id,
    required this.title,
    required this.preview,
    required this.time,
    this.avatarUrl = '',
    this.kind = 'CHAT',
    this.unread = 0,
    this.mention = false,
    this.muted = false,
    this.pinned = false,
    this.verified = false,
    this.selected = false,
    this.draft = false,
    this.italic = false,
    this.ownStatus,
    this.ownRead = false,
    this.hasCall = false,
    this.badge,
  });

  final String id;
  final String title;
  final String preview;
  final String time;
  final String avatarUrl;
  final String kind;
  final int unread;
  final bool mention;
  final bool muted;
  final bool pinned;
  final bool verified;
  final bool selected;
  final bool draft;
  final bool italic;
  final String? ownStatus;
  final bool ownRead;
  final bool hasCall;
  final String? badge;

  Map<String, Object?> toJson() => {
    'id': id,
    'title': title,
    'preview': preview,
    'time': time,
    'avatarUrl': avatarUrl,
    'kind': kind,
    'unread': unread,
    'mention': mention,
    'muted': muted,
    'pinned': pinned,
    'verified': verified,
    'selected': selected,
    'draft': draft,
    'italic': italic,
    'ownStatus': ownStatus,
    'ownRead': ownRead,
    'hasCall': hasCall,
    'badge': badge,
  };

  @override
  bool operator ==(Object other) =>
      other is NativeChatRow && mapEquals(other.toJson(), toJson());

  @override
  int get hashCode => Object.hashAll(toJson().values);
}

@immutable
class NativeChatListDiff {
  const NativeChatListDiff({
    required this.order,
    required this.upsert,
    required this.remove,
  });

  final List<String>? order;
  final List<NativeChatRow> upsert;
  final List<String> remove;

  bool get isEmpty => order == null && upsert.isEmpty && remove.isEmpty;

  Map<String, Object?> toJson() => {
    'order': order,
    'upsert': [for (final row in upsert) row.toJson()],
    'remove': remove,
  };

  static NativeChatListDiff between(
    List<NativeChatRow> previous,
    List<NativeChatRow> next,
  ) {
    final before = {for (final row in previous) row.id: row};
    final nextIds = <String>{for (final row in next) row.id};
    final upsert = <NativeChatRow>[
      for (final row in next)
        if (before[row.id] != row) row,
    ];
    final remove = <String>[
      for (final row in previous)
        if (!nextIds.contains(row.id)) row.id,
    ];
    final previousOrder = [
      for (final row in previous)
        if (nextIds.contains(row.id)) row.id,
    ];
    final nextOrder = [
      for (final row in next)
        if (before.containsKey(row.id)) row.id,
    ];
    final orderChanged =
        !listEquals(previousOrder, nextOrder) ||
        next.length != previousOrder.length;
    return NativeChatListDiff(
      order: orderChanged ? [for (final row in next) row.id] : null,
      upsert: upsert,
      remove: remove,
    );
  }
}

@immutable
class NativeChatListTheme {
  const NativeChatListTheme({
    required this.dark,
    required this.primary,
    required this.surface,
    required this.onSurface,
    required this.onSurfaceVariant,
    required this.outline,
  });

  final bool dark;
  final int primary;
  final int surface;
  final int onSurface;
  final int onSurfaceVariant;
  final int outline;

  Map<String, Object?> toJson() => {
    'dark': dark,
    'primary': primary,
    'surface': surface,
    'onSurface': onSurface,
    'onSurfaceVariant': onSurfaceVariant,
    'outline': outline,
  };

  @override
  bool operator ==(Object other) =>
      other is NativeChatListTheme && mapEquals(other.toJson(), toJson());

  @override
  int get hashCode => Object.hashAll(toJson().values);
}

enum NativeChatListActionType {
  open,
  select,
  pin,
  mute,
  archive,
  delete,
  search,
}

@immutable
class NativeChatListAction {
  const NativeChatListAction(this.type, [this.ids = const []]);

  final NativeChatListActionType type;
  final List<String> ids;

  static NativeChatListAction? parse(Object? raw) {
    if (raw is! Map) return null;
    final name = raw['type'];
    final type = NativeChatListActionType.values
        .where((t) => t.name == name)
        .firstOrNull;
    if (type == null) return null;
    final rawIds = raw['ids'];
    final ids = rawIds is List
        ? [
            for (final id in rawIds)
              if (id is String && id.isNotEmpty) id,
          ]
        : const <String>[];
    final needsIds = type != NativeChatListActionType.search;
    if (needsIds && ids.isEmpty) return null;
    return NativeChatListAction(type, ids);
  }
}

class NativeChatListHandlers {
  const NativeChatListHandlers({
    required this.open,
    required this.select,
    required this.pin,
    required this.mute,
    required this.archive,
    required this.delete,
    required this.search,
  });

  final void Function(String id) open;
  final void Function(String id) select;
  final FutureOr<void> Function(List<String> ids) pin;
  final FutureOr<void> Function(List<String> ids) mute;
  final FutureOr<void> Function(List<String> ids) archive;
  final FutureOr<void> Function(List<String> ids) delete;
  final VoidCallback search;

  Future<void> route(NativeChatListAction action) async {
    switch (action.type) {
      case NativeChatListActionType.open:
        open(action.ids.first);
      case NativeChatListActionType.select:
        select(action.ids.first);
      case NativeChatListActionType.pin:
        await pin(action.ids);
      case NativeChatListActionType.mute:
        await mute(action.ids);
      case NativeChatListActionType.archive:
        await archive(action.ids);
      case NativeChatListActionType.delete:
        await delete(action.ids);
      case NativeChatListActionType.search:
        search();
    }
  }
}

class NativeChatListBridge {
  NativeChatListBridge({
    required this.channel,
    required this.handlers,
    this.onReady,
  }) {
    channel.setMethodCallHandler(_onCall);
  }

  final MethodChannel channel;
  final NativeChatListHandlers handlers;
  final VoidCallback? onReady;

  List<NativeChatRow> _sent = const [];
  bool _synced = false;
  bool _selecting = false;
  bool _disposed = false;

  bool get isSynced => _synced;

  Future<dynamic> _onCall(MethodCall call) async {
    switch (call.method) {
      case 'ready':
        _synced = false;
        _sent = const [];
        onReady?.call();
      case 'action':
        final action = NativeChatListAction.parse(call.arguments);
        if (action == null) {
          logger.w('Нативный список чатов: непонятное действие');
          return;
        }
        await handlers.route(action);
    }
  }

  Future<void> sync(List<NativeChatRow> rows, {bool selecting = false}) async {
    if (_disposed) return;
    final snapshot = List<NativeChatRow>.unmodifiable(rows);
    try {
      if (!_synced) {
        _synced = true;
        _sent = snapshot;
        _selecting = selecting;
        await channel.invokeMethod<void>('replace', {
          'rows': [for (final row in snapshot) row.toJson()],
          'selecting': selecting,
        });
        return;
      }
      final diff = NativeChatListDiff.between(_sent, snapshot);
      final selectingChanged = _selecting != selecting;
      if (diff.isEmpty && !selectingChanged) return;
      _sent = snapshot;
      _selecting = selecting;
      await channel.invokeMethod<void>('apply', {
        ...diff.toJson(),
        'selecting': selecting,
      });
    } on PlatformException catch (e) {
      logger.w('Нативный список чатов: ошибка синхронизации ($e)');
      _synced = false;
    } on MissingPluginException {
      _synced = false;
    }
  }

  Future<void> setTheme(NativeChatListTheme theme) async {
    if (_disposed) return;
    try {
      await channel.invokeMethod<void>('theme', theme.toJson());
    } on PlatformException catch (e) {
      logger.w('Нативный список чатов: ошибка темы ($e)');
    } on MissingPluginException {
      return;
    }
  }

  Future<void> setInsets({required double top, required double bottom}) async {
    if (_disposed) return;
    try {
      await channel.invokeMethod<void>('insets', {
        'top': top,
        'bottom': bottom,
      });
    } on PlatformException catch (e) {
      logger.w('Нативный список чатов: ошибка отступов ($e)');
    } on MissingPluginException {
      return;
    }
  }

  void dispose() {
    _disposed = true;
    channel.setMethodCallHandler(null);
  }
}
