import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../core/plugins/motion_blur/motion_blur_plugin.dart';
import '../../../core/plugins/native_plugin.dart';
import '../../../l10n/app_localizations.dart';
import '../../widgets/settings_card.dart';
import 'motion_blur_settings_screen.dart';

class NativePluginEntry {
  const NativePluginEntry({
    required this.plugin,
    required this.icon,
    required this.title,
    required this.description,
    required this.settings,
  });

  final NativePlugin plugin;
  final IconData icon;
  final String Function(AppLocalizations l10n) title;
  final String Function(AppLocalizations l10n) description;
  final WidgetBuilder settings;
}

final List<NativePluginEntry> nativePluginEntries = List.unmodifiable([
  NativePluginEntry(
    plugin: MotionBlurPlugin.instance,
    icon: Symbols.motion_blur,
    title: (l10n) => l10n.motionBlurTitle,
    description: (l10n) => l10n.motionBlurDescription,
    settings: (_) => const MotionBlurSettingsScreen(),
  ),
]);

class NativePluginCard extends StatelessWidget {
  const NativePluginCard({super.key, required this.entry});

  final NativePluginEntry entry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final plugin = entry.plugin;
    return SettingsCard(
      children: [
        ValueListenableBuilder<bool>(
          valueListenable: plugin.enabled,
          builder: (context, enabled, _) => SettingsToggleTile(
            icon: entry.icon,
            label: entry.title(l10n),
            subtitle:
                '${plugin.version} · ${entry.description(l10n)}\n'
                '${l10n.pluginsScreenBundled}',
            value: enabled,
            onChanged: plugin.setEnabled,
          ),
        ),
        SettingsNavTile(
          icon: Symbols.tune,
          label: l10n.pluginsScreenConfigure,
          isLast: true,
          onTap: () => Navigator.of(
            context,
          ).push(MaterialPageRoute<void>(builder: entry.settings)),
        ),
      ],
    );
  }
}
