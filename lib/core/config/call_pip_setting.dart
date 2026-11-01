import 'package:flutter/foundation.dart';

import 'persisted_setting.dart';

class CallPipSetting {
  CallPipSetting._();

  static const prefKey = 'call_pip_enabled';

  static final _setting = PersistedSetting<bool>(
    prefKey: prefKey,
    defaultValue: true,
    read: (prefs, key) => prefs.getBool(key),
    write: (prefs, key, value) async {
      await prefs.setBool(key, value);
    },
  );

  static ValueNotifier<bool> get current => _setting.current;

  static Future<bool> load() => _setting.load();

  static Future<void> save(bool value) => _setting.save(value);
}
