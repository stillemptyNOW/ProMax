import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../widgets/connection_status.dart';

import '../../../core/config/app_shape.dart';
import '../../../core/config/build_profile.dart';
import '../../../core/config/promax_atmosphere.dart';
import '../../../core/config/promax_settings.dart';
import '../../../core/config/promax_theme_presets.dart';
import '../../../l10n/app_localizations.dart';
import '../../../main.dart';
import '../../widgets/promax_ui.dart';
import '../../widgets/settings_card.dart';
import '../digital_id/digital_id_screen.dart';
import '../../../core/storage/bookmarks_store.dart';
import 'atmosphere_screen.dart';
import 'bookmarks_screen.dart';
import 'export_reader_screen.dart';
import 'plugins_screen.dart';
import 'promax_design_screen.dart';
import 'promax_transfer_card.dart';
import 'quick_reaction_screen.dart';

class ProMaxSettingsScreen extends StatelessWidget {
  const ProMaxSettingsScreen({super.key});

  void _open(BuildContext context, Widget screen) =>
      Navigator.push(context, MaterialPageRoute(builder: (_) => screen));

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
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
          children: [
            _ProMaxHero(onGhostChanged: _setGhostMode),
            const ProMaxSectionTitle('Внешний вид'),
            SettingsCard(
              children: [
                ValueListenableBuilder<String?>(
                  valueListenable: ProMaxThemePresets.selected,
                  builder: (context, id, _) => SettingsNavTile(
                    icon: Symbols.palette,
                    label: 'Темы и стекло',
                    value: ProMaxThemePresets.byId(id)?.title ?? 'Своя',
                    onTap: () => _open(context, const ProMaxDesignScreen()),
                  ),
                ),
                ValueListenableBuilder<AtmosphereEffect>(
                  valueListenable: ProMaxAtmosphere.effect,
                  builder: (context, effect, _) => SettingsNavTile(
                    icon: atmosphereIcon(
                      effect == AtmosphereEffect.none
                          ? AtmosphereEffect.snow
                          : effect,
                    ),
                    label: 'Атмосфера',
                    value: effect.title,
                    onTap: () => _open(context, const AtmosphereScreen()),
                  ),
                ),
              ],
            ),
            const ProMaxSectionTitle('Призрак и приватность'),
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
                  valueListenable: ProMaxSettings.noTyping,
                  builder: (context, value, _) => SettingsToggleTile(
                    icon: Symbols.edit_off,
                    label: 'Не отправлять «печатает»',
                    subtitle: 'Собеседник не увидит, что вы набираете текст',
                    value: value,
                    onChanged: ProMaxSettings.setNoTyping,
                  ),
                ),
                ValueListenableBuilder<bool>(
                  valueListenable: ProMaxSettings.hideStoryViews,
                  builder: (context, value, _) => SettingsToggleTile(
                    icon: Symbols.auto_stories,
                    label: 'Не отмечать просмотры историй',
                    subtitle: 'Автор истории не узнает, что вы её смотрели',
                    value: value,
                    onChanged: ProMaxSettings.setHideStoryViews,
                  ),
                ),
                ValueListenableBuilder<bool>(
                  valueListenable: ProMaxSettings.streamerMode,
                  builder: (context, value, _) => SettingsToggleTile(
                    icon: Symbols.cast,
                    label: 'Режим стримера',
                    subtitle:
                        'Размывает номера, ID и превью сообщений, прячет текст уведомлений',
                    value: value,
                    onChanged: ProMaxSettings.setStreamerMode,
                  ),
                ),
                ValueListenableBuilder<bool>(
                  valueListenable: ProMaxSettings.switcherBlur,
                  builder: (context, value, _) => SettingsToggleTile(
                    icon: Symbols.blur_on,
                    label: 'Размытие в переключателе',
                    subtitle:
                        'В списке открытых приложений iOS не видно содержимое',
                    value: value,
                    onChanged: ProMaxSettings.setSwitcherBlur,
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
            const ProMaxSectionTitle('Сообщения'),
            SettingsCard(
              children: [
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
                ValueListenableBuilder<String>(
                  valueListenable: ProMaxSettings.quickReaction,
                  builder: (context, emoji, _) => SettingsNavTile(
                    icon: Symbols.add_reaction,
                    label: l10n.proMaxQuickReaction,
                    value: emoji,
                    onTap: () => _open(context, const QuickReactionScreen()),
                  ),
                ),
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
            const ProMaxSectionTitle('Инструменты'),
            SettingsCard(
              children: [
                ValueListenableBuilder<List<MessageBookmark>>(
                  valueListenable: BookmarksStore.instance.items,
                  builder: (context, items, _) => SettingsNavTile(
                    icon: Symbols.bookmarks,
                    label: 'Закладки',
                    value: items.isEmpty ? null : '${items.length}',
                    onTap: () => _open(context, const BookmarksScreen()),
                  ),
                ),
                SettingsNavTile(
                  icon: Symbols.lock_open,
                  label: 'Открыть экспорт .pmxchat',
                  onTap: () => _open(context, const ExportReaderScreen()),
                ),
                if (BuildProfile.plugins)
                  SettingsNavTile(
                    icon: Symbols.extension,
                    label: AppLocalizations.of(context)!.pluginsScreenTitle,
                    onTap: () => _open(context, const PluginsScreen()),
                  ),
              ],
            ),
            const ProMaxSectionTitle('Чаты и папки'),
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
            const ProMaxSectionTitle('Диагностика'),
            SettingsCard(
              children: [
                if (BuildProfile.digitalId)
                  SettingsNavTile(
                    icon: Symbols.badge,
                    label: 'Цифровой ID: нативный режим и отчёт',
                    onTap: () => _open(context, const DigitalIdScreen()),
                  ),
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
            ProMaxSectionTitle(l10n.proMaxArchiveTitle),
            const ProMaxTransferCard(),
            const SizedBox(height: 18),
            Center(
              child: Text(
                'ProMax основан на открытом клиенте Komet · GPLv3',
                style: TextStyle(color: cs.outline, fontSize: 12),
              ),
            ),
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

class _ProMaxHero extends StatelessWidget {
  const _ProMaxHero({required this.onGhostChanged});

  final ValueChanged<bool> onGhostChanged;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ValueListenableBuilder<String?>(
      valueListenable: ProMaxThemePresets.selected,
      builder: (context, id, _) {
        final preset = ProMaxThemePresets.byId(id);
        final colors =
            preset?.preview ??
            [
              Color.lerp(cs.primary, Colors.black, 0.35)!,
              Color.lerp(cs.primary, Colors.black, 0.75)!,
            ];
        return Container(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppShape.card + 6),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: colors,
            ),
            border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 46,
                    height: 46,
                    padding: const EdgeInsets.all(9),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Image.asset(
                      'assets/promax.png',
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'ProMax',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.4,
                          ),
                        ),
                        FutureBuilder<PackageInfo>(
                          future: PackageInfo.fromPlatform(),
                          builder: (context, snapshot) => Text(
                            snapshot.hasData
                                ? 'Версия ${snapshot.data!.version} · ${preset?.title ?? 'своя тема'}'
                                : 'Твой MAX — по-своему',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.72),
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                childAspectRatio: 2.35,
                children: [
                  ValueListenableBuilder<bool>(
                    valueListenable: ProMaxSettings.ghostMode,
                    builder: (context, on, _) => _ControlTile(
                      icon: Symbols.visibility_off,
                      label: 'Призрак',
                      on: on,
                      onTap: () => onGhostChanged(!on),
                    ),
                  ),
                  ValueListenableBuilder<bool>(
                    valueListenable: ProMaxSettings.antiRead,
                    builder: (context, on, _) => _ControlTile(
                      icon: Symbols.mark_chat_read,
                      label: 'Не читать',
                      on: on,
                      onTap: () => ProMaxSettings.setAntiRead(!on),
                    ),
                  ),
                  ValueListenableBuilder<bool>(
                    valueListenable: ProMaxSettings.streamerMode,
                    builder: (context, on, _) => _ControlTile(
                      icon: Symbols.cast,
                      label: 'Стример',
                      on: on,
                      onTap: () => ProMaxSettings.setStreamerMode(!on),
                    ),
                  ),
                  ValueListenableBuilder<AtmosphereEffect>(
                    valueListenable: ProMaxAtmosphere.effect,
                    builder: (context, effect, _) => _ControlTile(
                      icon: atmosphereIcon(
                        effect == AtmosphereEffect.none
                            ? AtmosphereEffect.snow
                            : effect,
                      ),
                      label: 'Атмосфера',
                      status: effect == AtmosphereEffect.none
                          ? 'Выкл'
                          : effect.title,
                      on: effect != AtmosphereEffect.none,
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const AtmosphereScreen(),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ControlTile extends StatelessWidget {
  const _ControlTile({
    required this.icon,
    required this.label,
    required this.on,
    required this.onTap,
    this.status,
  });

  final IconData icon;
  final String label;
  final bool on;
  final VoidCallback onTap;
  final String? status;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final ink = on ? const Color(0xFF111217) : Colors.white;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: on
              ? Colors.white.withValues(alpha: 0.94)
              : Colors.black.withValues(alpha: 0.22),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: Colors.white.withValues(alpha: on ? 0 : 0.12),
          ),
        ),
        child: Row(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: on ? cs.primary : Colors.white.withValues(alpha: 0.14),
              ),
              child: Icon(
                icon,
                size: 18,
                fill: on ? 1 : 0,
                color: on ? cs.onPrimary : Colors.white,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: ink,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    status ?? (on ? 'Вкл' : 'Выкл'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: ink.withValues(alpha: 0.6),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ProMaxBannerCard extends StatelessWidget {
  const ProMaxBannerCard({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ValueListenableBuilder<String?>(
      valueListenable: ProMaxThemePresets.selected,
      builder: (context, id, _) {
        final colors =
            ProMaxThemePresets.byId(id)?.preview ??
            [
              Color.lerp(cs.primary, Colors.black, 0.35)!,
              Color.lerp(cs.primary, Colors.black, 0.75)!,
            ];
        return Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(AppShape.card),
          clipBehavior: Clip.antiAlias,
          child: Ink(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: colors,
              ),
            ),
            child: InkWell(
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ProMaxSettingsScreen()),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
                child: Row(
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(13),
                      ),
                      child: Image.asset(
                        'assets/promax.png',
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'ProMax',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Призрак, темы, атмосфера и все фишки',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.82),
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Icon(Symbols.chevron_right, color: Colors.white),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
