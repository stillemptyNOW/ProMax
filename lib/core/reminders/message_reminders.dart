import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

@immutable
class MessageReminder {
  const MessageReminder({
    required this.id,
    required this.chatId,
    required this.messageId,
    required this.chatName,
    required this.text,
    required this.messageTime,
    required this.at,
  });

  final int id;
  final int chatId;
  final String messageId;
  final String chatName;
  final String text;
  final int messageTime;
  final int at;

  DateTime get dueAt => DateTime.fromMillisecondsSinceEpoch(at);

  String get preview => text.trim().isEmpty ? 'Вложение' : text.trim();

  Map<String, Object> toJson() => {
    'id': id,
    'c': chatId,
    'm': messageId,
    'n': chatName,
    't': text,
    'mt': messageTime,
    'at': at,
  };

  static MessageReminder? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id'];
    final chat = raw['c'];
    final message = raw['m'];
    final at = raw['at'];
    if (id is! int || chat is! int || message is! String || at is! int) {
      return null;
    }
    return MessageReminder(
      id: id,
      chatId: chat,
      messageId: message,
      chatName: raw['n'] is String ? raw['n'] as String : '',
      text: raw['t'] is String ? raw['t'] as String : '',
      messageTime: raw['mt'] is int ? raw['mt'] as int : 0,
      at: at,
    );
  }
}

abstract interface class ReminderScheduler {
  Future<bool> ensurePermission();
  Future<void> schedule(MessageReminder reminder);
  Future<void> cancel(int id);
}

class MessageReminders {
  MessageReminders._();

  static final MessageReminders instance = MessageReminders._();

  static const prefKey = 'promax_message_reminders';
  static const int maxTextLength = 300;
  static const int maxReminders = 200;

  final ValueNotifier<List<MessageReminder>> items = ValueNotifier(const []);
  final StreamController<MessageReminder> _due = StreamController.broadcast();

  ReminderScheduler? scheduler;
  final Map<int, Timer> _timers = {};

  Stream<MessageReminder> get due => _due.stream;

  bool get firesInApp => scheduler == null;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(prefKey);
    var loaded = const <MessageReminder>[];
    if (raw != null) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          loaded = [
            for (final entry in decoded) ?MessageReminder.fromJson(entry),
          ];
        }
      } catch (_) {}
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    final upcoming = [
      for (final r in loaded)
        if (r.at > now) r,
    ];
    items.value = List.unmodifiable(_sorted(upcoming));
    if (upcoming.length != loaded.length) await _persist();
    for (final r in upcoming) {
      _arm(r);
    }
  }

  MessageReminder? find(int chatId, String messageId) => items.value
      .where((r) => r.chatId == chatId && r.messageId == messageId)
      .firstOrNull;

  Future<MessageReminder?> add({
    required int chatId,
    required String messageId,
    required String chatName,
    required String text,
    required int messageTime,
    required DateTime at,
  }) async {
    final permitted = await scheduler?.ensurePermission() ?? true;
    if (!permitted) return null;
    final existing = find(chatId, messageId);
    if (existing != null) await remove(existing);
    final reminder = MessageReminder(
      id: _nextId(),
      chatId: chatId,
      messageId: messageId,
      chatName: chatName,
      text: text.length > maxTextLength
          ? text.substring(0, maxTextLength)
          : text,
      messageTime: messageTime,
      at: at.millisecondsSinceEpoch,
    );
    final next = _sorted([...items.value, reminder]);
    while (next.length > maxReminders) {
      await _disarm(next.removeLast());
    }
    items.value = List.unmodifiable(next);
    await _persist();
    await scheduler?.schedule(reminder);
    _arm(reminder);
    return reminder;
  }

  Future<void> remove(MessageReminder reminder) async {
    items.value = List.unmodifiable([
      for (final r in items.value)
        if (r.id != reminder.id) r,
    ]);
    await _persist();
    await _disarm(reminder);
  }

  Future<void> _disarm(MessageReminder reminder) async {
    _timers.remove(reminder.id)?.cancel();
    await scheduler?.cancel(reminder.id);
  }

  void _arm(MessageReminder reminder) {
    _timers.remove(reminder.id)?.cancel();
    final delay = reminder.dueAt.difference(DateTime.now());
    _timers[reminder.id] = Timer(
      delay.isNegative ? Duration.zero : delay,
      () => _fire(reminder),
    );
  }

  Future<void> _fire(MessageReminder reminder) async {
    _timers.remove(reminder.id);
    if (!items.value.any((r) => r.id == reminder.id)) return;
    items.value = List.unmodifiable([
      for (final r in items.value)
        if (r.id != reminder.id) r,
    ]);
    await _persist();
    _due.add(reminder);
  }

  int _nextId() {
    final taken = {for (final r in items.value) r.id};
    var id = DateTime.now().millisecondsSinceEpoch ~/ 1000 & 0x3fffffff;
    while (taken.contains(id)) {
      id = (id + 1) & 0x3fffffff;
    }
    return 0x40000000 | id;
  }

  List<MessageReminder> _sorted(List<MessageReminder> list) =>
      list..sort((a, b) => a.at.compareTo(b.at));

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      prefKey,
      jsonEncode([for (final r in items.value) r.toJson()]),
    );
  }

  @visibleForTesting
  void resetForTest() {
    for (final timer in _timers.values) {
      timer.cancel();
    }
    _timers.clear();
    scheduler = null;
    items.value = const [];
  }
}

@immutable
class ReminderPreset {
  const ReminderPreset(this.label, this.at);

  final String label;
  final DateTime at;

  static List<ReminderPreset> forNow(DateTime now) {
    final today = DateTime(now.year, now.month, now.day);
    final evening = today.add(const Duration(hours: 19));
    final tomorrowMorning = today.add(const Duration(days: 1, hours: 9));
    final daysToMonday = (DateTime.monday - now.weekday + 7) % 7;
    final nextMonday = today.add(
      Duration(days: daysToMonday == 0 ? 7 : daysToMonday, hours: 9),
    );
    return [
      ReminderPreset('Через 20 минут', now.add(const Duration(minutes: 20))),
      ReminderPreset('Через час', now.add(const Duration(hours: 1))),
      ReminderPreset('Через 3 часа', now.add(const Duration(hours: 3))),
      if (evening.difference(now) > const Duration(minutes: 30))
        ReminderPreset('Сегодня в 19:00', evening),
      ReminderPreset('Завтра в 9:00', tomorrowMorning),
      ReminderPreset('В понедельник в 9:00', nextMonday),
    ];
  }
}
