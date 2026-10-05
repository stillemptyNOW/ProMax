import 'package:flutter/material.dart';

import 'promax_glass.dart';

class AppLiquidGlass {
  static const bool enabled = true;

  static double get blurSigma => 1.2 * ProMaxGlass.blur.value;
  static const double spread = 1.02;
  static double get refraction => ProMaxGlass.refraction.value;
  static double get chroma => ProMaxGlass.chroma.value;
  static double get specular => ProMaxGlass.specular.value;
  static double get rimWidth => ProMaxGlass.rim.value;
  static const Offset light = Offset(-0.4, -1);
  static const double tintFeather = 30;

  static double _alpha(double base) =>
      (base * ProMaxGlass.tint.value).clamp(0.0, 1.0).toDouble();

  static Color navTint(ColorScheme cs) =>
      cs.primary.withValues(alpha: _alpha(0.10));

  static Color panelTint(ColorScheme cs) =>
      cs.surface.withValues(alpha: _alpha(0.16));
}
