import 'package:flutter_test/flutter_test.dart';
import 'package:promax/core/config/promax_archive.dart';
import 'package:promax/core/config/promax_atmosphere.dart';
import 'package:promax/core/config/promax_glass.dart';
import 'package:promax/core/config/promax_theme_presets.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('keyword triggers pick the matching effect', () {
    expect(
      ProMaxAtmosphere.triggerFor('С днём рождения, синтетика!'),
      AtmosphereEffect.confetti,
    );
    expect(ProMaxAtmosphere.triggerFor('с др 🎉'), AtmosphereEffect.confetti);
    expect(ProMaxAtmosphere.triggerFor('Люблю тебя'), AtmosphereEffect.hearts);
    expect(ProMaxAtmosphere.triggerFor('С Новым годом'), AtmosphereEffect.snow);
    expect(ProMaxAtmosphere.triggerFor('вау ✨'), AtmosphereEffect.sparkles);
    expect(ProMaxAtmosphere.triggerFor('обычный текст'), isNull);
    expect(ProMaxAtmosphere.triggerFor(''), isNull);
  });

  test('a burst fires only when triggers are enabled', () async {
    await ProMaxAtmosphere.load();
    ProMaxAtmosphere.burst.value = null;
    await ProMaxAtmosphere.setTriggers(false);
    ProMaxAtmosphere.react(7, 'люблю');
    expect(ProMaxAtmosphere.burst.value, isNull);
    await ProMaxAtmosphere.setTriggers(true);
    ProMaxAtmosphere.react(7, 'люблю');
    expect(ProMaxAtmosphere.burst.value?.effect, AtmosphereEffect.hearts);
    expect(ProMaxAtmosphere.burst.value?.chatId, 7);
  });

  test('per-chat effects survive a reload and ignore garbage', () async {
    await ProMaxAtmosphere.load();
    await ProMaxAtmosphere.setChatEffect(-42, AtmosphereEffect.rain);
    await ProMaxAtmosphere.setChatEffect(9, AtmosphereEffect.stars);
    await ProMaxAtmosphere.setChatEffect(9, null);
    ProMaxAtmosphere.chatEffects.value = const {};
    await ProMaxAtmosphere.load();
    expect(ProMaxAtmosphere.chatEffect(-42), AtmosphereEffect.rain);
    expect(ProMaxAtmosphere.chatEffect(9), isNull);
    expect(ProMaxAtmosphere.decodeChatEffects('{"1":"nope","x":"snow"}'), {});
    expect(ProMaxAtmosphere.decodeChatEffects('not json'), {});
  });

  test('chat layer respects scope and own overrides', () async {
    await ProMaxAtmosphere.load();
    await ProMaxAtmosphere.setEffect(AtmosphereEffect.snow);
    await ProMaxAtmosphere.setScope(AtmosphereScope.everywhere);
    expect(ProMaxAtmosphere.chatLayerEffect(1), AtmosphereEffect.none);
    await ProMaxAtmosphere.setScope(AtmosphereScope.chats);
    expect(ProMaxAtmosphere.chatLayerEffect(1), AtmosphereEffect.snow);
    await ProMaxAtmosphere.setChatEffect(1, AtmosphereEffect.hearts);
    expect(ProMaxAtmosphere.chatLayerEffect(1), AtmosphereEffect.hearts);
  });

  test('glass parameters are clamped to their range', () async {
    await ProMaxGlass.load();
    await ProMaxGlass.blur.save(99);
    expect(ProMaxGlass.blur.value, ProMaxGlass.blur.max);
    await ProMaxGlass.refraction.save(-5);
    expect(ProMaxGlass.refraction.value, ProMaxGlass.refraction.min);
    await ProMaxGlass.reset();
    expect(ProMaxGlass.blur.value, ProMaxGlass.blur.defaultValue);
  });

  test('first launch applies the graphite look once', () async {
    await ProMaxThemePresets.ensureDefault();
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(ProMaxThemePresets.prefKey), 'graphite');
    expect(prefs.getBool('app_amoled'), isTrue);
    await ProMaxThemePresets.remember('ocean');
    await ProMaxThemePresets.ensureDefault();
    expect(prefs.getString(ProMaxThemePresets.prefKey), 'ocean');
  });

  test('appearance settings travel in the .promax archive', () {
    expect(ProMaxArchive.validSetting('promax_glass_blur', 1.4), isTrue);
    expect(ProMaxArchive.validSetting('promax_glass_blur', 9.0), isFalse);
    expect(
      ProMaxArchive.validSetting('promax_atmosphere_effect', 'sakura'),
      isTrue,
    );
    expect(
      ProMaxArchive.validSetting('promax_atmosphere_effect', 'lava'),
      isFalse,
    );
    expect(ProMaxArchive.validSetting('promax_theme_preset', 'neon'), isTrue);
    expect(
      ProMaxArchive.validSetting('promax_atmosphere_triggers', false),
      isTrue,
    );
  });
}
