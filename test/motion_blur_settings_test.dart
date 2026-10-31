import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:promax/core/plugins/motion_blur/motion_blur_plugin.dart';
import 'package:promax/core/plugins/motion_blur/motion_blur_settings.dart';
import 'package:promax/core/plugins/native_plugin.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() => MotionBlurPlugin.instance.debugOverride());

  group('MotionBlurSettings', () {
    test('defaults to installed but disabled with moderate strength', () {
      const settings = MotionBlurSettings();
      expect(settings.enabled, isFalse);
      expect(settings.strength, MotionBlurSettings.defaultStrength);
      expect(settings.strength, lessThan(MotionBlurSettings.maxStrength / 2));
      expect(settings.quality, MotionBlurQuality.balanced);
      expect(settings.targets, MotionBlurSettings.allTargets);
      expect(settings.allows(MotionBlurTarget.scrolling), isFalse);
    });

    test('round-trips through JSON', () {
      final settings = const MotionBlurSettings().copyWith(
        enabled: true,
        strength: 28,
        sensitivity: 1.75,
        quality: MotionBlurQuality.high,
        targets: {MotionBlurTarget.scrolling, MotionBlurTarget.lens},
      );
      final restored = MotionBlurSettings.fromJson(
        jsonDecode(jsonEncode(settings.toJson())),
      );
      expect(restored, settings);
      expect(restored.allows(MotionBlurTarget.scrolling), isTrue);
      expect(restored.allows(MotionBlurTarget.transitions), isFalse);
    });

    test('falls back and clamps on damaged data', () {
      expect(MotionBlurSettings.fromJson('broken'), const MotionBlurSettings());
      final clamped = MotionBlurSettings.fromJson({
        'enabled': 'yes',
        'strength': 999,
        'sensitivity': -3,
        'quality': 'ultra',
        'targets': ['pages', 'unknown'],
      });
      expect(clamped.enabled, isFalse);
      expect(clamped.strength, MotionBlurSettings.maxStrength);
      expect(clamped.sensitivity, MotionBlurSettings.minSensitivity);
      expect(clamped.quality, MotionBlurQuality.balanced);
      expect(clamped.targets, {MotionBlurTarget.pages});
    });

    test('toggles one target at a time', () {
      final settings = const MotionBlurSettings().withTarget(
        MotionBlurTarget.lens,
        false,
      );
      expect(settings.targets.contains(MotionBlurTarget.lens), isFalse);
      expect(
        settings.withTarget(MotionBlurTarget.lens, true).targets,
        MotionBlurSettings.allTargets,
      );
    });
  });

  group('MotionBlurPlugin', () {
    test('is registered as a native built-in', () {
      expect(NativePlugins.all, contains(MotionBlurPlugin.instance));
      expect(MotionBlurPlugin.instance.id, MotionBlurPlugin.pluginId);
    });

    test('loads disabled when nothing is stored', () async {
      SharedPreferences.setMockInitialValues({});
      await MotionBlurPlugin.instance.load();
      expect(MotionBlurPlugin.instance.enabled.value, isFalse);
      expect(
        MotionBlurPlugin.instance.settings.value,
        const MotionBlurSettings(),
      );
    });

    test('persists edits and restores them on the next start', () async {
      SharedPreferences.setMockInitialValues({});
      final plugin = MotionBlurPlugin.instance;
      await plugin.load();
      await plugin.update(
        plugin.settings.value
            .copyWith(strength: 22, quality: MotionBlurQuality.low)
            .withTarget(MotionBlurTarget.transitions, false),
      );
      await plugin.setEnabled(true);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(MotionBlurPlugin.prefKey), isNotNull);

      plugin.debugOverride();
      expect(plugin.enabled.value, isFalse);
      await plugin.load();
      final restored = plugin.settings.value;
      expect(plugin.enabled.value, isTrue);
      expect(restored.strength, 22);
      expect(restored.quality, MotionBlurQuality.low);
      expect(restored.targets.contains(MotionBlurTarget.transitions), isFalse);
      expect(plugin.allows(MotionBlurTarget.scrolling), isTrue);
      expect(plugin.allows(MotionBlurTarget.transitions), isFalse);
    });

    test('preview changes memory only', () async {
      SharedPreferences.setMockInitialValues({});
      final plugin = MotionBlurPlugin.instance;
      await plugin.load();
      plugin.preview(plugin.settings.value.copyWith(strength: 30));
      expect(plugin.settings.value.strength, 30);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(MotionBlurPlugin.prefKey), isNull);
    });
  });
}
