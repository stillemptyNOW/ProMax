import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class DoubleBottom {
  static const secretKey = 'promax_secret_chats';
  static const activeKey = 'promax_decoy_active';

  static final ValueNotifier<Set<int>> secretChats = ValueNotifier(const {});
  static final ValueNotifier<bool> active = ValueNotifier(false);

  static final Listenable listenable = Listenable.merge([secretChats, active]);

  static Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    secretChats.value = Set.unmodifiable(
      (prefs.getStringList(secretKey) ?? const [])
          .map(int.tryParse)
          .whereType<int>(),
    );
    active.value = prefs.getBool(activeKey) ?? false;
  }

  static bool isSecret(int chatId) => secretChats.value.contains(chatId);

  static bool hides(int chatId) => active.value && isSecret(chatId);

  static Future<void> setSecret(int chatId, bool secret) async {
    final next = Set<int>.of(secretChats.value);
    if (secret) {
      next.add(chatId);
    } else {
      next.remove(chatId);
    }
    secretChats.value = Set.unmodifiable(next);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(secretKey, [for (final id in next) '$id']);
  }

  static Future<void> setActive(bool value) async {
    if (active.value == value) return;
    active.value = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(activeKey, value);
  }

  static Future<void> clear() async {
    secretChats.value = const {};
    active.value = false;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(secretKey);
    await prefs.remove(activeKey);
  }
}
