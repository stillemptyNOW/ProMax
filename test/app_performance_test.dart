import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promax/backend/api.dart';
import 'package:promax/core/config/app_performance.dart';
import 'package:promax/core/config/promax_atmosphere.dart';
import 'package:promax/frontend/widgets/ambient_clock.dart';
import 'package:promax/frontend/widgets/atmosphere_overlay.dart';
import 'package:promax/frontend/widgets/glossy_pill.dart';
import 'package:promax/frontend/widgets/liquid_glass.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _android = TargetPlatform.android;

DeviceHints _phone({
  int ramMb = 8000,
  int sdkInt = 34,
  bool lowRam = false,
  int cores = 8,
  bool vulkan = true,
  bool arm64 = true,
}) => DeviceHints(
  platform: _android,
  ramMb: ramMb,
  sdkInt: sdkInt,
  lowRamDevice: lowRam,
  cpuCores: cores,
  vulkan: vulkan,
  supports64Bit: arm64,
);

Widget _host(GlassQuality quality, Widget child) => MaterialApp(
  home: GlassQualityScope(
    quality: quality,
    child: Scaffold(
      body: Center(child: SizedBox(width: 240, height: 56, child: child)),
    ),
  ),
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  tearDown(() => AppPerformance.debugOverride());

  group('device tier', () {
    test('a modern flagship is high', () {
      expect(DeviceTierDetector.classify(_phone()), DeviceTier.high);
    });

    test('low RAM, Android Go, old Android, 32-bit or few cores are low', () {
      expect(DeviceTierDetector.classify(_phone(ramMb: 2800)), DeviceTier.low);
      expect(DeviceTierDetector.classify(_phone(lowRam: true)), DeviceTier.low);
      expect(DeviceTierDetector.classify(_phone(sdkInt: 24)), DeviceTier.low);
      expect(DeviceTierDetector.classify(_phone(arm64: false)), DeviceTier.low);
      expect(DeviceTierDetector.classify(_phone(cores: 4)), DeviceTier.low);
    });

    test('4 GB or a GLES-only GPU is mid, both together are low', () {
      expect(DeviceTierDetector.classify(_phone(ramMb: 3700)), DeviceTier.mid);
      expect(
        DeviceTierDetector.classify(_phone(vulkan: false)),
        DeviceTier.mid,
      );
      expect(DeviceTierDetector.classify(_phone(sdkInt: 28)), DeviceTier.mid);
      expect(
        DeviceTierDetector.classify(_phone(ramMb: 3700, vulkan: false)),
        DeviceTier.low,
      );
    });

    test('unknown RAM does not demote a device', () {
      expect(DeviceTierDetector.classify(_phone(ramMb: 0)), DeviceTier.high);
    });

    test('iOS, desktop and web keep the full look', () {
      for (final platform in [
        TargetPlatform.iOS,
        TargetPlatform.macOS,
        TargetPlatform.windows,
        TargetPlatform.linux,
      ]) {
        expect(
          DeviceTierDetector.classify(DeviceHints(platform: platform)),
          DeviceTier.high,
        );
      }
      expect(
        DeviceTierDetector.classify(
          const DeviceHints(platform: _android, web: true, ramMb: 1000),
        ),
        DeviceTier.high,
      );
    });
  });

  group('effect budget', () {
    test('auto follows the tier, the explicit modes ignore it', () {
      for (final tier in DeviceTier.values) {
        expect(
          EffectBudget.resolve(PerformanceMode.beauty, tier),
          EffectBudget.beauty,
        );
        expect(
          EffectBudget.resolve(PerformanceMode.smooth, tier),
          EffectBudget.smooth,
        );
      }
      expect(
        EffectBudget.resolve(PerformanceMode.auto, DeviceTier.high).glass,
        GlassQuality.refraction,
      );
      expect(
        EffectBudget.resolve(PerformanceMode.auto, DeviceTier.mid).glass,
        GlassQuality.frosted,
      );
      final low = EffectBudget.resolve(PerformanceMode.auto, DeviceTier.low);
      expect(low.glass, GlassQuality.flat);
      expect(low.animatedBackgrounds, isFalse);
      expect(low.maxRefreshRate, 60);
    });

    test('cheaper budgets never allow more particles or frames', () {
      final ladder = [
        EffectBudget.beauty,
        EffectBudget.high,
        EffectBudget.mid,
        EffectBudget.low,
      ];
      for (var i = 1; i < ladder.length; i++) {
        expect(
          ladder[i].particleCount(90, 3),
          lessThanOrEqualTo(ladder[i - 1].particleCount(90, 3)),
        );
        expect(
          ladder[i].glass.index,
          lessThanOrEqualTo(ladder[i - 1].glass.index),
        );
      }
      expect(
        EffectBudget.low.particleCount(90, 3),
        EffectBudget.low.maxParticles,
      );
      expect(EffectBudget.beauty.particleCount(70, 1), 70);
    });

    test('the mode survives a reload', () async {
      await AppPerformance.save(PerformanceMode.smooth);
      AppPerformance.debugOverride();
      await AppPerformance.load();
      expect(AppPerformance.mode.value, PerformanceMode.smooth);
      expect(AppPerformance.current, EffectBudget.smooth);
    });
  });

  group('ambient clock', () {
    test('waits so frames land on the capped rate', () {
      expect(AmbientClock.pauseBetweenFrames(0, 120), Duration.zero);
      expect(AmbientClock.pauseBetweenFrames(120, 120), Duration.zero);
      final at60on120 = AmbientClock.pauseBetweenFrames(60, 120);
      expect(at60on120.inMicroseconds, inInclusiveRange(8400, 16600));
      final at30on60 = AmbientClock.pauseBetweenFrames(30, 60);
      expect(at30on60.inMicroseconds, inInclusiveRange(16700, 33300));
    });

    testWidgets('a capped atmosphere schedules fewer frames', (tester) async {
      Future<int> framesIn(double frameRate) async {
        AppPerformance.budget.value = EffectBudget(
          glass: GlassQuality.refraction,
          ambientFrameRate: frameRate,
          atmosphereFrameRate: frameRate,
          particleScale: 1,
          maxParticles: 320,
          animatedBackgrounds: true,
          wallpaperMotion: true,
          maxRefreshRate: 0,
        );
        await tester.pumpWidget(
          const MaterialApp(
            home: AtmosphereLayer(
              style: AtmosphereStyle(effect: AtmosphereEffect.snow),
            ),
          ),
        );
        var painted = 0;
        final painter =
            tester
                    .widget<CustomPaint>(
                      find.descendant(
                        of: find.byType(AtmosphereLayer),
                        matching: find.byType(CustomPaint),
                      ),
                    )
                    .painter!
                as AtmospherePainter;
        void count() => painted++;
        painter.seconds.addListener(count);
        for (var i = 0; i < 60; i++) {
          await tester.pump(const Duration(milliseconds: 1000 ~/ 60));
        }
        painter.seconds.removeListener(count);
        await tester.pumpWidget(const SizedBox.shrink());
        return painted;
      }

      final uncapped = await framesIn(EffectBudget.uncapped);
      final capped = await framesIn(20);
      expect(uncapped, greaterThanOrEqualTo(55));
      expect(capped, lessThanOrEqualTo(uncapped ~/ 2));
    });
  });

  group('atmosphere', () {
    testWidgets('reduce motion draws one still frame and never ticks', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MediaQuery(
          data: MediaQueryData(disableAnimations: true),
          child: AtmosphereLayer(
            style: AtmosphereStyle(effect: AtmosphereEffect.stars),
          ),
        ),
      );
      expect(tester.binding.hasScheduledFrame, isFalse);
      expect(tester.takeException(), isNull);
    });

    test('every effect batches its particles into one atlas draw', () {
      for (final effect in AtmosphereEffect.values) {
        if (effect == AtmosphereEffect.none) continue;
        final field = AtmosphereField();
        final painter = AtmospherePainter(
          style: AtmosphereStyle(effect: effect),
          seconds: ValueNotifier(1.3),
          field: field,
        );
        final recorder = ui.PictureRecorder();
        painter.paint(Canvas(recorder), const Size(400, 800));
        recorder.endRecording().dispose();
        expect(field.particleCount, AtmospherePainter.baseCount[effect]);
        expect(field.spriteCount, greaterThan(0), reason: effect.name);
        expect(field.spriteCount, lessThanOrEqualTo(field.capacity));
      }
    });

    test('the particle cap follows the budget', () {
      final field = AtmosphereField();
      AtmospherePainter(
        style: const AtmosphereStyle(effect: AtmosphereEffect.rain, density: 3),
        seconds: ValueNotifier(0),
        field: field,
        budget: EffectBudget.low,
      ).paint(Canvas(ui.PictureRecorder()), const Size(400, 800));
      expect(field.particleCount, EffectBudget.low.maxParticles);
    });

    testWidgets('a chat without any effect builds no layer', (tester) async {
      await ProMaxAtmosphere.load();
      await ProMaxAtmosphere.setEffect(AtmosphereEffect.none);
      await tester.pumpWidget(
        const MaterialApp(home: ChatAtmosphereLayer(chatId: 5)),
      );
      expect(find.byType(AtmosphereLayer), findsNothing);
      await ProMaxAtmosphere.setChatEffect(5, AtmosphereEffect.leaves);
      await tester.pump();
      expect(find.byType(AtmosphereLayer), findsOneWidget);
      await ProMaxAtmosphere.setChatEffect(5, null);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  });

  group('glass quality', () {
    testWidgets('flat glass draws no backdrop filter', (tester) async {
      await tester.pumpWidget(
        _host(
          GlassQuality.flat,
          const LiquidGlassSurface(
            borderRadius: BorderRadius.all(Radius.circular(28)),
            child: Text('Синтетика'),
          ),
        ),
      );
      expect(find.byType(BackdropFilter), findsNothing);
      expect(find.text('Синтетика'), findsOneWidget);
    });

    testWidgets('frosted glass keeps one blur per surface', (tester) async {
      await tester.pumpWidget(
        _host(
          GlassQuality.frosted,
          const LiquidGlassSurface(
            borderRadius: BorderRadius.all(Radius.circular(28)),
          ),
        ),
      );
      expect(find.byType(BackdropFilter), findsOneWidget);
    });

    testWidgets('frosted pills and panels skip the blur when flat', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          GlassQuality.flat,
          Column(
            children: [
              GlassSurface(
                frostTint: Colors.white.withValues(alpha: 0.3),
                child: const SizedBox(height: 20),
              ),
              GlossyPill(
                color: Colors.white.withValues(alpha: 0.4),
                blurSigma: 12,
                child: const SizedBox(height: 20),
              ),
            ],
          ),
        ),
      );
      expect(find.byType(BackdropFilter), findsNothing);
    });
  });

  test('the wire log is decoded only for a consumer', () {
    expect(
      Api.wireLogWanted(monitor: false, sessionLog: false, push: false),
      isFalse,
    );
    expect(
      Api.wireLogWanted(monitor: false, sessionLog: true, push: true),
      isFalse,
    );
    expect(
      Api.wireLogWanted(monitor: false, sessionLog: true, push: false),
      isTrue,
    );
    expect(
      Api.wireLogWanted(monitor: true, sessionLog: false, push: true),
      isTrue,
    );
  });
}
