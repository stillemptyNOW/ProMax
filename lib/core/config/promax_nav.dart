import 'package:flutter/foundation.dart';

import 'persisted_setting.dart';

class ProMaxNavLayout {
  static const prefKey = 'promax_nav_tabs';

  static final _setting = PersistedSetting<bool>(
    prefKey: prefKey,
    defaultValue: true,
    read: (prefs, key) => prefs.getBool(key),
    write: (prefs, key, value) async => prefs.setBool(key, value),
  );

  static ValueNotifier<bool> get tabs => _setting.current;

  static Future<bool> load() => _setting.load();

  static Future<void> save(bool value) => _setting.save(value);
}

class ProMaxIconTiles {
  static const prefKey = 'promax_icon_tiles';

  static final _setting = PersistedSetting<bool>(
    prefKey: prefKey,
    defaultValue: true,
    read: (prefs, key) => prefs.getBool(key),
    write: (prefs, key, value) async => prefs.setBool(key, value),
  );

  static ValueNotifier<bool> get enabled => _setting.current;

  static Future<bool> load() => _setting.load();

  static Future<void> save(bool value) => _setting.save(value);
}
