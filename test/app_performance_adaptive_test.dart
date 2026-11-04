import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:promax/core/config/app_performance.dart';
import 'package:promax/core/utils/app_foreground.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();

  void report(int count, {int durationUs = 50000}) {
    binding.platformDispatcher.onReportTimings!(
      List.generate(
        count,
        (_) => ui.FrameTiming(
          vsyncStart: 0,
          buildStart: 0,
          buildFinish: durationUs,
          rasterStart: durationUs,
          rasterFinish: durationUs * 2,
          rasterFinishWallTime: durationUs * 2,
        ),
      ),
    );
  }

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await AppPerformance.load();
    await Future<void>.delayed(const Duration(milliseconds: 3100));
  });

  setUp(() async {
    AppForeground.update(foreground: true);
    AppPerformance.debugOverride();
    await AppPerformance.save(PerformanceMode.auto);
  });

  tearDown(() {
    AppForeground.update(foreground: true);
    AppPerformance.debugOverride();
  });

  test(
    'reloading unchanged settings preserves the adaptive reduction',
    () async {
      report(120);
      expect(AppPerformance.current, EffectBudget.mid);
      await AppPerformance.load();
      expect(AppPerformance.current, EffectBudget.mid);
      expect(AppPerformance.tier.value, DeviceTier.high);
      expect(AppPerformance.effectiveTier, DeviceTier.mid);
    },
  );

  test('suspending without background frames discards the old window', () {
    report(119);
    AppForeground.update(foreground: false);
    AppForeground.update(foreground: true);
    report(1, durationUs: 1000);
    expect(AppPerformance.current, EffectBudget.high);
    report(119);
    expect(AppPerformance.current, EffectBudget.mid);
  });

  test(
    'manual selection restores the device tier and starts a new window',
    () async {
      report(120);
      expect(AppPerformance.current, EffectBudget.mid);
      report(119);
      await AppPerformance.save(PerformanceMode.auto);
      expect(AppPerformance.current, EffectBudget.high);
      report(1);
      expect(AppPerformance.current, EffectBudget.high);
      report(119);
      expect(AppPerformance.current, EffectBudget.mid);
    },
  );

  test('explicit modes ignore sustained slow frames', () async {
    await AppPerformance.save(PerformanceMode.beauty);
    report(240);
    expect(AppPerformance.current, EffectBudget.beauty);
    await AppPerformance.save(PerformanceMode.smooth);
    report(240);
    expect(AppPerformance.current, EffectBudget.smooth);
  });
}
