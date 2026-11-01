import 'dart:convert';

import 'app_database.dart';

abstract final class NotifiedMessages {
  static const limit = 64;

  static String _key(int chatId) => 'promax_notified_$chatId';

  static Future<bool> claim(int accountId, int chatId, String messageId) async {
    final ids = await _load(accountId, chatId);
    if (ids.contains(messageId)) return false;
    ids.add(messageId);
    final kept = ids.length > limit ? ids.sublist(ids.length - limit) : ids;
    await AppDatabase.setSyncValue(accountId, _key(chatId), jsonEncode(kept));
    return true;
  }

  static Future<List<String>> _load(int accountId, int chatId) async {
    final raw = await AppDatabase.getSyncValue(accountId, _key(chatId));
    if (raw == null) return <String>[];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return <String>[];
      return [for (final id in decoded) '$id'];
    } catch (_) {
      return <String>[];
    }
  }
}
