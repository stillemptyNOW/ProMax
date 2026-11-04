import 'dart:ui' show lerpDouble;
import 'dart:math' as math;

import 'package:flutter/material.dart';

class PersonProfileScrollView extends StatelessWidget {
  const PersonProfileScrollView({
    super.key,
    required this.name,
    required this.subtitle,
    required this.avatarBuilder,
    required this.body,
    this.controller,
    this.trailing,
  });

  final String name;
  final String subtitle;
  final Widget Function(double size) avatarBuilder;
  final Widget body;
  final ScrollController? controller;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final top = MediaQuery.paddingOf(context).top;
    final scaler = MediaQuery.textScalerOf(context);
    final statusTop = math.max(270.0, 238 + scaler.scale(26) * 1.25);
    final expandedHeight = math.max(
      312.0,
      statusTop + scaler.scale(14) * 1.3 + 20,
    );
    return CustomScrollView(
      controller: controller,
      physics: const BouncingScrollPhysics(),
      slivers: [
        SliverAppBar(
          pinned: true,
          expandedHeight: expandedHeight,
          elevation: 0,
          scrolledUnderElevation: 0,
          backgroundColor: cs.surface,
          leading: const BackButton(),
          actions: [?trailing],
          flexibleSpace: LayoutBuilder(
            builder: (context, constraints) {
              final expanded =
                  ((constraints.maxHeight - top - kToolbarHeight) /
                          (expandedHeight - kToolbarHeight))
                      .clamp(0.0, 1.0);
              final size = lerpDouble(34, 156, expanded)!;
              return ColoredBox(
                color: Color.lerp(
                  cs.surface,
                  cs.surfaceContainerLow,
                  expanded,
                )!,
                child: Stack(
                  children: [
                    Positioned(
                      top: top + lerpDouble(11, 58, expanded)!,
                      left: lerpDouble(
                        56,
                        (constraints.maxWidth - size) / 2,
                        expanded,
                      )!,
                      width: size,
                      height: size,
                      child: avatarBuilder(size),
                    ),
                    Positioned(
                      top: top + lerpDouble(15, 230, expanded)!,
                      left: lerpDouble(102, 20, expanded)!,
                      right: lerpDouble(56, 20, expanded)!,
                      child: Align(
                        alignment: Alignment.lerp(
                          Alignment.centerLeft,
                          Alignment.center,
                          expanded,
                        )!,
                        child: Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(
                                fontSize: lerpDouble(17, 26, expanded),
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                      ),
                    ),
                    if (subtitle.isNotEmpty)
                      Positioned(
                        top: top + statusTop,
                        left: 24,
                        right: 24,
                        child: Opacity(
                          opacity: expanded,
                          child: Text(
                            subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                            style: TextStyle(color: cs.onSurfaceVariant),
                          ),
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
        ),
        SliverToBoxAdapter(child: body),
      ],
    );
  }
}
