import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../utils/logger.dart';
import 'persisted_setting.dart';

abstract final class NativeIosUi {
  static const String prefKey = 'app_native_ios_ui';
  static const String chatListViewType = 'promax/native_chat_list';
  static const MethodChannel _support = MethodChannel(
    'promax/native_ui_support',
  );

  static final PersistedSetting<bool> _setting = PersistedSetting<bool>(
    prefKey: prefKey,
    defaultValue: false,
    read: (prefs, key) => prefs.getBool(key),
    write: (prefs, key, value) => prefs.setBool(key, value),
  );

  static bool _supported = false;

  static bool get platformCanHost =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  static bool get isSupported => _supported;

  static ValueListenable<bool> get enabled => _setting.current;

  static bool get active => _supported && _setting.current.value;

  static Future<void> load() async {
    await _setting.load();
    if (!platformCanHost) return;
    try {
      _supported = await _support.invokeMethod<bool>('isSupported') ?? false;
    } on PlatformException catch (e) {
      logger.w('Нативный интерфейс iOS: ошибка проверки ($e)');
      _supported = false;
    } on MissingPluginException {
      _supported = false;
    }
  }

  static Future<void> save(bool value) => _setting.save(value);

  @visibleForTesting
  static void debugOverride({bool? supported, bool? enabled}) {
    if (supported != null) _supported = supported;
    if (enabled != null) _setting.current.value = enabled;
  }
}
