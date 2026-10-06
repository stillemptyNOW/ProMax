import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class QuickRepliesStore {
  QuickRepliesStore._();

  static final QuickRepliesStore instance = QuickRepliesStore._();

  static const prefKey = 'promax_quick_replies';
  static const int maxCount = 50;
  static const int maxLength = 2000;

  final ValueNotifier<List<String>> items = ValueNotifier(const []);

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    items.value = List.unmodifiable([
      for (final text in prefs.getStringList(prefKey) ?? const <String>[])
        if (text.trim().isNotEmpty) text,
    ]);
  }

  Future<bool> add(String text) async {
    final clean = _clean(text);
    if (clean == null || items.value.length >= maxCount) return false;
    if (items.value.contains(clean)) return true;
    await _save([...items.value, clean]);
    return true;
  }

  Future<void> update(int index, String text) async {
    if (index < 0 || index >= items.value.length) return;
    final clean = _clean(text);
    final next = [...items.value];
    if (clean == null) {
      next.removeAt(index);
    } else {
      next[index] = clean;
    }
    await _save(next);
  }

  Future<void> removeAt(int index) => update(index, '');

  Future<void> move(int from, int to) async {
    final next = [...items.value];
    if (from < 0 || from >= next.length) return;
    final item = next.removeAt(from);
    next.insert(to.clamp(0, next.length), item);
    await _save(next);
  }

  String? _clean(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return null;
    return trimmed.length > maxLength
        ? trimmed.substring(0, maxLength)
        : trimmed;
  }

  Future<void> _save(List<String> next) async {
    items.value = List.unmodifiable(next);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(prefKey, next);
  }
}
