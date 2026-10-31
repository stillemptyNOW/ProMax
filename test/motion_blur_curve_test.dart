import 'package:flutter_test/flutter_test.dart';
import 'package:promax/core/plugins/motion_blur/motion_blur_curve.dart';
import 'package:promax/core/plugins/motion_blur/motion_blur_settings.dart';

void main() {
  double length(double speed, {double strength = 16, double sensitivity = 1}) =>
      MotionBlurCurve.streakLength(
        speed,
        strength: strength,
        sensitivity: sensitivity,
      );

  group('streakLength', () {
    test('stays at zero below the dead zone', () {
      expect(length(0), 0);
      expect(length(MotionBlurCurve.deadZone), 0);
      expect(length(MotionBlurCurve.deadZone * 0.5), 0);
    });

    test('grows with speed and saturates at the strength', () {
      final samples = [400.0, 800.0, 1600.0, 3200.0, 6400.0, 50000.0];
      final lengths = samples.map(length).toList();
      for (var i = 1; i < lengths.length; i++) {
        expect(lengths[i], greaterThan(lengths[i - 1]));
      }
      expect(lengths.last, lessThanOrEqualTo(16));
      expect(lengths.last, closeTo(16, 0.01));
    });

    test('higher sensitivity starts earlier and grows faster', () {
      expect(length(200, sensitivity: 0.5), 0);
      expect(length(200, sensitivity: 2), greaterThan(0));
      expect(
        length(900, sensitivity: 2),
        greaterThan(length(900, sensitivity: 1)),
      );
    });

    test('ignores invalid input', () {
      expect(length(double.nan), 0);
      expect(length(double.infinity), 0);
      expect(length(3000, strength: 0), 0);
    });
  });

  group('streak', () {
    const settings = MotionBlurSettings(enabled: true);

    test('points along the velocity', () {
      final streak = MotionBlurCurve.streak(const Offset(0, -3000), settings);
      expect(streak.dx, 0);
      expect(streak.dy, lessThan(0));
      final diagonal = MotionBlurCurve.streak(
        const Offset(2000, 2000),
        settings,
      );
      expect(diagonal.dx, closeTo(diagonal.dy, 1e-9));
    });

    test('is zero at rest', () {
      expect(MotionBlurCurve.streak(Offset.zero, settings), Offset.zero);
    });

    test('low-end budget caps the length', () {
      final capped = MotionBlurCurve.streak(
        const Offset(0, 40000),
        settings.copyWith(strength: 40),
        budget: MotionBlurBudget.lowEnd,
      );
      expect(capped.distance, lessThanOrEqualTo(10));
    });
  });

  group('taps', () {
    test('scale with the streak and stop at the quality', () {
      expect(MotionBlurCurve.taps(1, MotionBlurQuality.high), 3);
      expect(MotionBlurCurve.taps(15, MotionBlurQuality.high), 10);
      expect(MotionBlurCurve.taps(500, MotionBlurQuality.high), 24);
      expect(MotionBlurCurve.taps(500, MotionBlurQuality.balanced), 12);
      expect(MotionBlurCurve.taps(500, MotionBlurQuality.low), 6);
    });

    test('low-end budget caps the taps', () {
      expect(
        MotionBlurCurve.taps(
          500,
          MotionBlurQuality.high,
          budget: MotionBlurBudget.lowEnd,
        ),
        6,
      );
    });
  });

  group('MotionBlurVelocity', () {
    const frame = 1 / 60;

    test('follows steady motion', () {
      final velocity = MotionBlurVelocity();
      for (var i = 0; i < 20; i++) {
        velocity.update(const Offset(0, 50), frame);
      }
      expect(velocity.value.dy, closeTo(3000, 1));
      expect(velocity.value.dx, 0);
    });

    test('fades out smoothly once motion stops', () {
      final velocity = MotionBlurVelocity();
      for (var i = 0; i < 20; i++) {
        velocity.update(const Offset(0, 50), frame);
      }
      final fading = <double>[];
      for (var i = 0; i < 12; i++) {
        fading.add(velocity.update(Offset.zero, frame).dy);
      }
      expect(fading.first, greaterThan(1000));
      for (var i = 1; i < fading.length; i++) {
        expect(fading[i], lessThan(fading[i - 1]));
      }
      expect(fading.last, lessThan(MotionBlurCurve.deadZone));
    });

    test('clamps the frame time after a pause', () {
      final velocity = MotionBlurVelocity();
      final value = velocity.update(const Offset(0, 50), 0);
      expect(value.dy.isFinite, isTrue);
      expect(
        value.dy,
        lessThanOrEqualTo(50 / MotionBlurVelocity.shortestFrame),
      );
    });
  });
}
