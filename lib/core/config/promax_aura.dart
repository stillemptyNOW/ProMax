import 'package:flutter/foundation.dart';

import 'persisted_setting.dart';

class ProMaxAura {
  static const prefKey = 'promax_chat_aura';

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
