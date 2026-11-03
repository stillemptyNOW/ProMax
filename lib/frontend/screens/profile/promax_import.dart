import 'package:flutter/material.dart';

import '../../../core/config/app_accent.dart';
import '../../../core/config/app_design.dart';
import '../../../core/config/app_amoled.dart';
import '../../../core/config/app_theme_mode.dart';
import '../../../core/config/app_video_note_quality.dart';
import '../../../core/config/promax_archive.dart';
import '../../../core/config/promax_atmosphere.dart';
import '../../../core/config/promax_glass.dart';
import '../../../core/config/promax_theme_presets.dart';
import '../../../core/config/promax_aura.dart';
import '../../../core/config/promax_nav.dart';
import '../../../core/config/app_performance.dart';
import '../../../core/config/app_native_glass.dart';
import '../../../core/config/call_pip_setting.dart';
import '../../../core/config/platform_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../main.dart';

Future<int> applyProMaxArchive(
  BuildContext context,
  Map<String, dynamic> data, {
  Map<String, dynamic>? deleted,
}) async {
  final restored = await ProMaxArchive.apply(data, deleted: deleted);
  await AppThemeModeConfig.load();
  await AppAmoled.load();
  await AppDesign.load();
  await AppVideoNoteResolution.load();
  await AppVideoNoteFps.load();
  await AppVideoNoteRearCamera.load();
  await ProMaxGlass.load();
  await ProMaxAtmosphere.load();
  await ProMaxThemePresets.load();
  await ProMaxAura.load();
  await ProMaxNavLayout.load();
  await ProMaxIconTiles.load();
  await AppPerformance.load();
  await CallPipSetting.load();
  if (PlatformSettings.current == 'ios') {
    final prefs = await SharedPreferences.getInstance();
    await NativeGlass.save(prefs.getBool('app_native_glass') ?? true);
  }
  if (!context.mounted) return restored;
  final prefs = await ProMaxArchive.settings();
  if (!context.mounted) return restored;
  final app = ProMaxApp.stateOf(context);
  if (prefs['app_theme_mode'] is String) {
    await app?.applyThemeMode(AppThemeModeConfig.current.value);
  }
  if (prefs['app_amoled'] is bool) {
    await app?.applyAmoled(AppAmoled.current.value);
  }
  if (prefs['app_accent_seed'] is int) {
    await app?.applyAccentColor(await AppAccent.load());
  }
  if (prefs['app_font'] is String) {
    await app?.applyAppFont(prefs['app_font'] as String);
  }
  if (prefs['app_font_scale'] is num) {
    await app?.applyFontScale((prefs['app_font_scale'] as num).toDouble());
  }
  api.refreshPresence();
  return restored;
}
