import 'dart:io' show Platform;
import 'dart:ui' as ui;

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'persisted_setting.dart';

enum PerformanceMode { auto, smooth, beauty }

enum DeviceTier { low, mid, high }

enum GlassQuality { flat, frosted, refraction }

@immutable
class DeviceHints {
  const DeviceHints({
    required this.platform,
    this.web = false,
    this.ramMb = 0,
    this.sdkInt = 0,
    this.lowRamDevice = false,
    this.cpuCores = 0,
    this.vulkan = true,
    this.supports64Bit = true,
  });

  final TargetPlatform platform;
  final bool web;
  final int ramMb;
  final int sdkInt;
  final bool lowRamDevice;
  final int cpuCores;
  final bool vulkan;
  final bool supports64Bit;
}

abstract final class DeviceTierDetector {
  static const int lowRamMb = 3500;
  static const int midRamMb = 5000;
  static const int vulkanBaselineSdk = 29;
  static const int legacySdk = 26;
  static const int fewCores = 6;
  static const String vulkanFeature = 'android.hardware.vulkan.version';

  static DeviceTier classify(DeviceHints hints) {
    if (hints.web || hints.platform != TargetPlatform.android) {
      return DeviceTier.high;
    }
    final knownRam = hints.ramMb > 0;
    if (hints.lowRamDevice ||
        (knownRam && hints.ramMb < lowRamMb) ||
        (hints.sdkInt > 0 && hints.sdkInt < legacySdk) ||
        !hints.supports64Bit ||
        (hints.cpuCores > 0 && hints.cpuCores < fewCores)) {
      return DeviceTier.low;
    }
    final gles =
        !hints.vulkan || (hints.sdkInt > 0 && hints.sdkInt < vulkanBaselineSdk);
    final modestRam = knownRam && hints.ramMb < midRamMb;
    if (gles && modestRam) return DeviceTier.low;
    if (gles || modestRam) return DeviceTier.mid;
    return DeviceTier.high;
  }

  static Future<DeviceHints> collect() async {
    if (kIsWeb) {
      return DeviceHints(platform: defaultTargetPlatform, web: true);
    }
    if (defaultTargetPlatform != TargetPlatform.android) {
      return DeviceHints(platform: defaultTargetPlatform);
    }
    final android = await DeviceInfoPlugin().androidInfo;
    return DeviceHints(
      platform: TargetPlatform.android,
      ramMb: android.physicalRamSize,
      sdkInt: android.version.sdkInt,
      lowRamDevice: android.isLowRamDevice,
      cpuCores: Platform.numberOfProcessors,
      vulkan: android.systemFeatures.contains(vulkanFeature),
      supports64Bit: android.supported64BitAbis.isNotEmpty,
    );
  }

  static Future<DeviceTier> detect() async {
    try {
      return classify(await collect());
    } catch (_) {
      return DeviceTier.high;
    }
  }
}

@immutable
class EffectBudget {
  const EffectBudget({
    required this.glass,
    required this.ambientFrameRate,
    required this.atmosphereFrameRate,
    required this.particleScale,
    required this.maxParticles,
    required this.animatedBackgrounds,
    required this.wallpaperMotion,
    required this.maxRefreshRate,
  });

  static const double uncapped = 0;

  static const EffectBudget beauty = EffectBudget(
    glass: GlassQuality.refraction,
    ambientFrameRate: uncapped,
    atmosphereFrameRate: uncapped,
    particleScale: 1,
    maxParticles: 320,
    animatedBackgrounds: true,
    wallpaperMotion: true,
    maxRefreshRate: uncapped,
  );

  static const EffectBudget high = EffectBudget(
    glass: GlassQuality.refraction,
    ambientFrameRate: 60,
    atmosphereFrameRate: 60,
    particleScale: 1,
    maxParticles: 320,
    animatedBackgrounds: true,
    wallpaperMotion: true,
    maxRefreshRate: uncapped,
  );

  static const EffectBudget mid = EffectBudget(
    glass: GlassQuality.frosted,
    ambientFrameRate: 30,
    atmosphereFrameRate: 30,
    particleScale: 0.7,
    maxParticles: 140,
    animatedBackgrounds: true,
    wallpaperMotion: true,
    maxRefreshRate: uncapped,
  );

  static const EffectBudget low = EffectBudget(
    glass: GlassQuality.flat,
    ambientFrameRate: 24,
    atmosphereFrameRate: 30,
    particleScale: 0.45,
    maxParticles: 80,
    animatedBackgrounds: false,
    wallpaperMotion: false,
    maxRefreshRate: 60,
  );

  static const EffectBudget smooth = EffectBudget(
    glass: GlassQuality.flat,
    ambientFrameRate: 24,
    atmosphereFrameRate: 30,
    particleScale: 0.45,
    maxParticles: 80,
    animatedBackgrounds: false,
    wallpaperMotion: false,
    maxRefreshRate: uncapped,
  );

  final GlassQuality glass;
  final double ambientFrameRate;
  final double atmosphereFrameRate;
  final double particleScale;
  final int maxParticles;
  final bool animatedBackgrounds;
  final bool wallpaperMotion;
  final double maxRefreshRate;

  static EffectBudget resolve(PerformanceMode mode, DeviceTier tier) =>
      switch (mode) {
        PerformanceMode.beauty => beauty,
        PerformanceMode.smooth => smooth,
        PerformanceMode.auto => switch (tier) {
          DeviceTier.high => high,
          DeviceTier.mid => mid,
          DeviceTier.low => low,
        },
      };

  int particleCount(int base, double density) {
    final wanted = (base * density * particleScale).round();
    return wanted.clamp(0, maxParticles);
  }
}

class AppPerformance {
  static const prefKey = 'app_performance_mode';
  static const MethodChannel _screen = MethodChannel(
    'io.github.stillemptynow.promax/screen',
  );

  static final _mode = PersistedEnum<PerformanceMode>(
    prefKey: prefKey,
    defaultValue: PerformanceMode.auto,
    encode: (value) => value.name,
    decode: (raw) =>
        enumFromName(PerformanceMode.values, raw, PerformanceMode.auto),
  );

  static final ValueNotifier<DeviceTier> tier = ValueNotifier(DeviceTier.high);
  static final ValueNotifier<EffectBudget> budget = ValueNotifier(
    EffectBudget.high,
  );
  static double? _appliedRefreshCap;

  static ValueNotifier<PerformanceMode> get mode => _mode.current;

  static EffectBudget get current => budget.value;

  static Future<void> load() async {
    await _mode.load();
    tier.value = await DeviceTierDetector.detect();
    _refresh();
  }

  static Future<void> save(PerformanceMode value) async {
    await _mode.save(value);
    _refresh();
  }

  @visibleForTesting
  static void debugOverride({
    PerformanceMode mode = PerformanceMode.auto,
    DeviceTier tier = DeviceTier.high,
  }) {
    _mode.current.value = mode;
    AppPerformance.tier.value = tier;
    budget.value = EffectBudget.resolve(mode, tier);
  }

  static void _refresh() {
    budget.value = EffectBudget.resolve(mode.value, tier.value);
    _applyRefreshCap(budget.value.maxRefreshRate);
  }

  static void _applyRefreshCap(double hz) {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    if (_appliedRefreshCap == hz) return;
    _appliedRefreshCap = hz;
    _screen
        .invokeMethod<void>('setMaxRefreshRate', {'hz': hz})
        .catchError((_) {});
  }

  static double displayRefreshRate() {
    final displays = ui.PlatformDispatcher.instance.displays;
    final hz = displays.isEmpty ? 60.0 : displays.first.refreshRate;
    return hz.isFinite && hz >= 30 ? hz : 60;
  }
}
