import 'dart:math' as math;
import 'dart:ui';

import 'motion_blur_settings.dart';

class MotionBlurBudget {
  const MotionBlurBudget({required this.maxStrength, required this.maxTaps});

  static const MotionBlurBudget full = MotionBlurBudget(
    maxStrength: MotionBlurSettings.maxStrength,
    maxTaps: 24,
  );
  static const MotionBlurBudget lowEnd = MotionBlurBudget(
    maxStrength: 10,
    maxTaps: 6,
  );

  final double maxStrength;
  final int maxTaps;
}

abstract final class MotionBlurCurve {
  static const double deadZone = 240;
  static const double exposure = 1 / 90;
  static const double minVisibleLength = 0.4;
  static const double physicalPixelsPerTap = 1.5;
  static const int minTaps = 3;

  static double streakLength(
    double speed, {
    required double strength,
    required double sensitivity,
  }) {
    if (!speed.isFinite || strength <= 0 || sensitivity <= 0) return 0;
    final excess = speed - deadZone / sensitivity;
    if (excess <= 0) return 0;
    final length = strength * _tanh(excess * exposure * sensitivity / strength);
    return length < minVisibleLength ? 0 : length;
  }

  static Offset streak(
    Offset velocity,
    MotionBlurSettings settings, {
    MotionBlurBudget budget = MotionBlurBudget.full,
  }) {
    final speed = velocity.distance;
    final length = streakLength(
      speed,
      strength: math.min(settings.strength, budget.maxStrength),
      sensitivity: settings.sensitivity,
    );
    if (length == 0) return Offset.zero;
    return velocity * (length / speed);
  }

  static int taps(
    double physicalLength,
    MotionBlurQuality quality, {
    MotionBlurBudget budget = MotionBlurBudget.full,
  }) {
    final ceiling = math.min(quality.taps, budget.maxTaps);
    final wanted = (physicalLength / physicalPixelsPerTap).ceil();
    return wanted.clamp(math.min(minTaps, ceiling), ceiling);
  }

  static double gaussianSigma(double length) => length * 0.29;

  static double _tanh(double x) {
    if (x > 9) return 1;
    final e = math.exp(2 * x);
    return (e - 1) / (e + 1);
  }
}

class MotionBlurVelocity {
  static const double riseTime = 0.024;
  static const double fallTime = 0.075;
  static const double shortestFrame = 1 / 240;
  static const double longestFrame = 1 / 20;

  Offset _value = Offset.zero;

  Offset get value => _value;

  Offset update(Offset displacement, double seconds) {
    final dt = seconds.clamp(shortestFrame, longestFrame);
    final target = displacement / dt;
    final rising = target.distanceSquared > _value.distanceSquared;
    final k = 1 - math.exp(-dt / (rising ? riseTime : fallTime));
    _value += (target - _value) * k;
    return _value;
  }

  void reset() => _value = Offset.zero;
}
