import 'package:flutter/material.dart';

import 'persisted_setting.dart';

class GlassParameter {
  GlassParameter({
    required this.prefKey,
    required this.defaultValue,
    required this.min,
    required this.max,
  }) : _setting = PersistedSetting<double>(
         prefKey: prefKey,
         defaultValue: defaultValue,
         read: (prefs, key) => prefs.getDouble(key),
         write: (prefs, key, value) async => prefs.setDouble(key, value),
         sanitize: (value) => value.clamp(min, max).toDouble(),
       );

  final String prefKey;
  final double defaultValue;
  final double min;
  final double max;
  final PersistedSetting<double> _setting;

  ValueNotifier<double> get current => _setting.current;

  double get value => _setting.current.value;

  Future<double> load() => _setting.load();

  Future<void> save(double value) => _setting.save(value);

  Future<void> reset() => _setting.save(defaultValue);
}

class ProMaxGlass {
  static final blur = GlassParameter(
    prefKey: 'promax_glass_blur',
    defaultValue: 1.0,
    min: 0.0,
    max: 2.5,
  );
  static final refraction = GlassParameter(
    prefKey: 'promax_glass_refraction',
    defaultValue: 12,
    min: 0,
    max: 40,
  );
  static final specular = GlassParameter(
    prefKey: 'promax_glass_specular',
    defaultValue: 0.6,
    min: 0,
    max: 1,
  );
  static final chroma = GlassParameter(
    prefKey: 'promax_glass_chroma',
    defaultValue: 0.06,
    min: 0,
    max: 0.4,
  );
  static final rim = GlassParameter(
    prefKey: 'promax_glass_rim',
    defaultValue: 2.0,
    min: 0,
    max: 5,
  );
  static final tint = GlassParameter(
    prefKey: 'promax_glass_tint',
    defaultValue: 1.0,
    min: 0,
    max: 2.5,
  );

  static List<GlassParameter> get all => [
    blur,
    refraction,
    specular,
    chroma,
    rim,
    tint,
  ];

  static final Listenable listenable = Listenable.merge([
    for (final parameter in all) parameter.current,
  ]);

  static Future<void> load() =>
      Future.wait([for (final parameter in all) parameter.load()]);

  static Future<void> reset() =>
      Future.wait([for (final parameter in all) parameter.reset()]);

  static Future<void> apply({
    double? blur,
    double? refraction,
    double? specular,
    double? chroma,
    double? rim,
    double? tint,
  }) => Future.wait([
    ProMaxGlass.blur.save(blur ?? ProMaxGlass.blur.defaultValue),
    ProMaxGlass.refraction.save(
      refraction ?? ProMaxGlass.refraction.defaultValue,
    ),
    ProMaxGlass.specular.save(specular ?? ProMaxGlass.specular.defaultValue),
    ProMaxGlass.chroma.save(chroma ?? ProMaxGlass.chroma.defaultValue),
    ProMaxGlass.rim.save(rim ?? ProMaxGlass.rim.defaultValue),
    ProMaxGlass.tint.save(tint ?? ProMaxGlass.tint.defaultValue),
  ]);
}

@immutable
class ProMaxGlassTheme extends ThemeExtension<ProMaxGlassTheme> {
  const ProMaxGlassTheme({
    required this.blur,
    required this.refraction,
    required this.specular,
    required this.chroma,
    required this.rim,
    required this.tint,
  });

  factory ProMaxGlassTheme.current() => ProMaxGlassTheme(
    blur: ProMaxGlass.blur.value,
    refraction: ProMaxGlass.refraction.value,
    specular: ProMaxGlass.specular.value,
    chroma: ProMaxGlass.chroma.value,
    rim: ProMaxGlass.rim.value,
    tint: ProMaxGlass.tint.value,
  );

  final double blur;
  final double refraction;
  final double specular;
  final double chroma;
  final double rim;
  final double tint;

  @override
  ProMaxGlassTheme copyWith({
    double? blur,
    double? refraction,
    double? specular,
    double? chroma,
    double? rim,
    double? tint,
  }) => ProMaxGlassTheme(
    blur: blur ?? this.blur,
    refraction: refraction ?? this.refraction,
    specular: specular ?? this.specular,
    chroma: chroma ?? this.chroma,
    rim: rim ?? this.rim,
    tint: tint ?? this.tint,
  );

  @override
  ProMaxGlassTheme lerp(ProMaxGlassTheme? other, double t) {
    if (other == null) return this;
    double mix(double a, double b) => a + (b - a) * t;
    return ProMaxGlassTheme(
      blur: mix(blur, other.blur),
      refraction: mix(refraction, other.refraction),
      specular: mix(specular, other.specular),
      chroma: mix(chroma, other.chroma),
      rim: mix(rim, other.rim),
      tint: mix(tint, other.tint),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is ProMaxGlassTheme &&
      other.blur == blur &&
      other.refraction == refraction &&
      other.specular == specular &&
      other.chroma == chroma &&
      other.rim == rim &&
      other.tint == tint;

  @override
  int get hashCode =>
      Object.hash(blur, refraction, specular, chroma, rim, tint);
}
