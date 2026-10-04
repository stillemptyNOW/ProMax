import 'package:flutter/material.dart';

// #***! параметры жидкого стекла
class AppLiquidGlass {
  static const bool enabled = true;

  // #***! подобрано на глаз, крутится только тут
  static const double blurSigma = 1.2;
  static const double spread = 1.02;
  static const double refraction = 18;
  static const double chroma = 0.12;
  static const double specular = 0.56;
  static const double rimWidth = 2.4;
  static const Offset light = Offset(-0.4, -1);
  static const double tintFeather = 30;

  static Color navTint(ColorScheme cs) => cs.primary.withValues(alpha: 0.10);

  static Color panelTint(ColorScheme cs) => cs.surface.withValues(alpha: 0.16);
}
