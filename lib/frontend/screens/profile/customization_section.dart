import 'package:flutter/material.dart';

import '../../../core/config/promax_atmosphere.dart';
import '../../../core/config/promax_theme_presets.dart';
import '../../widgets/promax_ui.dart';
import 'atmosphere_screen.dart';
import 'promax_design_screen.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../core/config/ios_release.dart';
import '../../../core/utils/haptics.dart';
import '../../../l10n/app_localizations.dart';
import '../../widgets/settings_card.dart';
import 'app_icon_screen.dart';
import 'appearance_screen.dart';
import 'chat_background_screen.dart';
import 'font_settings_screen.dart';
import 'message_actions_screen.dart';
import 'theme_settings_screen.dart';

class _CustomizationCategory {
  final IconData icon;
  final String Function(AppLocalizations l10n) title;
  final WidgetBuilder builder;
  final bool Function() isAvailable;

  const _CustomizationCategory({
    required this.icon,
    required this.title,
    required this.builder,
    this.isAvailable = _always,
  });

  static bool _always() => true;
}

class CustomizationSection extends StatefulWidget {
  const CustomizationSection({super.key});

  @override
  State<CustomizationSection> createState() => _CustomizationSectionState();
}

class _CustomizationSectionState extends State<CustomizationSection> {
  static final List<_CustomizationCategory> _categories = [
    _CustomizationCategory(
      icon: Symbols.dark_mode,
      title: (l10n) => l10n.themeSettingsTitle,
      builder: (context) => const ThemeSettingsScreen(),
    ),
    _CustomizationCategory(
      icon: Symbols.styler,
      title: (l10n) => l10n.appearanceTitle,
      builder: (context) => const AppearanceScreen(),
    ),
    _CustomizationCategory(
      icon: Symbols.wallpaper,
      title: (l10n) => l10n.customizationChatBackground,
      builder: (context) => const ChatBackgroundScreen(),
    ),
    _CustomizationCategory(
      icon: Symbols.text_fields,
      title: (l10n) => l10n.fontSettingsTitle,
      builder: (context) => const FontSettingsScreen(),
    ),
    _CustomizationCategory(
      icon: Symbols.touch_app,
      title: (l10n) => l10n.customizationMessageActions,
      builder: (context) => const MessageActionsScreen(),
      isAvailable: _messageActionsStyleChoice,
    ),
    _CustomizationCategory(
      icon: Symbols.apps,
      title: (l10n) => l10n.customizationAppIcon,
      builder: (context) => const AppIconScreen(),
    ),
  ];

  static bool _messageActionsStyleChoice() =>
      IosRelease.messageActionsStyleChoice;

  void _open(Widget Function(BuildContext) builder) {
    Haptics.tap();
    Navigator.push(context, MaterialPageRoute(builder: builder));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final categories = [
      for (final category in _categories)
        if (category.isAvailable()) category,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const ProMaxSectionTitle('Оформление'),
        SettingsCard(
          children: [
            ValueListenableBuilder<String?>(
              valueListenable: ProMaxThemePresets.selected,
              builder: (context, id, _) => SettingsNavTile(
                icon: Symbols.palette,
                label: 'Темы и стекло',
                value: ProMaxThemePresets.byId(id)?.title ?? 'Своя',
                onTap: () => _open((_) => const ProMaxDesignScreen()),
              ),
            ),
            ValueListenableBuilder<AtmosphereEffect>(
              valueListenable: ProMaxAtmosphere.effect,
              builder: (context, effect, _) => SettingsNavTile(
                icon: Symbols.ac_unit,
                label: 'Атмосфера',
                value: effect.title,
                onTap: () => _open((_) => const AtmosphereScreen()),
              ),
            ),
            for (var i = 0; i < categories.length; i++)
              SettingsNavTile(
                icon: categories[i].icon,
                label: categories[i].title(l10n),
                onTap: () => _open(categories[i].builder),
                isLast: i == categories.length - 1,
              ),
          ],
        ),
      ],
    );
  }
}
