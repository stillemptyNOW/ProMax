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

class _RedesignWelcomeLayerState extends State<RedesignWelcomeLayer> {
  bool _visible = false;
  bool _preparing = false;
  bool _completed = false;
  Timer? _dismiss;

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
    AppLock.instance.locked.removeListener(_onLockChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_visible) return const IgnorePointer(child: SizedBox.shrink());
    return BlockSemantics(
      child: Material(
        color: Theme.of(context).colorScheme.surface,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Semantics(
              liveRegion: true,
              child: Text(
                AppLocalizations.of(context)!.appRedesignWelcome,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineMedium,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
