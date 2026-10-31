import 'package:flutter/foundation.dart';

import '../../frontend/widgets/liquid_glass.dart';
import 'app_native_glass.dart';
import 'app_visual_style.dart';

abstract final class ChromeGlass {
  static bool resolve({
    required VisualStyle style,
    required bool nativeActive,
    required bool shaderSupported,
  }) {
    if (style == VisualStyle.materialYou) return false;
    if (nativeActive) return true;
    return style == VisualStyle.liquidGlass && shaderSupported;
  }

  static bool get isLiquid => resolve(
    style: AppVisualStyle.current.value,
    nativeActive: NativeGlass.active,
    shaderSupported: LiquidGlass.isSupported,
  );

  static final Listenable listenable = Listenable.merge([
    AppVisualStyle.current,
    NativeGlass.enabled,
  ]);
}
