import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../core/config/app_native_glass.dart';
import '../../../core/config/platform_settings.dart';
import '../../../core/translation/translation_backend.dart';
import '../../../l10n/app_localizations.dart';
import '../../widgets/connection_status.dart';
import '../../widgets/settings_card.dart';
import 'media_devices_screen.dart';
import 'notifications_screen.dart';
import 'performance_mode_card.dart';
import 'translation_settings_screen.dart';

class PlatformSettingsScreen extends StatelessWidget {
  const PlatformSettingsScreen({super.key});

  void _open(BuildContext context, Widget screen) =>
      Navigator.push(context, MaterialPageRoute(builder: (_) => screen));

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: ConnectionTitleBar(
        titleText: '${l10n.platformSettingsTitle} · ${PlatformSettings.label}',
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
        children: [
          Text(l10n.platformSettingsHint),
          const SizedBox(height: 16),
          SettingsCard(
            children: [
              SettingsNavTile(
                icon: Symbols.notifications,
                label: l10n.platformNotifications,
                onTap: () => _open(context, const NotificationsScreen()),
              ),
              if (PlatformSettings.current != 'web')
                SettingsNavTile(
                  icon: Symbols.mic,
                  label: l10n.platformMedia,
                  onTap: () => _open(context, const MediaDevicesScreen()),
                ),
              if (MethodChannelTranslationBackend.platformSupported)
                SettingsNavTile(
                  icon: Symbols.translate,
                  label: l10n.translationSettingsTitle,
                  onTap: () =>
                      _open(context, const TranslationSettingsScreen()),
                ),
            ],
          ),
          if (NativeGlass.isSupported) ...[
            const SizedBox(height: 16),
            SettingsCard(
              children: [
                ValueListenableBuilder<bool>(
                  valueListenable: NativeGlass.enabled,
                  builder: (context, enabled, _) => SettingsToggleTile(
                    icon: Symbols.phone_iphone,
                    label: l10n.platformNativeGlass,
                    subtitle: l10n.platformNativeGlassHint,
                    value: enabled,
                    onChanged: NativeGlass.save,
                  ),
                ),
              ],
            ),
          ],
          const PerformanceModeCard(),
        ],
      ),
    );
  }
}
