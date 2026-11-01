import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class TranslationSettings {
  TranslationSettings._();

  static final TranslationSettings instance = TranslationSettings._();

  static const targetKey = 'translation_target_language';
  static const wifiOnlyKey = 'translation_wifi_only';
  static const autoChatsKey = 'translation_auto_chats';

  final ValueNotifier<String?> targetLanguage = ValueNotifier<String?>(null);
  final ValueNotifier<bool> wifiOnly = ValueNotifier<bool>(false);
  final ValueNotifier<Set<String>> autoChats = ValueNotifier<Set<String>>(
    const {},
  );

  static String chatKey(int accountId, int chatId) => '$accountId:$chatId';

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final target = prefs.getString(targetKey);
    targetLanguage.value = target == null || target.isEmpty ? null : target;
    wifiOnly.value = prefs.getBool(wifiOnlyKey) ?? false;
    autoChats.value = Set.unmodifiable(
      prefs.getStringList(autoChatsKey) ?? const <String>[],
    );
  }

  String targetFor(String appLanguage) => targetLanguage.value ?? appLanguage;

  bool isAuto(int accountId, int chatId) =>
      autoChats.value.contains(chatKey(accountId, chatId));

  Future<void> setTargetLanguage(String? language) async {
    targetLanguage.value = language;
    final prefs = await SharedPreferences.getInstance();
    if (language == null) {
      await prefs.remove(targetKey);
    } else {
      await prefs.setString(targetKey, language);
    }
  }

  Future<void> setWifiOnly(bool value) async {
    wifiOnly.value = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(wifiOnlyKey, value);
  }

  Future<void> setAuto(int accountId, int chatId, bool enabled) async {
    final key = chatKey(accountId, chatId);
    final next = {...autoChats.value};
    if (enabled) {
      next.add(key);
    } else {
      next.remove(key);
    }
    autoChats.value = Set.unmodifiable(next);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(autoChatsKey, next.toList()..sort());
  }
}
