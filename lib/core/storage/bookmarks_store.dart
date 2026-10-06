import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

@immutable
class MessageBookmark {
  const MessageBookmark({
    required this.chatId,
    required this.messageId,
    required this.chatName,
    required this.text,
    required this.time,
    required this.savedAt,
  });

  final int chatId;
  final String messageId;
  final String chatName;
  final String text;
  final int time;
  final int savedAt;

  String get key => '$chatId:$messageId';

  Map<String, Object> toJson() => {
    'c': chatId,
    'm': messageId,
    'n': chatName,
    't': text,
    'tm': time,
    's': savedAt,
  };

  static MessageBookmark? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final chat = raw['c'];
    final message = raw['m'];
    if (chat is! int || message is! String) return null;
    return MessageBookmark(
      chatId: chat,
      messageId: message,
      chatName: raw['n'] is String ? raw['n'] as String : '',
      text: raw['t'] is String ? raw['t'] as String : '',
      time: raw['tm'] is int ? raw['tm'] as int : 0,
      savedAt: raw['s'] is int ? raw['s'] as int : 0,
    );
  }
}

class BookmarksStore {
  BookmarksStore._();

  static final BookmarksStore instance = BookmarksStore._();

  static const prefKey = 'promax_bookmarks';
  static const int maxBookmarks = 2000;
  static const int maxTextLength = 1000;

  final ValueNotifier<List<MessageBookmark>> items = ValueNotifier(const []);

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(prefKey);
    if (raw == null) {
      items.value = const [];
      return;
    }
    try {
      final decoded = jsonDecode(raw);
      items.value = decoded is List
          ? List.unmodifiable(
              decoded
                  .map(MessageBookmark.fromJson)
                  .whereType<MessageBookmark>(),
            )
          : const [];
    } catch (_) {
      items.value = const [];
    }
  }

  bool contains(int chatId, String messageId) =>
      items.value.any((b) => b.chatId == chatId && b.messageId == messageId);

  Future<bool> toggle({
    required int chatId,
    required String messageId,
    required String chatName,
    required String text,
    required int time,
  }) async {
    final current = [...items.value];
    final index = current.indexWhere(
      (b) => b.chatId == chatId && b.messageId == messageId,
    );
    final added = index < 0;
    if (added) {
      current.insert(
        0,
        MessageBookmark(
          chatId: chatId,
          messageId: messageId,
          chatName: chatName,
          text: text.length > maxTextLength
              ? text.substring(0, maxTextLength)
              : text,
          time: time,
          savedAt: DateTime.now().millisecondsSinceEpoch,
        ),
      );
      if (current.length > maxBookmarks) current.removeLast();
    } else {
      current.removeAt(index);
    }
    await _save(current);
    return added;
  }

  Future<void> remove(MessageBookmark bookmark) async {
    await _save([
      for (final b in items.value)
        if (b.key != bookmark.key) b,
    ]);
  }

  Future<void> _save(List<MessageBookmark> next) async {
    items.value = List.unmodifiable(next);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      prefKey,
      jsonEncode([for (final b in next) b.toJson()]),
    );
  }
}
