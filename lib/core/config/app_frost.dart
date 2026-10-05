import 'package:flutter/material.dart';

import 'promax_glass.dart';

class AppFrost {
  static double get sigma => 34 * ProMaxGlass.blur.value;
  static double get panelSigma => 24 * ProMaxGlass.blur.value;
  static const double overlaySigma = 18;
  static const double mediaBackdropSigma = 30;
  static double get glassAlpha =>
      (0.28 * ProMaxGlass.tint.value).clamp(0.0, 1.0).toDouble();
  static double get blurPanelAlpha =>
      (0.55 * ProMaxGlass.tint.value).clamp(0.0, 1.0).toDouble();
  static const double scrimAlpha = 0.4;

  static Color glassTint(ColorScheme cs, [double? alpha]) =>
      cs.surfaceContainerHigh.withValues(alpha: alpha ?? glassAlpha);

  static Color blurPanelTint(ColorScheme cs) => glassTint(cs, blurPanelAlpha);

  static Color scrim([double alpha = scrimAlpha]) =>
      Colors.black.withValues(alpha: alpha);

  static BorderSide hairline(ColorScheme cs) =>
      BorderSide(color: cs.outlineVariant.withValues(alpha: 0.4), width: 0.5);
}
