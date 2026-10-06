import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ChatNotesStore {
  ChatNotesStore._();

  static final ChatNotesStore instance = ChatNotesStore._();

  static const prefKey = 'promax_chat_notes';
  static const int maxLength = 4000;

  final ValueNotifier<Map<int, String>> notes = ValueNotifier(const {});

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(prefKey);
    if (raw == null) {
      notes.value = const {};
      return;
    }
    try {
      final decoded = jsonDecode(raw);
      notes.value = decoded is Map
          ? Map.unmodifiable({
              for (final entry in decoded.entries)
                if (int.tryParse('${entry.key}') case final id?
                    when entry.value is String &&
                        (entry.value as String).trim().isNotEmpty)
                  id: entry.value as String,
            })
          : const {};
    } catch (_) {
      notes.value = const {};
    }
  }

  String? noteFor(int chatId) => notes.value[chatId];

  Future<void> save(int chatId, String text) async {
    final trimmed = text.trim();
    final next = Map<int, String>.of(notes.value);
    if (trimmed.isEmpty) {
      next.remove(chatId);
    } else {
      next[chatId] = trimmed.length > maxLength
          ? trimmed.substring(0, maxLength)
          : trimmed;
    }
    notes.value = Map.unmodifiable(next);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      prefKey,
      jsonEncode({for (final e in next.entries) '${e.key}': e.value}),
    );
  }
}
