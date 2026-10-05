import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../core/config/promax_settings.dart';

class StreamerMask extends StatelessWidget {
  const StreamerMask({super.key, required this.child, this.sigma = 6});

  final Widget child;
  final double sigma;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<bool>(
    valueListenable: ProMaxSettings.streamerMode,
    child: child,
    builder: (context, hidden, child) {
      if (!hidden) return child!;
      return ExcludeSemantics(
        child: ImageFiltered(
          imageFilter: ui.ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
          child: child,
        ),
      );
    },
  );
}

class AppSwitcherCurtain extends StatefulWidget {
  const AppSwitcherCurtain({super.key});

  @override
  State<AppSwitcherCurtain> createState() => _AppSwitcherCurtainState();
}

class _AppSwitcherCurtainState extends State<AppSwitcherCurtain>
    with WidgetsBindingObserver {
  bool _covered = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final covered =
        ProMaxSettings.switcherBlur.value && state != AppLifecycleState.resumed;
    if (covered != _covered) setState(() => _covered = covered);
  }

  @override
  Widget build(BuildContext context) {
    if (!_covered) return const SizedBox.shrink();
    return BackdropFilter(
      filter: ui.ImageFilter.blur(sigmaX: 36, sigmaY: 36),
      child: ColoredBox(
        color: Colors.black.withValues(alpha: 0.55),
        child: Center(
          child: Image.asset(
            'assets/promax.png',
            width: 88,
            height: 88,
            color: Colors.white,
          ),
        ),
      ),
    );
  }
}
