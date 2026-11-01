import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../core/config/promax_settings.dart';

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
