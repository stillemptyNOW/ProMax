import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_icon_catalog.dart';

export 'app_icon_catalog.dart';

class AppIconConfig {
  static const prefKey = 'app_icon';
  static const seasonalPrefKey = 'app_icon_seasonal';
  static const manualSeasonPrefKey = 'app_icon_manual_season';
  static const autoAppliedPrefKey = 'app_icon_auto_applied';
  static const autoAttemptPrefKey = 'app_icon_auto_attempt';
  static const _channel = MethodChannel(
    'io.github.stillemptynow.promax/app_icon',
  );

  static final AppIconPlatform platform = AppIconPlatform.resolve(
    web: kIsWeb,
    target: defaultTargetPlatform,
  );

  static final ValueNotifier<AppIconSelection> selection = ValueNotifier(
    const AppIconSelection(),
  );
  static final ValueNotifier<AppIcon> applied = ValueNotifier(
    AppIcon.defaultIcon,
  );
  static final ValueNotifier<AppIcon?> pending = ValueNotifier(null);

  static String? _autoApplied;
  static Future<void>? _loading;
  static bool _switching = false;

  static bool get isSupported => platform.canSwitch;

  static List<AppIcon> get available => AppIcon.values;

  static Future<void> load() => _loading ??= _load();

  static Future<void> _load() async {
    if (!isSupported) return;
    final prefs = await SharedPreferences.getInstance();
    var loaded = AppIconSelection(
      choice: AppIcon.byId(prefs.getString(prefKey)) ?? AppIcon.defaultIcon,
      seasonal: prefs.getBool(seasonalPrefKey) ?? false,
      manualSeason: prefs.getString(manualSeasonPrefKey),
    );
    _autoApplied = prefs.getString(autoAppliedPrefKey);
    if (platform.readsAppliedIcon) {
      applied.value = await _readApplied();
      final adopted = AppIconAutoSwitch.adopt(
        selection: loaded,
        applied: applied.value,
        autoApplied: _autoApplied,
      );
      if (adopted != loaded) {
        loaded = adopted;
        await _persistSelection(prefs, loaded);
      }
    }
    selection.value = loaded;
  }

  static Future<void> refresh() async {
    await load();
    if (!isSupported || _switching) return;
    final target = AppIconAutoSwitch.target(
      selection: selection.value,
      applied: applied.value,
      now: DateTime.now(),
      autoApplied: _autoApplied,
      appliedResetsOnLaunch: platform.resetsOnLaunch,
    );
    if (target == null) {
      pending.value = null;
      return;
    }
    if (platform.defersAutomaticSwitch) {
      pending.value = target;
      return;
    }
    await _applyAutomatically(target);
  }

  static Future<void> onBackground() async {
    final target = pending.value;
    if (target == null || _switching || !platform.defersAutomaticSwitch) {
      return;
    }
    pending.value = null;
    final prefs = await SharedPreferences.getInstance();
    final attempt = AppIconAutoSwitch.attemptKey(target, DateTime.now());
    if (prefs.getString(autoAttemptPrefKey) == attempt) return;
    await prefs.setString(autoAttemptPrefKey, attempt);
    await _applyAutomatically(target);
  }

  static Future<void> choose(AppIcon icon) async {
    await load();
    if (!isSupported) return;
    final prefs = await SharedPreferences.getInstance();
    final previous = selection.value;
    final next = previous.pick(icon, DateTime.now());
    await _persistSelection(prefs, next);
    await _setAutoApplied(prefs, null);
    try {
      if (applied.value != icon) {
        await _invoke(icon, closeApp: true);
        applied.value = icon;
      }
    } catch (_) {
      await _persistSelection(prefs, previous);
      rethrow;
    }
    selection.value = next;
    pending.value = null;
  }

  static Future<void> setSeasonal(bool enabled) async {
    await load();
    if (!isSupported) return;
    final prefs = await SharedPreferences.getInstance();
    final next = selection.value.withSeasonal(enabled);
    await _persistSelection(prefs, next);
    selection.value = next;
    await refresh();
  }

  static Future<void> _applyAutomatically(AppIcon target) async {
    _switching = true;
    try {
      await _invoke(target, closeApp: false);
      applied.value = target;
      pending.value = null;
      final prefs = await SharedPreferences.getInstance();
      await _setAutoApplied(
        prefs,
        target == selection.value.choice ? null : target.id,
      );
    } catch (e) {
      debugPrint('AppIconConfig: automatic switch failed: $e');
    } finally {
      _switching = false;
    }
  }

  static Future<void> _invoke(AppIcon icon, {required bool closeApp}) async {
    final arguments = <String, Object?>{
      'name': platform == AppIconPlatform.ios
          ? icon.iosAlternateName
          : icon.nativeName,
      if (platform == AppIconPlatform.android) 'closeApp': closeApp,
      if (platform.sendsIconImage) 'image': await _iconImage(icon),
    };
    await _channel.invokeMethod<void>('setAppIcon', arguments);
  }

  static Future<Uint8List?> _iconImage(AppIcon icon) async {
    if (icon == AppIcon.defaultIcon) return null;
    final data = await rootBundle.load(icon.previewAsset);
    return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  }

  static Future<AppIcon> _readApplied() async {
    try {
      final name = await _channel.invokeMethod<String>('getAppIcon');
      return AppIcon.byNativeName(name) ?? AppIcon.defaultIcon;
    } catch (_) {
      return AppIcon.defaultIcon;
    }
  }

  static Future<void> _persistSelection(
    SharedPreferences prefs,
    AppIconSelection value,
  ) async {
    await prefs.setString(prefKey, value.choice.id);
    await prefs.setBool(seasonalPrefKey, value.seasonal);
    final manual = value.manualSeason;
    if (manual == null) {
      await prefs.remove(manualSeasonPrefKey);
    } else {
      await prefs.setString(manualSeasonPrefKey, manual);
    }
  }

  static Future<void> _setAutoApplied(
    SharedPreferences prefs,
    String? id,
  ) async {
    _autoApplied = id;
    if (id == null) {
      await prefs.remove(autoAppliedPrefKey);
    } else {
      await prefs.setString(autoAppliedPrefKey, id);
    }
  }
}
