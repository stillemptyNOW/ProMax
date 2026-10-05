import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_accent.dart';
import 'app_amoled.dart';
import 'promax_atmosphere.dart';
import 'promax_glass.dart';

@immutable
class ProMaxThemePreset {
  const ProMaxThemePreset({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.accent,
    required this.amoled,
    required this.preview,
    this.blur = 1.0,
    this.refraction = 18,
    this.specular = 0.56,
    this.chroma = 0.12,
    this.rim = 2.4,
    this.tint = 1.0,
    this.atmosphere,
  });

  final String id;
  final String title;
  final String subtitle;
  final Color? accent;
  final bool amoled;
  final List<Color> preview;
  final double blur;
  final double refraction;
  final double specular;
  final double chroma;
  final double rim;
  final double tint;
  final AtmosphereEffect? atmosphere;
}

class ProMaxThemePresets {
  static const prefKey = 'promax_theme_preset';

  static const List<ProMaxThemePreset> all = [
    ProMaxThemePreset(
      id: 'graphite',
      title: 'Графит',
      subtitle: 'Фирменный монохром ProMax',
      accent: Color(0xFFE4E4EA),
      amoled: true,
      preview: [Color(0xFF2A2C33), Color(0xFF050506)],
      tint: 1.2,
      specular: 0.7,
    ),
    ProMaxThemePreset(
      id: 'aurora',
      title: 'Аврора',
      subtitle: 'Фиолетовый в бирюзу',
      accent: Color(0xFF7B5CFF),
      amoled: false,
      preview: [Color(0xFF7B5CFF), Color(0xFF22D3EE)],
      refraction: 24,
      chroma: 0.2,
    ),
    ProMaxThemePreset(
      id: 'sunset',
      title: 'Закат',
      subtitle: 'Тёплый оранжевый',
      accent: Color(0xFFFF6B4A),
      amoled: false,
      preview: [Color(0xFFFF7A45), Color(0xFFFF3D8B)],
      chroma: 0.16,
    ),
    ProMaxThemePreset(
      id: 'ocean',
      title: 'Океан',
      subtitle: 'Глубокий синий',
      accent: Color(0xFF1FA2FF),
      amoled: false,
      preview: [Color(0xFF1FA2FF), Color(0xFF12D8FA)],
      refraction: 22,
    ),
    ProMaxThemePreset(
      id: 'forest',
      title: 'Лес',
      subtitle: 'Спокойный зелёный',
      accent: Color(0xFF2E9E6B),
      amoled: false,
      preview: [Color(0xFF2E9E6B), Color(0xFF0B3D2E)],
    ),
    ProMaxThemePreset(
      id: 'neon',
      title: 'Неон',
      subtitle: 'Яркое стекло на чёрном',
      accent: Color(0xFF00E5FF),
      amoled: true,
      preview: [Color(0xFF00E5FF), Color(0xFFFF00C8)],
      specular: 0.85,
      chroma: 0.3,
      rim: 3.2,
    ),
    ProMaxThemePreset(
      id: 'sakura',
      title: 'Сакура',
      subtitle: 'Розовые лепестки',
      accent: Color(0xFFFF8FB8),
      amoled: false,
      preview: [Color(0xFFFF8FB8), Color(0xFFC2185B)],
      atmosphere: AtmosphereEffect.sakura,
    ),
    ProMaxThemePreset(
      id: 'winter',
      title: 'Зима',
      subtitle: 'Лёд и снег',
      accent: Color(0xFF8EC5FF),
      amoled: false,
      preview: [Color(0xFF8EC5FF), Color(0xFF2F5FB8)],
      blur: 1.4,
      atmosphere: AtmosphereEffect.snow,
    ),
    ProMaxThemePreset(
      id: 'night',
      title: 'Звёздная ночь',
      subtitle: 'Чёрный и мерцание',
      accent: Color(0xFF5B6CFF),
      amoled: true,
      preview: [Color(0xFF1B1F4B), Color(0xFF000000)],
      atmosphere: AtmosphereEffect.stars,
    ),
    ProMaxThemePreset(
      id: 'system',
      title: 'Системная',
      subtitle: 'Цвета обоев телефона',
      accent: null,
      amoled: false,
      preview: [Color(0xFF8C9EFF), Color(0xFF4DB6AC)],
    ),
  ];

  static final ValueNotifier<String?> selected = ValueNotifier(null);

  static Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    selected.value = prefs.getString(prefKey);
  }

  static Future<void> ensureDefault() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.containsKey(prefKey) || prefs.containsKey(AppAccent.prefKey)) {
      return;
    }
    final preset = all.first;
    await AppAccent.save(preset.accent);
    await AppAmoled.save(preset.amoled);
    await applyLook(preset);
  }

  static ProMaxThemePreset? byId(String? id) =>
      all.where((preset) => preset.id == id).firstOrNull;

  static Future<void> remember(String? id) async {
    selected.value = id;
    final prefs = await SharedPreferences.getInstance();
    if (id == null) {
      await prefs.remove(prefKey);
    } else {
      await prefs.setString(prefKey, id);
    }
  }

  static Future<void> applyLook(ProMaxThemePreset preset) async {
    await ProMaxGlass.apply(
      blur: preset.blur,
      refraction: preset.refraction,
      specular: preset.specular,
      chroma: preset.chroma,
      rim: preset.rim,
      tint: preset.tint,
    );
    final atmosphere = preset.atmosphere;
    if (atmosphere != null) await ProMaxAtmosphere.setEffect(atmosphere);
    await remember(preset.id);
  }
}
