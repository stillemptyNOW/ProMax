import 'package:flutter/foundation.dart';

enum MotionBlurQuality {
  low(6),
  balanced(12),
  high(24);

  const MotionBlurQuality(this.taps);

  final int taps;
}

enum MotionBlurTarget { scrolling, transitions, pages, lens }

@immutable
class MotionBlurSettings {
  const MotionBlurSettings({
    this.enabled = false,
    this.strength = defaultStrength,
    this.sensitivity = defaultSensitivity,
    this.quality = MotionBlurQuality.balanced,
    this.targets = allTargets,
  });

  static const double minStrength = 4;
  static const double maxStrength = 40;
  static const double defaultStrength = 16;
  static const double minSensitivity = 0.25;
  static const double maxSensitivity = 3;
  static const double defaultSensitivity = 1;
  static const Set<MotionBlurTarget> allTargets = {
    MotionBlurTarget.scrolling,
    MotionBlurTarget.transitions,
    MotionBlurTarget.pages,
    MotionBlurTarget.lens,
  };

  final bool enabled;
  final double strength;
  final double sensitivity;
  final MotionBlurQuality quality;
  final Set<MotionBlurTarget> targets;

  bool allows(MotionBlurTarget target) => enabled && targets.contains(target);

  MotionBlurSettings copyWith({
    bool? enabled,
    double? strength,
    double? sensitivity,
    MotionBlurQuality? quality,
    Set<MotionBlurTarget>? targets,
  }) => MotionBlurSettings(
    enabled: enabled ?? this.enabled,
    strength: (strength ?? this.strength).clamp(minStrength, maxStrength),
    sensitivity: (sensitivity ?? this.sensitivity).clamp(
      minSensitivity,
      maxSensitivity,
    ),
    quality: quality ?? this.quality,
    targets: Set.unmodifiable(targets ?? this.targets),
  );

  MotionBlurSettings withTarget(MotionBlurTarget target, bool on) {
    final next = {...targets};
    on ? next.add(target) : next.remove(target);
    return copyWith(targets: next);
  }

  Map<String, Object> toJson() => {
    'enabled': enabled,
    'strength': strength,
    'sensitivity': sensitivity,
    'quality': quality.name,
    'targets': [
      for (final target in MotionBlurTarget.values)
        if (targets.contains(target)) target.name,
    ],
  };

  factory MotionBlurSettings.fromJson(Object? raw) {
    const fallback = MotionBlurSettings();
    if (raw is! Map) return fallback;
    double number(Object? value, double fallback) =>
        value is num && value.isFinite ? value.toDouble() : fallback;
    final rawTargets = raw['targets'];
    return fallback.copyWith(
      enabled: raw['enabled'] is bool ? raw['enabled'] as bool : null,
      strength: number(raw['strength'], defaultStrength),
      sensitivity: number(raw['sensitivity'], defaultSensitivity),
      quality: MotionBlurQuality.values
          .where((value) => value.name == raw['quality'])
          .firstOrNull,
      targets: rawTargets is List
          ? {
              for (final target in MotionBlurTarget.values)
                if (rawTargets.contains(target.name)) target,
            }
          : null,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is MotionBlurSettings &&
      other.enabled == enabled &&
      other.strength == strength &&
      other.sensitivity == sensitivity &&
      other.quality == quality &&
      setEquals(other.targets, targets);

  @override
  int get hashCode => Object.hash(
    enabled,
    strength,
    sensitivity,
    quality,
    Object.hashAllUnordered(targets),
  );
}
