import 'package:flutter/material.dart';
import 'package:promax/core/config/app_frost.dart';
import 'package:promax/frontend/widgets/liquid_glass.dart';

class FrostedPanel extends StatelessWidget {
  final Color tint;
  final Border? border;
  final double? sigma;
  final BackdropKey? backdropKey;
  final Widget child;

  const FrostedPanel({
    super.key,
    required this.tint,
    this.border,
    this.sigma,
    this.backdropKey,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.passthrough,
      clipBehavior: Clip.none,
      children: [
        Positioned.fill(
          child: GlassSurface(
            frostTint: tint,
            frostSigma: sigma ?? AppFrost.panelSigma,
            border: border,
            backdropKey: backdropKey,
            child: const SizedBox.expand(),
          ),
        ),
        child,
      ],
    );
  }
}
