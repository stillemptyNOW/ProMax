import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class AccountPhoneStore {
  AccountPhoneStore._();

  static const String storageKey = 'promax_account_phones_v1';

  static Future<Map<String, int>> _read(SharedPreferences prefs) async {
    final raw = prefs.getString(storageKey);
    if (raw == null) return {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return {};
      return {
        for (final entry in decoded.entries)
          if (entry.value is int) '${entry.key}': entry.value as int,
      };
    } catch (_) {
      return {};
    }
  }

  static Future<void> remember(int accountId, int phone) async {
    if (accountId == 0 || phone <= 0) return;
    final prefs = await SharedPreferences.getInstance();
    final phones = await _read(prefs);
    if (phones['$accountId'] == phone) return;
    phones['$accountId'] = phone;
    await prefs.setString(storageKey, jsonEncode(phones));
  }

  static Future<int?> phoneOf(int accountId) async {
    final prefs = await SharedPreferences.getInstance();
    final phone = (await _read(prefs))['$accountId'];
    return phone != null && phone > 0 ? phone : null;
  }

  static Future<void> forget(int accountId) async {
    final prefs = await SharedPreferences.getInstance();
    final phones = await _read(prefs);
    if (phones.remove('$accountId') == null) return;
    await prefs.setString(storageKey, jsonEncode(phones));
  }
}
