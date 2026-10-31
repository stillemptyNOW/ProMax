import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../core/config/app_chrome_glass.dart';
import '../../core/config/app_liquid_glass.dart';
import 'glossy_pill.dart';
import 'liquid_glass.dart';

class ChromeGlassBuilder extends StatelessWidget {
  const ChromeGlassBuilder({super.key, required this.builder});

  final Widget Function(BuildContext context, bool liquid) builder;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: ChromeGlass.listenable,
    builder: (context, _) => builder(context, ChromeGlass.isLiquid),
  );
}

class ChromeGlassPanel extends StatelessWidget {
  const ChromeGlassPanel({
    super.key,
    required this.borderRadius,
    this.role = GlassRole.panel,
    this.tint,
    this.shadow = true,
    this.clipContent = true,
    required this.child,
  });

  final BorderRadius borderRadius;
  final GlassRole role;
  final Color? tint;
  final bool shadow;
  final bool clipContent;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final content = Material(type: MaterialType.transparency, child: child);
    return LiquidGlassSurface(
      borderRadius: borderRadius,
      role: role,
      tint: tint,
      shadow: shadow,
      child: clipContent
          ? ClipRRect(borderRadius: borderRadius, child: content)
          : content,
    );
  }
}

class ChromeGlassCircleButton extends StatelessWidget {
  const ChromeGlassCircleButton({
    super.key,
    required this.icon,
    required this.onPressed,
    this.size = 44,
    this.iconSize = 24,
    this.color,
    this.tooltip,
    this.native = true,
  });

  final Widget icon;
  final VoidCallback? onPressed;
  final double size;
  final double iconSize;
  final Color? color;
  final String? tooltip;
  final bool native;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final button = SizedBox.square(
      dimension: size,
      child: GlossyPill(
        liquid: true,
        nativeGlass: native,
        onTap: onPressed,
        child: Center(
          child: IconTheme.merge(
            data: IconThemeData(
              color: color ?? cs.onSurface,
              size: iconSize,
              weight: 500,
            ),
            child: icon,
          ),
        ),
      ),
    );
    final label = tooltip;
    if (label == null) return button;
    return Semantics(button: true, label: label, child: button);
  }
}

class ChromeBackButton extends StatelessWidget {
  const ChromeBackButton({super.key, this.onPressed, this.close = false});

  final VoidCallback? onPressed;
  final bool close;

  @override
  Widget build(BuildContext context) {
    return ChromeGlassCircleButton(
      icon: Icon(close ? Symbols.close : Symbols.arrow_back),
      tooltip: close
          ? MaterialLocalizations.of(context).closeButtonTooltip
          : MaterialLocalizations.of(context).backButtonTooltip,
      onPressed: onPressed ?? () => Navigator.maybePop(context),
    );
  }

  static Widget? leadingFor(BuildContext context, {required bool liquid}) {
    if (!liquid) return null;
    final route = ModalRoute.of(context);
    if (!(Navigator.maybeOf(context)?.canPop() ?? false)) return null;
    final close = route is PageRoute && route.fullscreenDialog;
    return ChromeBackButton(close: close);
  }
}

class ChromeGlassToolbar extends StatelessWidget {
  const ChromeGlassToolbar({
    super.key,
    required this.children,
    this.height = 44,
    this.native = true,
  });

  final List<Widget> children;
  final double height;
  final bool native;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SizedBox(
      height: height,
      child: LiquidGlassSurface(
        borderRadius: BorderRadius.circular(height / 2),
        native: native,
        child: Material(
          type: MaterialType.transparency,
          child: IconTheme.merge(
            data: IconThemeData(color: cs.onSurface, weight: 500),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Row(mainAxisSize: MainAxisSize.min, children: children),
            ),
          ),
        ),
      ),
    );
  }
}

class ChromeMenuSurface extends StatelessWidget {
  const ChromeMenuSurface({
    super.key,
    required this.borderRadius,
    required this.child,
    this.animation,
    this.elevation = 12,
    this.shadowOpacity = 0.45,
  });

  final BorderRadius borderRadius;
  final Animation<double>? animation;
  final double elevation;
  final double shadowOpacity;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ChromeGlassBuilder(
      builder: (context, liquid) {
        if (!liquid) {
          return Material(
            color: Theme.of(context).colorScheme.surfaceContainerHigh,
            borderRadius: borderRadius,
            clipBehavior: Clip.antiAlias,
            elevation: elevation,
            shadowColor: Colors.black.withValues(alpha: shadowOpacity),
            child: child,
          );
        }
        final glass = ChromeGlassPanel(
          borderRadius: borderRadius,
          child: child,
        );
        final hold = animation;
        if (hold == null) return glass;
        return NativeGlassAnimationHold(animation: hold, child: glass);
      },
    );
  }
}

class ChromeLeadingButton extends StatelessWidget {
  const ChromeLeadingButton({
    super.key,
    required this.icon,
    required this.onPressed,
    this.native = true,
  });

  final Widget icon;
  final VoidCallback? onPressed;
  final bool native;

  @override
  Widget build(BuildContext context) {
    return ChromeGlassBuilder(
      builder: (context, liquid) => liquid
          ? Center(
              child: ChromeGlassCircleButton(
                icon: icon,
                onPressed: onPressed,
                native: native,
              ),
            )
          : IconButton(icon: icon, onPressed: onPressed),
    );
  }
}

class ChromeImpliedLeading extends StatelessWidget {
  const ChromeImpliedLeading({super.key});

  @override
  Widget build(BuildContext context) {
    final route = ModalRoute.of(context);
    if (!(route?.impliesAppBarDismissal ?? false)) {
      return const SizedBox.shrink();
    }
    final close = route is PageRoute && route.fullscreenDialog;
    return ChromeGlassBuilder(
      builder: (context, liquid) {
        if (liquid) return Center(child: ChromeBackButton(close: close));
        return close ? const CloseButton() : const BackButton();
      },
    );
  }
}
