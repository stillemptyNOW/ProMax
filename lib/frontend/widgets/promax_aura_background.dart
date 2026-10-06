import 'package:flutter/material.dart';

import '../../core/config/promax_aura.dart';

class ProMaxAuraBackground extends StatelessWidget {
  const ProMaxAuraBackground({super.key});

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<bool>(
    valueListenable: ProMaxAura.enabled,
    builder: (context, enabled, _) {
      if (!enabled) return const SizedBox.shrink();
      final cs = Theme.of(context).colorScheme;
      final dark = cs.brightness == Brightness.dark;
      return IgnorePointer(
        child: RepaintBoundary(
          child: Stack(
            fit: StackFit.expand,
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: const Alignment(0.9, -0.85),
                    radius: 1.1,
                    colors: [
                      cs.primary.withValues(alpha: dark ? 0.20 : 0.16),
                      cs.primary.withValues(alpha: 0),
                    ],
                  ),
                ),
              ),
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: const Alignment(-1.0, 0.75),
                    radius: 1.0,
                    colors: [
                      cs.tertiary.withValues(alpha: dark ? 0.14 : 0.12),
                      cs.tertiary.withValues(alpha: 0),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}
