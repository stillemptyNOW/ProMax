import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum AppIcon {
  defaultIcon(
    'default',
    'Классическая',
    'assets/promax_icon.png',
    'MainActivity',
    null,
  ),
  light('light', 'Светлая', 'assets/icons/promax_light.png', null, 'IconLight'),
  aurora('aurora', 'Аврора', 'assets/icons/promax_aurora.png', null, 'IconAurora'),
  sunset('sunset', 'Закат', 'assets/icons/promax_sunset.png', null, 'IconSunset'),
  glass('glass', 'Стекло', 'assets/icons/promax_glass.png', null, 'IconGlass');

  final String id;
  final String title;
  final String previewAsset;
  final String? androidAlias;
  final String? iosAlternateName;

  const AppIcon(
    this.id,
    this.title,
    this.previewAsset,
    this.androidAlias,
    this.iosAlternateName,
  );

  bool get availableOnAndroid => androidAlias != null;

  static List<AppIcon> forPlatform({required bool ios}) =>
      ios ? values : values.where((icon) => icon.availableOnAndroid).toList();
}

// #***! переключение иконки
class AppIconConfig {
  static const prefKey = 'app_icon';
  static const _channel = MethodChannel('io.github.stillemptynow.promax/app_icon');

  static final ValueNotifier<AppIcon> current = ValueNotifier(
    AppIcon.defaultIcon,
  );

  // #***! на десктопе и в вебе иконку не поменять
  static bool get isSupported => Platform.isAndroid || Platform.isIOS;

  static List<AppIcon> get available =>
      AppIcon.forPlatform(ios: !kIsWeb && Platform.isIOS);

  // #***! иос может сбросить иконку сам, на старте сверяемся
  static Future<void> load() async {
    if (!isSupported) return;
    final prefs = await SharedPreferences.getInstance();
    var icon = _parse(prefs.getString(prefKey));
    final applied = await _appliedIcon();
    if (applied != null && applied != icon) {
      icon = applied;
      await prefs.setString(prefKey, icon.id);
    }
    current.value = icon;
  }

  // #***! меняем через натив потом сохраняем выбор
  static Future<void> apply(AppIcon icon) async {
    if (!isSupported) return;
    if (current.value == icon) return;
    await _channel.invokeMethod<void>('setAppIcon', {
      'name': Platform.isIOS ? icon.iosAlternateName : icon.androidAlias,
    });
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(prefKey, icon.id);
    current.value = icon;
  }

  static Future<AppIcon?> _appliedIcon() async {
    if (!Platform.isIOS) return null;
    try {
      final name = await _channel.invokeMethod<String>('getAppIcon');
      for (final icon in AppIcon.values) {
        if (icon.iosAlternateName == name) return icon;
      }
    } catch (_) {}
    return null;
  }

  static AppIcon _parse(String? val) {
    for (final icon in AppIcon.values) {
      if (icon.id == val) return icon;
    }
    return AppIcon.defaultIcon;
  }
}
