import 'dart:collection';

import 'translation_backend.dart';

class TranslationCache {
  TranslationCache({this.capacity = 500});

  final int capacity;
  final LinkedHashMap<String, TranslationOutput> _entries =
      LinkedHashMap<String, TranslationOutput>();

  int get length => _entries.length;

  static String keyOf(String target, String text) => '$target\u0000$text';

  TranslationOutput? get(String target, String text) {
    final key = keyOf(target, text);
    final hit = _entries.remove(key);
    if (hit == null) return null;
    _entries[key] = hit;
    return hit;
  }

  void put(String target, String text, TranslationOutput output) {
    final key = keyOf(target, text);
    _entries.remove(key);
    _entries[key] = output;
    while (_entries.length > capacity) {
      _entries.remove(_entries.keys.first);
    }
  }

  void clear() => _entries.clear();
}
