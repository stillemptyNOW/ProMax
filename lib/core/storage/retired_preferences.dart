import 'package:shared_preferences/shared_preferences.dart';

abstract final class RetiredPreferences {
  static const keys = {'promax_ignored_senders', 'promax_streamer_mode'};

  static Future<void> purge(SharedPreferences prefs) async {
    for (final key in keys) {
      if (prefs.containsKey(key)) await prefs.remove(key);
    }
  }
}
