import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../utils/logger.dart';
import 'persisted_setting.dart';

abstract final class NativeGlass {
  static const String glassViewType = 'promax/native_glass';
  static const String tabBarViewType = 'promax/native_tab_bar';
  static const MethodChannel _support = MethodChannel(
    'promax/native_glass_support',
  );

  static final PersistedSetting<bool> _setting = PersistedSetting<bool>(
    prefKey: 'app_native_glass',
    defaultValue: true,
    read: (prefs, key) => prefs.getBool(key),
    write: (prefs, key, value) => prefs.setBool(key, value),
  );

  static bool _supported = false;
  static Future<void>? _loading;

  static bool get isSupported => _supported;

  static ValueListenable<bool> get enabled => _setting.current;

  static bool get active => _supported && _setting.current.value;

  static bool get _platformCanHost =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  static Future<void> load() => _loading ??= _load();

  static Future<void> _load() async {
    await _setting.load();
    if (!_platformCanHost) return;
    try {
      _supported = await _support.invokeMethod<bool>('isSupported') ?? false;
    } on PlatformException catch (e) {
      logger.w('Системное стекло iOS: ошибка проверки ($e)');
      _supported = false;
    } on MissingPluginException {
      logger.w('Системное стекло iOS: канал не зарегистрирован');
      _supported = false;
    }
    logger.i(
      'Системное стекло iOS: ${_supported ? 'поддерживается' : 'не поддерживается'}, '
      'переключатель ${_setting.current.value ? 'включён' : 'выключен'}',
    );
  }

  static Future<void> save(bool value) => _setting.save(value);

  @visibleForTesting
  static void debugOverride({bool? supported, bool? enabled}) {
    if (supported != null) _supported = supported;
    if (enabled != null) _setting.current.value = enabled;
  }

  @visibleForTesting
  static void debugReset() {
    _supported = false;
    _loading = null;
    _setting.current.value = true;
  }
}
