import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../widgets/connection_status.dart';

import '../../../core/config/app_icon.dart';
import '../../../core/utils/haptics.dart';
import '../../../l10n/app_localizations.dart';
import '../../widgets/confirm_dialog.dart';
import '../../widgets/custom_notification.dart';
import '../../widgets/settings_radio_tile.dart';
import '../../widgets/settings_card.dart';

class AppIconScreen extends StatefulWidget {
  const AppIconScreen({super.key});

  @override
  State<AppIconScreen> createState() => _AppIconScreenState();
}

class _AppIconScreenState extends State<AppIconScreen> {
  late final Listenable _state = Listenable.merge([
    AppIconConfig.selection,
    AppIconConfig.applied,
    AppIconConfig.pending,
  ]);

  @override
  void initState() {
    super.initState();
    AppIconConfig.load();
  }

  String _platformHint(AppLocalizations l10n) {
    final platform = AppIconConfig.platform;
    if (!platform.canSwitch) return l10n.appIconScreenUnsupported;
    if (platform == AppIconPlatform.android) {
      return l10n.appIconScreenHintAndroid;
    }
    if (platform.isDesktop) return l10n.appIconScreenHintDesktop;
    return l10n.appIconScreenHint;
  }

  Future<void> _select(AppIcon icon) async {
    final l10n = AppLocalizations.of(context)!;
    if (!AppIconConfig.isSupported) {
      showCustomNotification(context, l10n.appIconScreenUnsupported);
      return;
    }
    if (AppIconConfig.selection.value.choice == icon &&
        AppIconConfig.applied.value == icon) {
      return;
    }
    Haptics.selection();
    final needsConfirm =
        AppIconConfig.platform.closesOnManualSwitch &&
        AppIconConfig.applied.value != icon;
    if (needsConfirm) {
      final confirmed = await showConfirmDialog(
        context,
        title: l10n.appIconAndroidConfirmTitle,
        message: l10n.appIconAndroidConfirmMessage,
        confirmLabel: l10n.appIconAndroidConfirmAction,
      );
      if (!confirmed || !mounted) return;
    }
    try {
      await AppIconConfig.choose(icon);
      if (!mounted) return;
      showCustomNotification(
        context,
        l10n.appIconScreenChanged(_iconTitle(icon, l10n)),
      );
    } catch (e) {
      if (!mounted) return;
      final reason = e is PlatformException ? (e.message ?? e.code) : '$e';
      showCustomNotification(context, l10n.appIconScreenChangeFailed(reason));
    }
  }

  Future<void> _toggleSeasonal(bool enabled) async {
    Haptics.selection();
    await AppIconConfig.setSeasonal(enabled);
  }

  String? _seasonalStatus(AppLocalizations l10n) {
    final selection = AppIconConfig.selection.value;
    if (!selection.seasonal) return null;
    if (AppIconConfig.pending.value != null) {
      return l10n.appIconSeasonalPending;
    }
    final now = DateTime.now();
    final override = selection.seasonalOverrideAt(now);
    if (override != null) {
      return l10n.appIconSeasonalActive(
        _iconTitle(override.season.icon, l10n),
        override.lastDay,
      );
    }
    final active = IconSeason.activeAt(now);
    if (active != null && active.key == selection.manualSeason) {
      return l10n.appIconSeasonalManual;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      backgroundColor: cs.surface,
      appBar: ConnectionTitleBar(
        titleText: l10n.appIconScreenTitle,
        backgroundColor: cs.surface,
      ),
      body: SafeArea(
        top: false,
        child: ListenableBuilder(
          listenable: _state,
          builder: (context, _) {
            final selection = AppIconConfig.selection.value;
            final status = _seasonalStatus(l10n);
            return ListView(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 120),
              children: [
                SettingsPanel(
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.appIconScreenAppearance,
                        style: TextStyle(
                          color: cs.onSurface,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _platformHint(l10n),
                        style: TextStyle(
                          color: cs.onSurfaceVariant,
                          fontSize: 13,
                          height: 1.35,
                        ),
                      ),
                      const SizedBox(height: 12),
                      for (final icon in AppIconConfig.available)
                        _AppIconTile(
                          key: ValueKey(icon.id),
                          icon: icon,
                          selected: selection.choice == icon,
                          onTap: () => _select(icon),
                        ),
                    ],
                  ),
                ),
                if (AppIconConfig.isSupported) ...[
                  const SizedBox(height: 16),
                  SettingsCard(
                    children: [
                      SettingsToggleTile(
                        icon: Symbols.event_repeat,
                        label: l10n.appIconSeasonalTitle,
                        subtitle: status == null
                            ? l10n.appIconSeasonalSubtitle
                            : '${l10n.appIconSeasonalSubtitle}\n$status',
                        value: selection.seasonal,
                        onChanged: _toggleSeasonal,
                      ),
                    ],
                  ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}

class _AppIconTile extends StatelessWidget {
  final AppIcon icon;
  final bool selected;
  final VoidCallback onTap;

  const _AppIconTile({
    super.key,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    return SettingsRadioTile(
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Image.asset(
          icon.previewAsset,
          width: 56,
          height: 56,
          cacheWidth: 168,
          fit: BoxFit.cover,
        ),
      ),
      leadingGap: 16,
      label: _iconTitle(icon, l10n),
      labelStyle: TextStyle(
        color: cs.onSurface,
        fontSize: 16,
        fontWeight: FontWeight.w600,
      ),
      selected: selected,
      onTap: onTap,
    );
  }
}

String _iconTitle(AppIcon icon, AppLocalizations l10n) => switch (icon) {
  AppIcon.defaultIcon => l10n.appIconNameDefault,
  AppIcon.light => l10n.appIconNameLight,
  AppIcon.aurora => l10n.appIconNameAurora,
  AppIcon.sunset => l10n.appIconNameSunset,
  AppIcon.glass => l10n.appIconNameGlass,
  AppIcon.halloween => l10n.appIconNameHalloween,
  AppIcon.newYear => l10n.appIconNameNewYear,
};
