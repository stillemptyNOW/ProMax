import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'persisted_setting.dart';
import 'promax_glass.dart';

enum AtmosphereEffect {
  none('Выключено'),
  snow('Снег'),
  rain('Дождь'),
  stars('Звёзды'),
  leaves('Листопад'),
  sakura('Сакура'),
  hearts('Сердечки'),
  confetti('Конфетти'),
  sparkles('Искры'),
  bubbles('Пузыри'),
  fireflies('Светлячки');

  const AtmosphereEffect(this.title);

  final String title;
}

enum AtmosphereScope {
  everywhere('Везде'),
  chats('Только в чатах');

  const AtmosphereScope(this.title);

  final String title;
}

@immutable
class AtmosphereBurst {
  const AtmosphereBurst(this.effect, this.chatId, this.serial);

  final AtmosphereEffect effect;
  final int chatId;
  final int serial;
}

class ProMaxAtmosphere {
  static const effectKey = 'promax_atmosphere_effect';
  static const scopeKey = 'promax_atmosphere_scope';
  static const colorKey = 'promax_atmosphere_color';
  static const triggersKey = 'promax_atmosphere_triggers';
  static const chatsKey = 'promax_atmosphere_chats';

  static final _effect = PersistedEnum<AtmosphereEffect>(
    prefKey: effectKey,
    defaultValue: AtmosphereEffect.none,
    encode: (value) => value.name,
    decode: (raw) =>
        enumFromName(AtmosphereEffect.values, raw, AtmosphereEffect.none),
  );

  static final _scope = PersistedEnum<AtmosphereScope>(
    prefKey: scopeKey,
    defaultValue: AtmosphereScope.everywhere,
    encode: (value) => value.name,
    decode: (raw) =>
        enumFromName(AtmosphereScope.values, raw, AtmosphereScope.everywhere),
  );

  static final density = GlassParameter(
    prefKey: 'promax_atmosphere_density',
    defaultValue: 1,
    min: 0.2,
    max: 3,
  );
  static final speed = GlassParameter(
    prefKey: 'promax_atmosphere_speed',
    defaultValue: 1,
    min: 0.2,
    max: 3,
  );
  static final size = GlassParameter(
    prefKey: 'promax_atmosphere_size',
    defaultValue: 1,
    min: 0.4,
    max: 2.5,
  );
  static final opacity = GlassParameter(
    prefKey: 'promax_atmosphere_opacity',
    defaultValue: 0.7,
    min: 0.1,
    max: 1,
  );
  static final wind = GlassParameter(
    prefKey: 'promax_atmosphere_wind',
    defaultValue: 0,
    min: -1,
    max: 1,
  );

  static final _color = PersistedSetting<int>(
    prefKey: colorKey,
    defaultValue: 0,
    read: (prefs, key) => prefs.getInt(key),
    write: (prefs, key, value) async => prefs.setInt(key, value),
  );

  static final _triggers = PersistedSetting<bool>(
    prefKey: triggersKey,
    defaultValue: true,
    read: (prefs, key) => prefs.getBool(key),
    write: (prefs, key, value) async => prefs.setBool(key, value),
  );

  static final ValueNotifier<Map<int, AtmosphereEffect>> chatEffects =
      ValueNotifier(const {});

  static final ValueNotifier<AtmosphereBurst?> burst = ValueNotifier(null);
  static int _burstSerial = 0;

  static ValueNotifier<AtmosphereEffect> get effect => _effect.current;
  static ValueNotifier<AtmosphereScope> get scope => _scope.current;
  static ValueNotifier<int> get color => _color.current;
  static ValueNotifier<bool> get triggers => _triggers.current;

  static List<GlassParameter> get parameters => [
    density,
    speed,
    size,
    opacity,
    wind,
  ];

  static final Listenable listenable = Listenable.merge([
    effect,
    scope,
    color,
    for (final parameter in parameters) parameter.current,
  ]);

  static Future<void> load() async {
    await Future.wait([
      _effect.load(),
      _scope.load(),
      _color.load(),
      _triggers.load(),
      for (final parameter in parameters) parameter.load(),
    ]);
    final prefs = await SharedPreferences.getInstance();
    chatEffects.value = decodeChatEffects(prefs.getString(chatsKey));
  }

  static Future<void> setEffect(AtmosphereEffect value) => _effect.save(value);

  static Future<void> setScope(AtmosphereScope value) => _scope.save(value);

  static Future<void> setColor(int value) => _color.save(value);

  static Future<void> setTriggers(bool value) => _triggers.save(value);

  static Future<void> resetTuning() =>
      Future.wait([for (final parameter in parameters) parameter.reset()]);

  static AtmosphereEffect? chatEffect(int chatId) => chatEffects.value[chatId];

  static Future<void> setChatEffect(int chatId, AtmosphereEffect? value) async {
    final next = Map<int, AtmosphereEffect>.of(chatEffects.value);
    if (value == null) {
      next.remove(chatId);
    } else {
      next[chatId] = value;
    }
    chatEffects.value = Map.unmodifiable(next);
    final prefs = await SharedPreferences.getInstance();
    if (next.isEmpty) {
      await prefs.remove(chatsKey);
    } else {
      await prefs.setString(chatsKey, encodeChatEffects(next));
    }
  }

  static AtmosphereEffect resolveForChat(int chatId) =>
      chatEffect(chatId) ?? AtmosphereEffect.none;

  static bool get showsGlobally =>
      effect.value != AtmosphereEffect.none &&
      scope.value == AtmosphereScope.everywhere;

  static AtmosphereEffect chatLayerEffect(int chatId) {
    final own = chatEffect(chatId);
    if (own != null) return own;
    if (scope.value == AtmosphereScope.chats) return effect.value;
    return AtmosphereEffect.none;
  }

  static void react(int chatId, String text) {
    if (!triggers.value) return;
    final found = triggerFor(text);
    if (found == null) return;
    burst.value = AtmosphereBurst(found, chatId, ++_burstSerial);
  }

  static final List<(RegExp, AtmosphereEffect)> _triggerRules = [
    (
      RegExp(
        r'(дн[её]м рождени|(^|\s)с др($|[\s!.,)])|поздравл|🎉|🥳|🎂)',
        caseSensitive: false,
        unicode: true,
      ),
      AtmosphereEffect.confetti,
    ),
    (
      RegExp(
        r'(люблю|любим(ая|ый|ка)|❤|💕|💖|💘|😍|🥰)',
        caseSensitive: false,
        unicode: true,
      ),
      AtmosphereEffect.hearts,
    ),
    (
      RegExp(r'(с новым годом|❄|☃|🎄|⛄)', caseSensitive: false, unicode: true),
      AtmosphereEffect.snow,
    ),
    (RegExp(r'(✨|🌟|⭐|💫)', unicode: true), AtmosphereEffect.sparkles),
    (RegExp(r'(🌸|💮|🌷)', unicode: true), AtmosphereEffect.sakura),
    (RegExp(r'(🍂|🍁)', unicode: true), AtmosphereEffect.leaves),
  ];

  static AtmosphereEffect? triggerFor(String text) {
    if (text.isEmpty || text.length > 4000) return null;
    for (final (pattern, effect) in _triggerRules) {
      if (pattern.hasMatch(text)) return effect;
    }
    return null;
  }

  static String encodeChatEffects(Map<int, AtmosphereEffect> effects) =>
      jsonEncode({
        for (final entry in effects.entries)
          entry.key.toString(): entry.value.name,
      });

  static Map<int, AtmosphereEffect> decodeChatEffects(String? raw) {
    if (raw == null || raw.isEmpty) return const {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return const {};
      final result = <int, AtmosphereEffect>{};
      for (final entry in decoded.entries) {
        final id = int.tryParse(entry.key.toString());
        final value = entry.value;
        if (id == null || value is! String) continue;
        final effect = AtmosphereEffect.values
            .where((e) => e.name == value)
            .firstOrNull;
        if (effect != null) result[id] = effect;
      }
      return Map.unmodifiable(result);
    } catch (_) {
      return const {};
    }
  }
}
