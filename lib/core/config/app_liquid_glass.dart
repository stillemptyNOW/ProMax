import 'package:flutter/material.dart';

import 'promax_glass.dart';

enum GlassRole { bar, panel, overlay }

@immutable
class GlassRim {
  const GlassRim({
    required this.top,
    required this.bottom,
    required this.width,
  });

  final Color top;
  final Color bottom;
  final double width;

  bool get visible => width > 0 && (top.a > 0 || bottom.a > 0);

  @override
  bool operator ==(Object other) =>
      other is GlassRim &&
      other.top == top &&
      other.bottom == bottom &&
      other.width == width;

  @override
  int get hashCode => Object.hash(top, bottom, width);
}

@immutable
class GlassShadow {
  const GlassShadow({
    required this.contact,
    required this.contactBlur,
    required this.contactOffset,
    required this.ambient,
  });

  final Color contact;
  final double contactBlur;
  final double contactOffset;
  final bool ambient;

  bool get visible => contact.a > 0 || ambient;

  @override
  bool operator ==(Object other) =>
      other is GlassShadow &&
      other.contact == contact &&
      other.contactBlur == contactBlur &&
      other.contactOffset == contactOffset &&
      other.ambient == ambient;

  @override
  int get hashCode => Object.hash(contact, contactBlur, contactOffset, ambient);
}

@immutable
class GlassMaterial {
  const GlassMaterial({
    required this.fill,
    required this.rim,
    required this.shadow,
    required this.blurSigma,
    required this.thickness,
    required this.chroma,
  });

  final Color fill;
  final GlassRim rim;
  final GlassShadow shadow;
  final double blurSigma;
  final double thickness;
  final double chroma;

  @override
  bool operator ==(Object other) =>
      other is GlassMaterial &&
      other.fill == fill &&
      other.rim == rim &&
      other.shadow == shadow &&
      other.blurSigma == blurSigma &&
      other.thickness == thickness &&
      other.chroma == chroma;

  @override
  int get hashCode =>
      Object.hash(fill, rim, shadow, blurSigma, thickness, chroma);
}

class AppLiquidGlass {
  static const bool enabled = true;

  static const double fillAlpha = 0.85;
  static const double frostedFillAlpha = 0.76;
  static const double overlayFillAlpha = 0.25;
  static const double blurSigma = 3.6;
  static const double frostedBlurSigma = 22.6;
  static const double saturation = 3;
  static const double refractIndex = 1.5;
  static const double refractIntensity = 0.75;
  static const double thicknessShare = 0.2;

  static const double pressedSizeIncrease = 20;
  static const SpringDescription liftOn = SpringDescription(
    mass: 1.36,
    stiffness: 568,
    damping: 39.7,
  );
  static const SpringDescription liftOff = SpringDescription(
    mass: 2,
    stiffness: 460,
    damping: 21.8,
  );
  static const double highlightOpacity = 0.1;
  static const double highlightRadius = 150;
  static const double stretchOffset = 24;

  static Color lensColor(ColorScheme cs) => cs.brightness == Brightness.dark
      ? Colors.white.withValues(alpha: 0.1)
      : Colors.black.withValues(alpha: 0.075);

  static Color surfaceColor(ColorScheme cs) => cs.brightness == Brightness.dark
      ? cs.surfaceContainerHigh
      : cs.surfaceContainerLowest;

  static GlassMaterial material(
    ColorScheme cs,
    GlassRole role, {
    ProMaxGlassTheme? glass,
    Color? tint,
    bool frosted = false,
  }) {
    final tuning = glass ?? ProMaxGlassTheme.current();
    final dark = cs.brightness == Brightness.dark;
    final baseAlpha = switch (role) {
      GlassRole.overlay => overlayFillAlpha,
      _ => frosted ? frostedFillAlpha : fillAlpha,
    };
    final alpha = (baseAlpha * tuning.tint).clamp(0.0, 1.0).toDouble();
    final base = role == GlassRole.overlay ? Colors.black : surfaceColor(cs);
    var fill = base.withValues(alpha: alpha);
    if (tint != null && tint.a > 0) fill = Color.alphaBlend(tint, fill);
    return GlassMaterial(
      fill: fill,
      rim: _rim(role, dark, tuning),
      shadow: _shadow(role, dark),
      blurSigma: (frosted ? frostedBlurSigma : blurSigma) * tuning.blur,
      thickness: tuning.refraction,
      chroma: tuning.chroma,
    );
  }

  static GlassRim _rim(GlassRole role, bool dark, ProMaxGlassTheme tuning) {
    Color white(int alpha) =>
        Color.fromARGB(_scaled(alpha, tuning), 255, 255, 255);
    Color black(int alpha) => Color.fromARGB(_scaled(alpha, tuning), 0, 0, 0);
    final width = tuning.rim;
    return switch (role) {
      GlassRole.bar => GlassRim(
        top: dark ? white(0x06) : black(0x11),
        bottom: dark ? white(0x11) : black(0x20),
        width: width * 0.8,
      ),
      GlassRole.panel => GlassRim(
        top: dark ? white(0x28) : white(0xFF),
        bottom: dark ? white(0x14) : white(0xFF),
        width: width,
      ),
      GlassRole.overlay => GlassRim(
        top: white(0x28),
        bottom: white(0x14),
        width: width * 4 / 3,
      ),
    };
  }

  static int _scaled(int alpha, ProMaxGlassTheme tuning) =>
      (alpha * tuning.specular).round().clamp(0, 255);

  static GlassShadow _shadow(GlassRole role, bool dark) {
    if (dark || role == GlassRole.overlay) {
      return const GlassShadow(
        contact: Colors.transparent,
        contactBlur: 0,
        contactOffset: 0,
        ambient: true,
      );
    }
    return switch (role) {
      GlassRole.bar => const GlassShadow(
        contact: Color(0x20000000),
        contactBlur: 2.667,
        contactOffset: 0.85,
        ambient: true,
      ),
      _ => const GlassShadow(
        contact: Color(0x20000000),
        contactBlur: 1,
        contactOffset: 1 / 3,
        ambient: true,
      ),
    };
  }
}
