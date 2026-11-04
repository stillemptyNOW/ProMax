import 'package:flutter_test/flutter_test.dart';
import 'package:promax/core/config/frame_health.dart';

void main() {
  test('one isolated stall does not reduce effects', () {
    final health = FrameHealth();
    final decisions = [
      for (var i = 0; i < 120; i++)
        health.add(buildUs: i == 0 ? 50000 : 1000, rasterUs: 2000, hz: 120),
    ];
    expect(decisions, everyElement(false));
    expect(health.summary['slow'], 1);
    expect(health.summary['max_build_us'], 50000);
  });

  test(
    'sustained raster delays at 120 Hz reduce effects after a full window',
    () {
      final health = FrameHealth();
      for (var i = 0; i < 119; i++) {
        expect(health.add(buildUs: 1000, rasterUs: 13000, hz: 120), false);
      }
      expect(health.add(buildUs: 1000, rasterUs: 13000, hz: 120), true);
      expect(health.summary['frames'], 120);
      expect(health.summary['slow'], 120);
    },
  );

  test('the same frame fits a 60 Hz display without an effect reduction', () {
    final health = FrameHealth();
    for (var i = 0; i < 120; i++) {
      expect(health.add(buildUs: 1000, rasterUs: 13000, hz: 60), false);
    }
    expect(health.summary['slow'], 0);
  });

  test('foreground window reset keeps old stalls out of the next decision', () {
    final health = FrameHealth();
    for (var i = 0; i < 119; i++) {
      health.add(buildUs: 40000, rasterUs: 40000, hz: 120);
    }
    health.resetWindow();
    expect(health.add(buildUs: 1000, rasterUs: 1000, hz: 120), false);
    expect(health.summary['frames'], 120);
  });
}
