import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../widgets/connection_status.dart';

import '../../../core/config/build_profile.dart';
import '../../../core/config/promax_settings.dart';
import '../../../l10n/app_localizations.dart';
import '../../../main.dart';
import '../../widgets/section_header.dart';
import '../../widgets/settings_card.dart';
import 'plugins_screen.dart';
import 'quick_reaction_screen.dart';
import 'promax_transfer_card.dart';

class ProMaxSettingsScreen extends StatelessWidget {
  const ProMaxSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: ConnectionTitleBar(
        titleText: 'ProMax',
        backgroundColor: cs.surface,
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 120),
          children: [
            SectionHeader(
              l10n.authLimitsSignupMessagesTitle,
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
              fontSize: 14,
            ),
            SettingsCard(
              children: [
                ValueListenableBuilder<String>(
                  valueListenable: ProMaxSettings.quickReaction,
                  builder: (context, emoji, _) => SettingsNavTile(
                    icon: Symbols.add_reaction,
                    label: '${l10n.proMaxQuickReaction} $emoji',
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const QuickReactionScreen(),
                      ),
                    ),
                  ),
                ),
                if (BuildProfile.plugins)
                  SettingsNavTile(
                    icon: Symbols.extension,
                    label: l10n.pluginsScreenTitle,
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const PluginsScreen()),
                    ),
                  ),
                if (BuildProfile.hiddenContentViewers) ...[
                  ValueListenableBuilder<bool>(
                    valueListenable: ProMaxSettings.viewDeleted,
                    builder: (context, value, _) => SettingsToggleTile(
                      icon: Symbols.delete_history,
                      label: l10n.proMaxSettingLabel0,
                      subtitle: l10n.proMaxSettingsViewDeletedSubtitle,
                      value: value,
                      onChanged: ProMaxSettings.setViewDeleted,
                    ),
                  ),
                  ValueListenableBuilder<bool>(
                    valueListenable: ProMaxSettings.viewRedacted,
                    builder: (context, value, _) => SettingsToggleTile(
                      icon: Symbols.history_edu,
                      label: l10n.proMaxSettingLabel1,
                      subtitle: l10n.proMaxSettingsViewRedactedSubtitle,
                      value: value,
                      onChanged: ProMaxSettings.setViewRedacted,
                    ),
                  ),
                ],
                ValueListenableBuilder<bool>(
                  valueListenable: ProMaxSettings.fullTimestamp,
                  builder: (context, value, _) => SettingsToggleTile(
                    icon: Symbols.schedule,
                    label: l10n.proMaxSettingLabel2,
                    subtitle: l10n.proMaxSettingsFullTimestampSubtitle,
                    value: value,
                    onChanged: ProMaxSettings.setFullTimestamp,
                  ),
                ),
                ValueListenableBuilder<bool>(
                  valueListenable: ProMaxSettings.showForward,
                  builder: (context, value, _) => SettingsToggleTile(
                    icon: Symbols.forward,
                    label: l10n.proMaxSettingLabel3,
                    subtitle: l10n.proMaxSettingsShowForwardSubtitle,
                    value: value,
                    onChanged: ProMaxSettings.setShowForward,
                  ),
                ),
                ValueListenableBuilder<bool>(
                  valueListenable: ProMaxSettings.showTypingTime,
                  builder: (context, value, _) => SettingsToggleTile(
                    icon: Symbols.timer,
                    label: l10n.proMaxSettingLabel4,
                    subtitle: l10n.proMaxSettingsTypingTimeSubtitle,
                    value: value,
                    onChanged: ProMaxSettings.setShowTypingTime,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            SectionHeader(
              l10n.proMaxSettingsFoldersHeader,
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
              fontSize: 14,
            ),
            SettingsCard(
              children: [
                ValueListenableBuilder<bool>(
                  valueListenable: ProMaxSettings.hideAllChatsFolder,
                  builder: (context, value, _) => SettingsToggleTile(
                    icon: Symbols.folder_off,
                    label: l10n.proMaxSettingLabel5,
                    subtitle: l10n.proMaxSettingsHideAllFolderSubtitle,
                    value: value,
                    onChanged: ProMaxSettings.setHideAllChatsFolder,
                  ),
                ),
                ValueListenableBuilder<bool>(
                  valueListenable: ProMaxSettings.showHiddenChats,
                  builder: (context, value, _) => SettingsToggleTile(
                    icon: Symbols.visibility_lock,
                    label: l10n.proMaxSettingLabel6,
                    subtitle: l10n.proMaxSettingsShowHiddenChatsSubtitle,
                    value: value,
                    onChanged: ProMaxSettings.setShowHiddenChats,
                  ),
                ),
                ValueListenableBuilder<bool>(
                  valueListenable: ProMaxSettings.archiveOnPull,
                  builder: (context, value, _) => SettingsToggleTile(
                    icon: Symbols.archive,
                    label: l10n.proMaxSettingLabel7,
                    subtitle: l10n.proMaxSettingsArchiveOnPullSubtitle,
                    value: value,
                    onChanged: ProMaxSettings.setArchiveOnPull,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            SectionHeader(
              l10n.proMaxSettingLabel8,
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
              fontSize: 14,
            ),
            SettingsCard(
              children: [
                ValueListenableBuilder<bool>(
                  valueListenable: ProMaxSettings.ghostMode,
                  builder: (context, value, _) => SettingsToggleTile(
                    icon: Symbols.visibility_off,
                    label: l10n.proMaxSettingLabel8,
                    subtitle: l10n.proMaxSettingsGhostModeSubtitle,
                    value: value,
                    onChanged: _setGhostMode,
                  ),
                ),
                ValueListenableBuilder<bool>(
                  valueListenable: ProMaxSettings.antiRead,
                  builder: (context, value, _) => SettingsToggleTile(
                    icon: Symbols.mark_chat_read,
                    label: l10n.proMaxSettingLabel9,
                    subtitle: l10n.proMaxSettingsAntiReadSubtitle,
                    value: value,
                    onChanged: ProMaxSettings.setAntiRead,
                  ),
                ),
                ValueListenableBuilder<bool>(
                  valueListenable: ProMaxSettings.hideStoryViews,
                  builder: (context, value, _) => SettingsToggleTile(
                    icon: Symbols.visibility_off,
                    label: 'Не отмечать просмотры историй',
                    subtitle: 'Отметка просмотра не отправляется собеседнику',
                    value: value,
                    onChanged: ProMaxSettings.setHideStoryViews,
                  ),
                ),
                ValueListenableBuilder<bool>(
                  valueListenable: ProMaxSettings.noTyping,
                  builder: (context, value, _) => SettingsToggleTile(
                    icon: Symbols.edit_off,
                    label: 'Не отправлять статус «печатает»',
                    subtitle: 'Не отправлять собеседникам индикатор набора',
                    value: value,
                    onChanged: ProMaxSettings.setNoTyping,
                  ),
                ),
                ValueListenableBuilder<bool>(
                  valueListenable: ProMaxSettings.selfOnlineCheck,
                  builder: (context, value, _) => SettingsToggleTile(
                    icon: Symbols.radar,
                    label: l10n.proMaxSettingLabel10,
                    subtitle: l10n.proMaxSettingsSelfOnlineCheckSubtitle,
                    value: value,
                    onChanged: ProMaxSettings.setSelfOnlineCheck,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            const SectionHeader(
              'Оформление',
              padding: EdgeInsets.fromLTRB(8, 0, 8, 8),
              fontSize: 14,
            ),
            SettingsCard(
              children: [
                ValueListenableBuilder<bool>(
                  valueListenable: ProMaxSettings.snowEffect,
                  builder: (context, value, _) => SettingsToggleTile(
                    icon: Symbols.ac_unit,
                    label: 'Снег на экране',
                    subtitle: 'Лёгкий анимированный снег поверх интерфейса',
                    value: value,
                    onChanged: ProMaxSettings.setSnowEffect,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            SectionHeader(
              'Диагностика',
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
              fontSize: 14,
            ),
            SettingsCard(
              children: [
                ValueListenableBuilder<bool>(
                  valueListenable: ProMaxSettings.recordDebugLogs,
                  builder: (context, value, _) => SettingsToggleTile(
                    icon: Symbols.bug_report,
                    label: l10n.proMaxSettingsDebugLogsLabel,
                    subtitle: l10n.proMaxSettingsDebugLogsSubtitle,
                    value: value,
                    onChanged: ProMaxSettings.setRecordDebugLogs,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            SectionHeader(
              l10n.proMaxArchiveTitle,
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
              fontSize: 14,
            ),
            const ProMaxTransferCard(),
          ],
        ),
      ),
    );
  }

  Future<void> _setGhostMode(bool value) async {
    await ProMaxSettings.setGhostMode(value);
    api.sendPing(interactive: !value);
  }
}
