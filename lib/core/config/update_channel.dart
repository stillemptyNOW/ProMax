import 'package:flutter/foundation.dart';
import 'persisted_setting.dart';

abstract final class UpdateChannel {
  static final _setting = PersistedSetting<bool>(
    prefKey: 'receive_beta_updates',
    defaultValue: false,
    read: (prefs, key) => prefs.getBool(key),
    write: (prefs, key, value) => prefs.setBool(key, value),
  );
  static ValueNotifier<bool> get beta => _setting.current;
  static Future<void> load() async {
    await _setting.load();
  }

  static Future<void> setBeta(bool value) => _setting.save(value);
}
