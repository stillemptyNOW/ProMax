import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import 'app_database.dart';

int localUnreadCount({
  required int serverUnread,
  required int seen,
  required int localMark,
  required int lastMessageTime,
}) {
  if (lastMessageTime > 0 && lastMessageTime <= localMark) return 0;
  final server = serverUnread < 0 ? 0 : serverUnread;
  final unseen = server - (seen < 0 ? 0 : seen);
  if (unseen > 0) return unseen;
  return server > 0 ? 1 : 0;
}

@immutable
class LocalReadState {
  final int mark;
  final int serverMark;
  final int? serverUnread;
  final int? seen;

  const LocalReadState({
    this.mark = 0,
    this.serverMark = 0,
    this.serverUnread,
    this.seen,
  });

  bool get isActive => mark > 0;

  LocalReadState viewedUpTo(
    int nextMark, {
    required int serverMark,
    required int displayedUnread,
    required int remaining,
  }) {
    if (nextMark <= mark) return this;
    final raw = isActive ? serverUnread : displayedUnread;
    return LocalReadState(
      mark: nextMark,
      serverMark: isActive ? this.serverMark : serverMark,
      serverUnread: raw,
      seen: raw == null ? null : math.max(0, raw - math.max(0, remaining)),
    );
  }

  LocalReadState withServer({required int serverUnread, int? serverMark}) {
    if (!isActive) return this;
    if (serverMark != null && serverMark >= mark) {
      return const LocalReadState();
    }
    final moved = serverMark != null && serverMark != this.serverMark;
    return LocalReadState(
      mark: mark,
      serverMark: moved ? serverMark : this.serverMark,
      serverUnread: serverUnread,
      seen: moved ? null : seen,
    );
  }

  LocalReadState withSeen(int value) => LocalReadState(
    mark: mark,
    serverMark: serverMark,
    serverUnread: serverUnread,
    seen: math.max(0, value),
  );

  int unreadFor(int lastMessageTime) => localUnreadCount(
    serverUnread: serverUnread ?? 0,
    seen: seen ?? 0,
    localMark: mark,
    lastMessageTime: lastMessageTime,
  );

  bool covers(int messageTime) => isActive && messageTime <= mark;

  Map<String, Object> toJson() => {
    'mark': mark,
    'serverMark': serverMark,
    'serverUnread': ?serverUnread,
    'seen': ?seen,
  };

  static LocalReadState fromJson(Object? raw) {
    if (raw is! Map) return const LocalReadState();
    int? read(String key) => switch (raw[key]) {
      final int value => value,
      _ => null,
    };
    return LocalReadState(
      mark: read('mark') ?? 0,
      serverMark: read('serverMark') ?? 0,
      serverUnread: read('serverUnread'),
      seen: read('seen'),
    );
  }

  static String _key(int chatId) => 'promax_local_read_$chatId';

  static Future<LocalReadState> load(int accountId, int chatId) async {
    final raw = await AppDatabase.getSyncValue(accountId, _key(chatId));
    if (raw == null) return const LocalReadState();
    try {
      return fromJson(jsonDecode(raw));
    } catch (_) {
      return const LocalReadState();
    }
  }

  Future<void> save(int accountId, int chatId) =>
      AppDatabase.setSyncValue(accountId, _key(chatId), jsonEncode(toJson()));

  static Future<void> recordView(
    int accountId,
    int chatId,
    int mark, {
    required int serverMark,
    required int displayedUnread,
    int remaining = 0,
  }) async {
    final current = await load(accountId, chatId);
    final next = current.viewedUpTo(
      mark,
      serverMark: serverMark,
      displayedUnread: displayedUnread,
      remaining: remaining,
    );
    if (identical(next, current)) return;
    await next.save(accountId, chatId);
  }

  @override
  bool operator ==(Object other) =>
      other is LocalReadState &&
      other.mark == mark &&
      other.serverMark == serverMark &&
      other.serverUnread == serverUnread &&
      other.seen == seen;

  @override
  int get hashCode => Object.hash(mark, serverMark, serverUnread, seen);
}
