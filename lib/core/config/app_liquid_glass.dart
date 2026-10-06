import 'package:flutter/material.dart';

import 'promax_glass.dart';

class AppLiquidGlass {
  static const bool enabled = true;

  static double get blurSigma => 3.2 * ProMaxGlass.blur.value;
  static const double spread = 0.46;
  static double get refraction => ProMaxGlass.refraction.value;
  static double get chroma => ProMaxGlass.chroma.value;
  static double get specular => ProMaxGlass.specular.value;
  static double get rimWidth => ProMaxGlass.rim.value;
  static const Offset light = Offset(-0.4, -1);
  static const double tintFeather = 22;

  static double _alpha(double base) =>
      (base * ProMaxGlass.tint.value).clamp(0.0, 1.0).toDouble();

  static double _veil(ColorScheme cs) =>
      cs.brightness == Brightness.dark ? 0.26 : 0.38;

  static Color navTint(ColorScheme cs) => Color.alphaBlend(
    cs.primary.withValues(alpha: 0.06),
    cs.surface,
  ).withValues(alpha: _alpha(_veil(cs)));

  static Color panelTint(ColorScheme cs) =>
      cs.surface.withValues(alpha: _alpha(_veil(cs)));
}
