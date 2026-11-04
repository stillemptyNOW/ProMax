import 'dart:async';

import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/config/app_design.dart';
import '../../core/security/app_lock.dart';
import '../../l10n/app_localizations.dart';

class RedesignWelcomeLayer extends StatefulWidget {
  const RedesignWelcomeLayer({super.key});

  static const triggerBuild = int.fromEnvironment(
    'PROMAX_REDESIGN_WELCOME_BUILD',
    defaultValue: 121,
  );
  static const preferenceKey = 'promax_redesign_welcome_build';
  static const duration = Duration(seconds: 15);

  @override
  State<RedesignWelcomeLayer> createState() => _RedesignWelcomeLayerState();
}

class _RedesignWelcomeLayerState extends State<RedesignWelcomeLayer>
    with SingleTickerProviderStateMixin {
  bool _visible = false;
  bool _preparing = false;
  bool _completed = false;
  Timer? _dismiss;
  AnimationController? _animation;

  @override
  void initState() {
    super.initState();
    AppLock.instance.locked.addListener(_onLockChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_prepare()));
  }

  Future<void> _prepare() async {
    if (_preparing || _completed || AppLock.instance.locked.value) return;
    _preparing = true;
    try {
      final info = await PackageInfo.fromPlatform();
      final currentBuild = int.tryParse(info.buildNumber) ?? 0;
      final prefs = await SharedPreferences.getInstance();
      if (!mounted ||
          AppLock.instance.locked.value ||
          AppDesign.classic.value ||
          currentBuild < RedesignWelcomeLayer.triggerBuild ||
          (prefs.getInt(RedesignWelcomeLayer.preferenceKey) ?? 0) >=
              RedesignWelcomeLayer.triggerBuild) {
        return;
      }
      await prefs.setInt(
        RedesignWelcomeLayer.preferenceKey,
        RedesignWelcomeLayer.triggerBuild,
      );
      if (!mounted) return;
      _completed = true;
      if (!MediaQuery.disableAnimationsOf(context)) {
        _animation = AnimationController(
          vsync: this,
          duration: RedesignWelcomeLayer.duration,
        )..forward();
      }
      setState(() => _visible = true);
      _dismiss = Timer(RedesignWelcomeLayer.duration, () {
        if (mounted) setState(() => _visible = false);
      });
    } catch (_) {
    } finally {
      _preparing = false;
    }
  }

  void _onLockChanged() {
    if (!AppLock.instance.locked.value) unawaited(_prepare());
  }

  @override
  void dispose() {
    _dismiss?.cancel();
    _animation?.dispose();
    AppLock.instance.locked.removeListener(_onLockChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_visible) return const IgnorePointer(child: SizedBox.shrink());
    final text = Padding(
      padding: const EdgeInsets.all(32),
      child: Semantics(
        liveRegion: true,
        child: Text(
          AppLocalizations.of(context)!.appRedesignWelcome,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.headlineMedium,
        ),
      ),
    );
    final animation = _animation;
    final opacity = animation == null
        ? null
        : TweenSequence<double>([
            TweenSequenceItem(tween: Tween(begin: 0, end: 1), weight: 12),
            TweenSequenceItem(tween: ConstantTween(1), weight: 70),
            TweenSequenceItem(tween: Tween(begin: 1, end: 0), weight: 18),
          ]).animate(animation);
    return BlockSemantics(
      child: Material(
        color: Theme.of(context).colorScheme.surface,
        child: Center(
          child: opacity == null
              ? text
              : FadeTransition(opacity: opacity, child: text),
        ),
      ),
    );
  }
}
