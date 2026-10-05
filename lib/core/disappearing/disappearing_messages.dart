import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../backend/modules/chats.dart';

typedef DisappearingDelete =
    Future<bool> Function(int chatId, List<String> messageIds);

@immutable
class DisappearingEntry {
  const DisappearingEntry(
    this.chatId,
    this.messageId,
    this.dueAt, [
    this.tries = 0,
  ]);

  final int chatId;
  final String messageId;
  final int dueAt;
  final int tries;

  Map<String, Object> toJson() => {
    'c': chatId,
    'm': messageId,
    'd': dueAt,
    't': tries,
  };

  static DisappearingEntry? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final chat = raw['c'];
    final message = raw['m'];
    final due = raw['d'];
    final tries = raw['t'];
    if (chat is! int || message is! String || due is! int) return null;
    return DisappearingEntry(chat, message, due, tries is int ? tries : 0);
  }
}

class DisappearingMessages {
  DisappearingMessages._();

  static final DisappearingMessages instance = DisappearingMessages._();

  static const timersKey = 'promax_disappearing_timers';
  static const queueKey = 'promax_disappearing_queue';
  static const List<int> options = [0, 30, 300, 3600, 28800, 86400];
  static const int maxTries = 4;

  final ValueNotifier<Map<int, int>> timers = ValueNotifier(const {});
  final List<DisappearingEntry> _queue = [];
  final Set<String> _known = {};
  StreamSubscription<MessageEvent>? _events;
  DisappearingDelete? _delete;
  Future<int?> Function()? _myId;
  Timer? _timer;
  bool _running = false;
  DateTime Function() now = DateTime.now;

  static String label(int seconds) => switch (seconds) {
    0 => 'Выключено',
    30 => '30 секунд',
    300 => '5 минут',
    3600 => '1 час',
    28800 => '8 часов',
    86400 => '1 день',
    _ => '$seconds с',
  };

  List<DisappearingEntry> get pending => List.unmodifiable(_queue);

  Future<void> start({
    required Stream<MessageEvent> events,
    required DisappearingDelete delete,
    required Future<int?> Function() myId,
  }) async {
    _delete = delete;
    _myId = myId;
    final prefs = await SharedPreferences.getInstance();
    timers.value = _decodeTimers(prefs.getString(timersKey));
    _queue
      ..clear()
      ..addAll(_decodeQueue(prefs.getString(queueKey)));
    _known
      ..clear()
      ..addAll(_queue.map((e) => '${e.chatId}:${e.messageId}'));
    await _events?.cancel();
    _events = events.listen(_onEvent);
    await runDue();
  }

  Future<void> stop() async {
    await _events?.cancel();
    _events = null;
    _timer?.cancel();
    _timer = null;
  }

  int timerFor(int chatId) => timers.value[chatId] ?? 0;

  Future<void> setTimer(int chatId, int seconds) async {
    final next = Map<int, int>.of(timers.value);
    if (seconds <= 0) {
      next.remove(chatId);
    } else {
      next[chatId] = seconds;
    }
    timers.value = Map.unmodifiable(next);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      timersKey,
      jsonEncode({for (final e in next.entries) '${e.key}': e.value}),
    );
  }

  void _onEvent(MessageEvent event) {
    switch (event) {
      case MessageSentEvent(:final message):
        unawaited(schedule(event.chatId, message.id, message.time));
      case MessageAddedEvent(:final message):
        if (timerFor(event.chatId) <= 0) return;
        unawaited(
          _scheduleIfMine(
            event.chatId,
            message.id,
            message.senderId,
            message.time,
          ),
        );
      default:
        break;
    }
  }

  Future<void> _scheduleIfMine(
    int chatId,
    String messageId,
    int senderId,
    int sentAt,
  ) async {
    final me = await _myId?.call();
    if (me == null || me != senderId) return;
    await schedule(chatId, messageId, sentAt);
  }

  Future<void> schedule(int chatId, String messageId, int sentAt) async {
    final seconds = timerFor(chatId);
    if (seconds <= 0 || messageId.startsWith('temp_')) return;
    if (!_known.add('$chatId:$messageId')) return;
    _queue.add(DisappearingEntry(chatId, messageId, sentAt + seconds * 1000));
    await _save();
    _arm();
  }

  Future<void> runDue() async {
    if (_running) return;
    final delete = _delete;
    if (delete == null) return;
    _running = true;
    try {
      final at = now().millisecondsSinceEpoch;
      final due = _queue.where((e) => e.dueAt <= at).toList();
      final byChat = <int, List<DisappearingEntry>>{};
      for (final entry in due) {
        byChat.putIfAbsent(entry.chatId, () => []).add(entry);
      }
      for (final chat in byChat.entries) {
        final ids = [for (final e in chat.value) e.messageId];
        bool ok;
        try {
          ok = await delete(chat.key, ids);
        } catch (_) {
          ok = false;
        }
        for (final entry in chat.value) {
          _queue.remove(entry);
          if (ok) {
            _known.remove('${entry.chatId}:${entry.messageId}');
          } else if (entry.tries + 1 < maxTries) {
            _queue.add(
              DisappearingEntry(
                entry.chatId,
                entry.messageId,
                at + 60000 * (entry.tries + 1),
                entry.tries + 1,
              ),
            );
          }
        }
      }
      await _save();
    } finally {
      _running = false;
      _arm();
    }
  }

  void _arm() {
    _timer?.cancel();
    _timer = null;
    if (_queue.isEmpty) return;
    final next = _queue.map((e) => e.dueAt).reduce((a, b) => a < b ? a : b);
    final wait = next - now().millisecondsSinceEpoch;
    _timer = Timer(
      Duration(milliseconds: wait < 0 ? 0 : wait),
      () => unawaited(runDue()),
    );
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    if (_queue.isEmpty) {
      await prefs.remove(queueKey);
    } else {
      await prefs.setString(
        queueKey,
        jsonEncode([for (final e in _queue) e.toJson()]),
      );
    }
  }

  static Map<int, int> _decodeTimers(String? raw) {
    if (raw == null) return const {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return const {};
      return Map.unmodifiable({
        for (final e in decoded.entries)
          if (int.tryParse('${e.key}') != null && e.value is int && e.value > 0)
            int.parse('${e.key}'): e.value as int,
      });
    } catch (_) {
      return const {};
    }
  }

  static List<DisappearingEntry> _decodeQueue(String? raw) {
    if (raw == null) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return decoded
          .map(DisappearingEntry.fromJson)
          .whereType<DisappearingEntry>()
          .toList();
    } catch (_) {
      return const [];
    }
  }
}
