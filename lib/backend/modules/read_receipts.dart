import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../../core/storage/app_database.dart';
import '../../core/storage/read_receipt.dart';
import '../../core/utils/logger.dart';
import 'messages.dart' show CachedMessage;

enum MessageReadKind { exact, atMost, unknown, unread, hidden }

@immutable
class MessageReadState {
  const MessageReadState._(this.kind, [this.at]);

  const MessageReadState.exact(int at) : this._(MessageReadKind.exact, at);

  const MessageReadState.atMost(int at) : this._(MessageReadKind.atMost, at);

  static const unknown = MessageReadState._(MessageReadKind.unknown);
  static const unread = MessageReadState._(MessageReadKind.unread);
  static const hidden = MessageReadState._(MessageReadKind.hidden);

  final MessageReadKind kind;
  final int? at;

  bool get isRead =>
      kind == MessageReadKind.exact ||
      kind == MessageReadKind.atMost ||
      kind == MessageReadKind.unknown;

  @override
  bool operator ==(Object other) =>
      other is MessageReadState && other.kind == kind && other.at == at;

  @override
  int get hashCode => Object.hash(kind, at);

  @override
  String toString() => 'MessageReadState(${kind.name}, $at)';
}

class ReadReceipts extends ChangeNotifier {
  ReadReceipts._();

  static final ReadReceipts instance = ReadReceipts._();

  final Map<(int, int), List<ReadReceipt>> _byChat = {};
  final Map<(int, int), Future<void>> _loading = {};

  bool isLoaded(int accountId, int chatId) =>
      _byChat.containsKey((accountId, chatId));

  Future<void> preload(int accountId, int chatId) {
    final key = (accountId, chatId);
    if (_byChat.containsKey(key)) return Future.value();
    return _loading[key] ??= _load(key);
  }

  Future<void> _load((int, int) key) async {
    List<ReadReceipt> stored;
    try {
      stored = await AppDatabase.loadReadReceipts(key.$1, key.$2);
    } catch (e) {
      logger.w('Не удалось загрузить время прочтения для ${key.$2}: $e');
      stored = const [];
    }
    _loading.remove(key);
    _byChat[key] = [...stored];
    notifyListeners();
  }

  Future<void> record(int accountId, int chatId, ReadReceipt receipt) async {
    if (receipt.mark <= receipt.prevMark) return;
    try {
      await AppDatabase.insertReadReceipt(accountId, chatId, receipt);
    } catch (e) {
      logger.w('Не удалось сохранить время прочтения для $chatId: $e');
    }
    final key = (accountId, chatId);
    final inFlight = _loading[key];
    if (inFlight != null) await inFlight;
    final list = _byChat[key];
    if (list == null) return;
    final known = list.any(
      (r) => r.userId == receipt.userId && r.mark == receipt.mark,
    );
    if (known) return;
    list.add(receipt);
    if (list.length > AppDatabase.readReceiptsPerChat) {
      list.sort((a, b) => a.mark.compareTo(b.mark));
      list.removeRange(0, list.length - AppDatabase.readReceiptsPerChat);
    }
    notifyListeners();
  }

  int? latestMark(int accountId, int chatId, int userId) {
    int? latest;
    for (final r in _byChat[(accountId, chatId)] ?? const <ReadReceipt>[]) {
      if (r.userId != userId) continue;
      if (latest == null || r.mark > latest) latest = r.mark;
    }
    return latest;
  }

  Iterable<ReadReceipt> receiptsFor(int accountId, int chatId, int userId) =>
      (_byChat[(accountId, chatId)] ?? const <ReadReceipt>[]).where(
        (r) => r.userId == userId,
      );

  MessageReadState stateFor({
    required int accountId,
    required int chatId,
    required int userId,
    required int? mark,
    required int messageTime,
    int? replyTime,
  }) => resolve(
    mark: mark,
    messageTime: messageTime,
    receipts: receiptsFor(accountId, chatId, userId),
    replyTime: replyTime,
  );

  static MessageReadState resolve({
    required int? mark,
    required int messageTime,
    required Iterable<ReadReceipt> receipts,
    int? replyTime,
  }) {
    if (mark == null) return MessageReadState.hidden;
    if (mark < messageTime) return MessageReadState.unread;
    int? exact;
    for (final receipt in receipts) {
      if (!receipt.covers(messageTime)) continue;
      final at = math.max(receipt.readAt, messageTime);
      if (exact == null || at < exact) exact = at;
    }
    if (replyTime != null &&
        replyTime > messageTime &&
        (exact == null || replyTime < exact)) {
      return MessageReadState.atMost(replyTime);
    }
    if (exact != null) return MessageReadState.exact(exact);
    return MessageReadState.unknown;
  }

  static String? stampTargetId(
    List<CachedMessage> messages, {
    required int mark,
    required int myId,
  }) {
    for (var i = messages.length - 1; i >= 0; i--) {
      final m = messages[i];
      if (m.time > mark || m.senderId != myId) continue;
      if (m.isControl || m.deleted || int.tryParse(m.id) == null) continue;
      return m.id;
    }
    return null;
  }

  static Map<int, int> firstMessageTimesAfter(
    Iterable<CachedMessage> messages,
    int time,
  ) {
    final firsts = <int, int>{};
    for (final m in messages) {
      if (m.time <= time || m.isControl) continue;
      final known = firsts[m.senderId];
      if (known == null || m.time < known) firsts[m.senderId] = m.time;
    }
    return firsts;
  }

  static int readerCount(
    Map<int, int> participants, {
    required int myId,
    required int messageTime,
  }) => participants.entries
      .where((e) => e.key != myId && e.value >= messageTime)
      .length;

  @visibleForTesting
  void resetForTest() {
    _byChat.clear();
    _loading.clear();
  }
}

class ReadBaselines {
  int? _since;
  final Map<(int, int, int), int> _confirmed = {};

  bool get active => _since != null;

  void begin(int serverTime) {
    _since = serverTime;
    _confirmed.clear();
  }

  void end() {
    _since = null;
    _confirmed.clear();
  }

  void confirm(int accountId, int chatId, int userId, int mark) {
    if (_since == null) return;
    final key = (accountId, chatId, userId);
    final known = _confirmed[key];
    if (known == null || mark > known) _confirmed[key] = mark;
  }

  void confirmAll(int accountId, int chatId, Map<int, int> participants) {
    for (final entry in participants.entries) {
      confirm(accountId, chatId, entry.key, entry.value);
    }
  }

  int? baseFor(
    int accountId,
    int chatId,
    int userId, {
    Iterable<int> knownMarks = const [],
  }) {
    final since = _since;
    if (since == null) return null;
    final known = knownMarks.fold<int?>(
      null,
      (a, b) => a == null ? b : math.max(a, b),
    );
    final confirmed = _confirmed[(accountId, chatId, userId)];
    if (confirmed != null) return math.max(confirmed, known ?? confirmed);
    return math.max(since, known ?? since);
  }
}
