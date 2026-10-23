import 'package:flutter/foundation.dart';

import '../../core/cache/info_cache.dart';
import '../../core/storage/app_database.dart';
import 'messages.dart' show CachedMessage, ContactCache;

class DeletionPolicy {
  DeletionPolicy._();

  static final DeletionPolicy instance = DeletionPolicy._();

  static const String deleteForAllKey = 'delete-for-all';
  static const String editTimeoutKey = 'edit-timeout';
  static const String editCommentTimeoutKey = 'edit-comment-timeout';
  static const Duration defaultEditTimeout = Duration(seconds: 86400);
  static const Duration defaultEditCommentTimeout = Duration(seconds: 93600);

  int? _accountId;
  bool? _deleteForAll;
  Duration? _editTimeout;
  Duration? _editCommentTimeout;

  int? get accountId => _accountId;

  bool? get deleteForAll => _deleteForAll;

  Duration get editTimeout => _editTimeout ?? defaultEditTimeout;

  Duration get editCommentTimeout =>
      _editCommentTimeout ?? defaultEditCommentTimeout;

  bool get editTimeoutKnown => _editTimeout != null;

  Future<void> load(int accountId) async {
    final values = await AppDatabase.getAllSyncValues(accountId);
    _accountId = accountId;
    _deleteForAll = _parseFlag(values[SyncKey.deleteForAll]);
    _editTimeout = _parseSeconds(values[SyncKey.editTimeout]);
    _editCommentTimeout = _parseSeconds(values[SyncKey.editCommentTimeout]);
  }

  Future<void> applyServerConfig(
    int accountId,
    Map<dynamic, dynamic> server, {
    required bool complete,
  }) async {
    final deleteForAll = server.containsKey(deleteForAllKey)
        ? _parseFlag(server[deleteForAllKey]) ?? false
        : (complete ? false : null);
    final editTimeout = _parseSeconds(server[editTimeoutKey]);
    final editCommentTimeout = _parseSeconds(server[editCommentTimeoutKey]);
    if (deleteForAll != null) {
      await AppDatabase.setSyncValue(
        accountId,
        SyncKey.deleteForAll,
        '$deleteForAll',
      );
    }
    if (editTimeout != null) {
      await AppDatabase.setSyncValue(
        accountId,
        SyncKey.editTimeout,
        '${editTimeout.inSeconds}',
      );
    }
    if (editCommentTimeout != null) {
      await AppDatabase.setSyncValue(
        accountId,
        SyncKey.editCommentTimeout,
        '${editCommentTimeout.inSeconds}',
      );
    }
    await load(accountId);
  }

  void forget() {
    _accountId = null;
    _deleteForAll = null;
    _editTimeout = null;
    _editCommentTimeout = null;
  }

  String describe() =>
      'delete-for-all=${_deleteForAll ?? 'неизвестно'}, '
      'edit-timeout=${_editTimeout?.inSeconds ?? 'неизвестно'} с '
      '(по умолчанию ${defaultEditTimeout.inSeconds} с), '
      'edit-comment-timeout=${_editCommentTimeout?.inSeconds ?? 'неизвестно'} с';

  bool allowsChatForAll({
    required int chatId,
    required String? chatType,
    required int? owner,
    required int myId,
    required bool peerIsBot,
  }) => chatForAllAllowed(
    chatId: chatId,
    chatType: chatType,
    owner: owner,
    myId: myId,
    peerIsBot: peerIsBot,
    deleteForAll: _deleteForAll,
  );

  @visibleForTesting
  void debugSet({
    required int accountId,
    bool? deleteForAll,
    Duration? editTimeout,
  }) {
    _accountId = accountId;
    _deleteForAll = deleteForAll;
    _editTimeout = editTimeout;
  }

  static bool? _parseFlag(Object? raw) => switch (raw) {
    bool value => value,
    'true' => true,
    'false' => false,
    num value => value != 0,
    _ => null,
  };

  static Duration? _parseSeconds(Object? raw) {
    final seconds = switch (raw) {
      int value => value,
      num value => value.toInt(),
      String value => int.tryParse(value.trim()),
      _ => null,
    };
    if (seconds == null || seconds <= 0) return null;
    return Duration(seconds: seconds);
  }
}

bool chatForAllAllowed({
  required int chatId,
  required String? chatType,
  required int? owner,
  required int myId,
  required bool peerIsBot,
  required bool? deleteForAll,
}) {
  if (chatId == 0) return false;
  return switch (chatType) {
    'DIALOG' => !peerIsBot && (deleteForAll ?? true),
    'CHAT' => owner != null && owner == myId,
    _ => false,
  };
}

int? dialogPeerId({
  required int chatId,
  required int myId,
  Iterable<int> participants = const [],
}) {
  for (final id in participants) {
    if (id != myId) return id;
  }
  final derived = chatId ^ myId;
  return derived > 0 && derived != myId ? derived : null;
}

bool knownBot(int? userId, {Set<String> chatOptions = const {}}) {
  if (userId == null) return chatOptions.contains('BOT');
  final options = ContactCache.getOptions(userId);
  if (options != null) return options.contains('BOT');
  final info = ContactInfoFetch.peek(userId);
  if (info != null) return info.isBot;
  return chatOptions.contains('BOT');
}

enum MessageDeletionChat { dialog, group, channel, none }

enum ForEveryoneDenial { notSent, scheduled, notMine, tooOld, noRights }

class MessageDeletionRules {
  const MessageDeletionRules({
    required this.chat,
    required this.myId,
    required this.nowMs,
    required this.editTimeout,
    this.canDeleteAny = false,
    this.canDeleteOwn = false,
  });

  final MessageDeletionChat chat;
  final int myId;
  final int nowMs;
  final Duration editTimeout;
  final bool canDeleteAny;
  final bool canDeleteOwn;

  ForEveryoneDenial? denialFor(CachedMessage message) {
    if (int.tryParse(message.id) == null) return ForEveryoneDenial.notSent;
    final mine = message.senderId == myId;
    switch (chat) {
      case MessageDeletionChat.none:
        return ForEveryoneDenial.noRights;
      case MessageDeletionChat.channel:
        if (canDeleteAny || (canDeleteOwn && mine)) return null;
        return mine ? ForEveryoneDenial.noRights : ForEveryoneDenial.notMine;
      case MessageDeletionChat.group when canDeleteAny:
        return null;
      case MessageDeletionChat.group:
      case MessageDeletionChat.dialog:
        if (message.isDelayed) return ForEveryoneDenial.scheduled;
        if (!mine) return ForEveryoneDenial.notMine;
        if (nowMs - message.time >= editTimeout.inMilliseconds) {
          return ForEveryoneDenial.tooOld;
        }
        return null;
    }
  }

  bool allowsForEveryone(CachedMessage message) => denialFor(message) == null;
}
