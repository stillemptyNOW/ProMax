import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/logger.dart';

class IgnoredSenders {
  IgnoredSenders._();

  static final IgnoredSenders instance = IgnoredSenders._();

  static const prefKey = 'promax_ignored_senders';
  static const maxUserId = 9007199254740991;

  final ValueNotifier<int> revision = ValueNotifier(0);
  final Map<int, Set<int>> _byAccount = {};
  Future<void>? _loading;

  Future<void> load() => _loading ??= _read();

  Future<void> _read() async {
    final String? raw;
    try {
      raw = (await SharedPreferences.getInstance()).getString(prefKey);
    } catch (e) {
      _loading = null;
      logger.w('IgnoredSenders: список не прочитан: $e');
      return;
    }
    _byAccount
      ..clear()
      ..addAll(decode(raw));
    revision.value++;
  }

  @visibleForTesting
  void reset() {
    _loading = null;
    _byAccount.clear();
  }

  List<int> of(int accountId) {
    final ids = _byAccount[accountId];
    if (ids == null) return const [];
    return ids.toList()..sort();
  }

  bool isIgnored(int accountId, int userId) =>
      _byAccount[accountId]?.contains(userId) ?? false;

  int? ignoredPeer(int accountId, int chatId) {
    final peer = dialogPeerOf(accountId, chatId);
    return peer != null && isIgnored(accountId, peer) ? peer : null;
  }

  bool hidesFromDialog({
    required int accountId,
    required int chatId,
    required int? senderId,
    bool isDialog = false,
  }) {
    if (senderId == null || senderId == accountId) return false;
    if (!isIgnored(accountId, senderId)) return false;
    return isDialog || dialogPeerOf(accountId, chatId) == senderId;
  }

  Future<bool> add(int accountId, int userId) async {
    if (accountId <= 0 || !isValidUserId(userId) || userId == accountId) {
      return false;
    }
    await load();
    final ids = _byAccount.putIfAbsent(accountId, () => <int>{});
    if (!ids.add(userId)) return false;
    await _save();
    return true;
  }

  Future<bool> remove(int accountId, int userId) async {
    await load();
    final ids = _byAccount[accountId];
    if (ids == null || !ids.remove(userId)) return false;
    if (ids.isEmpty) _byAccount.remove(accountId);
    await _save();
    return true;
  }

  Future<void> _save() async {
    revision.value++;
    final prefs = await SharedPreferences.getInstance();
    if (_byAccount.isEmpty) {
      await prefs.remove(prefKey);
    } else {
      await prefs.setString(prefKey, encode(_byAccount));
    }
  }

  static int? dialogPeerOf(int accountId, int chatId) {
    if (accountId <= 0 || chatId <= 0) return null;
    final peer = chatId ^ accountId;
    return peer > 0 && peer != accountId ? peer : null;
  }

  static bool isValidUserId(int userId) => userId > 0 && userId <= maxUserId;

  static int? parseUserId(String raw) {
    final text = raw.trim();
    if (!RegExp(r'^\d{1,16}$').hasMatch(text)) return null;
    final value = int.tryParse(text);
    return value != null && isValidUserId(value) ? value : null;
  }

  static String encode(Map<int, Set<int>> byAccount) => jsonEncode({
    for (final entry in byAccount.entries)
      if (entry.value.isNotEmpty)
        '${entry.key}': (entry.value.toList()..sort()),
  });

  static Map<int, Set<int>> decode(String? raw) {
    if (raw == null || raw.isEmpty) return {};
    Object? parsed;
    try {
      parsed = jsonDecode(raw);
    } catch (_) {
      return {};
    }
    if (parsed is! Map) return {};
    final result = <int, Set<int>>{};
    parsed.forEach((key, value) {
      final accountId = int.tryParse('$key');
      if (accountId == null || accountId <= 0 || value is! List) return;
      final ids = {
        for (final id in value)
          if (id is int && isValidUserId(id) && id != accountId) id,
      };
      if (ids.isNotEmpty) result[accountId] = ids;
    });
    return result;
  }
}
