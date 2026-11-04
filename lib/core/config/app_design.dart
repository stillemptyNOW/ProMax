import 'package:flutter/foundation.dart';

import 'persisted_setting.dart';

class AppDesign {
  static const prefKey = 'promax_classic_design';

  static final _setting = PersistedSetting<bool>(
    prefKey: prefKey,
    defaultValue: false,
    read: (prefs, key) => prefs.getBool(key),
    write: (prefs, key, value) async {
      await prefs.setBool(key, value);
    },
  );

  static ValueNotifier<bool> get classic => _setting.current;

  static Future<bool> load() => _setting.load();

  static Future<void> saveClassic(bool value) => _setting.save(value);
}
