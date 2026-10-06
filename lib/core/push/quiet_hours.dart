import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

@immutable
class QuietWindow {
  const QuietWindow(this.startHour, this.endHour, {this.weekdaysOnly = false});

  final int startHour;
  final int endHour;
  final bool weekdaysOnly;

  String get label {
    final range =
        '${startHour.toString().padLeft(2, '0')}:00–${endHour.toString().padLeft(2, '0')}:00';
    return weekdaysOnly ? '$range по будням' : range;
  }

  bool covers(DateTime time) {
    if (weekdaysOnly && time.weekday > DateTime.friday) return false;
    final hour = time.hour;
    if (startHour == endHour) return true;
    if (startHour < endHour) return hour >= startHour && hour < endHour;
    return hour >= startHour || hour < endHour;
  }

  Map<String, Object> toJson() => {
    's': startHour,
    'e': endHour,
    'w': weekdaysOnly,
  };

  static QuietWindow? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final start = raw['s'];
    final end = raw['e'];
    if (start is! int || end is! int) return null;
    if (start < 0 || start > 23 || end < 0 || end > 23) return null;
    return QuietWindow(start, end, weekdaysOnly: raw['w'] == true);
  }

  @override
  bool operator ==(Object other) =>
      other is QuietWindow &&
      other.startHour == startHour &&
      other.endHour == endHour &&
      other.weekdaysOnly == weekdaysOnly;

  @override
  int get hashCode => Object.hash(startHour, endHour, weekdaysOnly);
}

class QuietHours {
  QuietHours._();

  static final QuietHours instance = QuietHours._();

  static const prefKey = 'promax_quiet_hours';

  static const List<QuietWindow> presets = [
    QuietWindow(22, 8),
    QuietWindow(23, 7),
    QuietWindow(0, 9),
    QuietWindow(9, 18, weekdaysOnly: true),
  ];

  final ValueNotifier<Map<int, QuietWindow>> windows = ValueNotifier(const {});

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(prefKey);
    if (raw == null) return;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return;
      windows.value = Map.unmodifiable({
        for (final entry in decoded.entries)
          if (int.tryParse('${entry.key}') != null &&
              QuietWindow.fromJson(entry.value) != null)
            int.parse('${entry.key}'): QuietWindow.fromJson(entry.value)!,
      });
    } catch (_) {}
  }

  QuietWindow? windowFor(int chatId) => windows.value[chatId];

  bool isQuiet(int chatId, [DateTime? at]) =>
      windowFor(chatId)?.covers(at ?? DateTime.now()) ?? false;

  Future<void> set(int chatId, QuietWindow? window) async {
    final next = Map<int, QuietWindow>.of(windows.value);
    if (window == null) {
      next.remove(chatId);
    } else {
      next[chatId] = window;
    }
    windows.value = Map.unmodifiable(next);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      prefKey,
      jsonEncode({for (final e in next.entries) '${e.key}': e.value.toJson()}),
    );
  }
}
