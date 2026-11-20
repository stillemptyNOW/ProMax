import 'dart:async';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../core/config/app_accent.dart';
import '../../../core/config/app_bubble_behavior.dart';
import '../../../core/config/app_bubble_shape.dart';
import '../../../core/config/app_chat_chrome.dart';
import '../../../core/config/app_composer_background.dart';
import '../../../core/config/app_composer_style.dart';
import '../../../core/config/app_design.dart';
import '../../../core/config/app_nav_pill_style.dart';
import '../../../core/config/app_pill_gradient.dart';
import '../../../core/config/app_spectrum_background.dart';
import '../../../core/config/app_visual_style.dart';
import '../../../core/utils/bubble_radius.dart';
import '../../../core/utils/debouncer.dart';
import '../../../core/utils/haptics.dart';
import '../../../l10n/app_localizations.dart';
import '../../../main.dart';
import '../../theme/promax_theme.dart';
import '../../widgets/color_wheel_picker.dart';
import '../../widgets/connection_status.dart';
import '../../widgets/liquid_glass.dart';
import '../../widgets/settings_card.dart';

part 'appearance_preview.dart';

enum _Section { style, chats, panels }

String _hex(Color color) =>
    '#${(color.toARGB32() & 0xffffff).toRadixString(16).padLeft(6, '0').toUpperCase()}';

class AppearanceScreen extends StatefulWidget {
  const AppearanceScreen({super.key});

  @override
  State<AppearanceScreen> createState() => _AppearanceScreenState();
}

class _AppearanceScreenState extends State<AppearanceScreen> {
  final _accent = ValueNotifier<Color?>(null);
  final _debounce = Debouncer(const Duration(milliseconds: 350));
  ProMaxAppState? _app;
  var _section = _Section.style;
  var _editingColor = false;
  var _accentPending = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final app = ProMaxApp.stateOf(context);
    if (app != _app) {
      _app = app;
      _accent.value = app?.accentSeed.value;
    }
  }

  void _commitAccent() {
    _debounce.cancel();
    if (!_accentPending) return;
    _accentPending = false;
    final app = _app;
    if (app != null && app.mounted) {
      unawaited(app.applyAccentColor(_accent.value));
    }
  }

  void _changeAccent(Color? value, {bool dragging = false}) {
    if (_accent.value == value) return;
    _accent.value = value;
    _accentPending = true;
    if (dragging) {
      _debounce.run(_commitAccent);
    } else {
      Haptics.selection();
      _commitAccent();
    }
  }

  @override
  void dispose() {
    _commitAccent();
    _debounce.dispose();
    _accent.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    final preview = _AppearancePreview(accent: _accent);
    final sections = {
      _Section.style: (l10n.appearanceSectionStyle, Symbols.palette),
      _Section.chats: (l10n.chatListNavChats, Symbols.chat_bubble),
      _Section.panels: (l10n.appearanceSectionPanels, Symbols.layers),
    };
    final controls = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            for (final MapEntry(key: section, value: (label, icon))
                in sections.entries)
              ChoiceChip(
                avatar: Icon(icon, size: 18),
                label: Text(label),
                selected: _section == section,
                showCheckmark: false,
                onSelected: (selected) {
                  if (!selected) return;
                  Haptics.selection();
                  setState(() => _section = section);
                },
              ),
          ],
        ),
        const SizedBox(height: 12),
        ...switch (_section) {
          _Section.style => _styleControls(l10n),
          _Section.chats => _chatControls(l10n),
          _Section.panels => _panelControls(l10n),
        },
      ],
    );

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: ConnectionTitleBar(
        titleText: l10n.appearanceTitle,
        backgroundColor: cs.surface,
      ),
      body: SafeArea(
        top: false,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 780;
            return ListView(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
              children: [
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1040),
                    child: wide
                        ? Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(child: preview),
                              const SizedBox(width: 24),
                              Expanded(flex: 2, child: controls),
                            ],
                          )
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              preview,
                              const SizedBox(height: 16),
                              controls,
                            ],
                          ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  List<Widget> _styleControls(AppLocalizations l10n) => [
    _Panel(
      title: l10n.appearanceAccentColorTitle,
      subtitle: l10n.appearanceAccentColorSubtitle,
      child: ValueListenableBuilder(
        valueListenable: _accent,
        builder: (context, accent, _) {
          final color = accent ?? Theme.of(context).colorScheme.primary;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final preset in AppAccent.presets)
                    _AccentSwatch(
                      color: preset.seed,
                      label: preset.seed == null
                          ? l10n.appearanceAccentColorSystem
                          : _hex(preset.seed!),
                      selected: accent?.toARGB32() == preset.seed?.toARGB32(),
                      onTap: () => _changeAccent(preset.seed),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () => setState(() => _editingColor = !_editingColor),
                icon: Icon(
                  _editingColor ? Symbols.expand_less : Symbols.palette,
                  size: 18,
                ),
                label: Text(
                  accent == null
                      ? l10n.appearanceCustomColor
                      : "${l10n.appearanceCustomColor} · ${_hex(accent)}",
                ),
              ),
              AnimatedSize(
                duration: const Duration(milliseconds: 200),
                alignment: Alignment.topCenter,
                child: !_editingColor
                    ? const SizedBox.shrink()
                    : Padding(
                        padding: const EdgeInsets.only(top: 16),
                        child: Column(
                          children: [
                            ColorWheelPicker(
                              color: color,
                              onChanged: (color) =>
                                  _changeAccent(color, dragging: true),
                            ),
                            const SizedBox(height: 16),
                            _HexColorField(
                              color: color,
                              onApply: _changeAccent,
                            ),
                          ],
                        ),
                      ),
              ),
            ],
          );
        },
      ),
    ),
    _Panel(
      title: l10n.appearanceVisualStyleTitle,
      subtitle: l10n.appearanceVisualStyleSubtitle,
      child: _Choices(
        setting: AppVisualStyle.current,
        fallback: LiquidGlass.isSupported ? null : VisualStyle.glossy,
        options: {
          VisualStyle.materialYou: l10n.appearanceVisualStyleMaterialYou,
          VisualStyle.glossy: l10n.appearanceVisualStyleGlossy,
          if (LiquidGlass.isSupported)
            VisualStyle.liquidGlass: l10n.appearanceVisualStyleLiquidGlass,
        },
        onSelected: _applyVisualStyle,
      ),
    ),
    SettingsCard(
      children: [
        _Toggle(
          icon: Symbols.design_services,
          title: l10n.appClassicDesignTitle,
          subtitle: l10n.appClassicDesignHint,
          setting: AppDesign.classic,
          onChanged: AppDesign.saveClassic,
        ),
        _Toggle(
          icon: Symbols.graphic_eq,
          title: l10n.appearanceSpectrumTitle,
          subtitle: l10n.appearanceSpectrumSubtitle,
          setting: AppSpectrumBackground.current,
          onChanged: AppSpectrumBackground.save,
        ),
      ],
    ),
  ];

  List<Widget> _chatControls(AppLocalizations l10n) => [
    _Panel(
      title: l10n.appearanceBubbleShapeTitle,
      subtitle: l10n.appearanceBubbleShapeSubtitle,
      child: _Choices(
        setting: AppBubbleShape.current,
        options: {
          BubbleStyle.promax: 'ProMax',
          BubbleStyle.mobile: l10n.appearanceBubbleShapeMobile,
          BubbleStyle.desktop: l10n.appearanceBubbleShapeDesktop,
        },
        onSelected: AppBubbleShape.save,
      ),
    ),
    _Panel(
      title: l10n.appearanceBubbleBehaviorTitle,
      subtitle: l10n.appearanceBubbleBehaviorSubtitle,
      child: _Choices(
        setting: AppBubbleBehavior.current,
        options: {
          BubbleBehavior.mutable: l10n.appearanceBubbleBehaviorMutable,
          BubbleBehavior.immutable: l10n.appearanceBubbleBehaviorImmutable,
        },
        onSelected: AppBubbleBehavior.save,
      ),
    ),
  ];

  List<Widget> _panelControls(AppLocalizations l10n) => [
    _Panel(
      title: l10n.appearanceChatChromeTitle,
      subtitle: l10n.appearanceChatChromeSubtitle,
      child: _Choices(
        setting: AppChatChrome.current,
        fallback: LiquidGlass.isSupported ? null : ChatChromeStyle.transparent,
        options: {
          ChatChromeStyle.color: l10n.appearanceChatChromeColor,
          ChatChromeStyle.blur: l10n.appearanceChatChromeBlur,
          ChatChromeStyle.none: l10n.appearanceChatChromeNone,
          ChatChromeStyle.transparent: l10n.appearanceChatChromeTransparent,
          if (LiquidGlass.isSupported)
            ChatChromeStyle.liquidGlass: l10n.appearanceGlassMaterial,
        },
        onSelected: AppChatChrome.save,
      ),
    ),
    _Panel(
      title: l10n.appearanceComposerTitle,
      subtitle: l10n.appearanceComposerSubtitle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Choices(
            setting: AppComposerStyle.current,
            options: {
              ComposerStyle.auto: l10n.appearanceStyleAuto,
              ComposerStyle.glossy: l10n.appearanceVisualStyleGlossy,
              ComposerStyle.materialYou: l10n.appearanceVisualStyleMaterialYou,
            },
            onSelected: AppComposerStyle.save,
          ),
          const Divider(height: 20),
          _Choices(
            setting: AppComposerBackground.current,
            fallback: LiquidGlass.isSupported
                ? null
                : ComposerBackground.frostBlur,
            options: {
              ComposerBackground.standard:
                  l10n.appearanceComposerBackgroundStandard,
              ComposerBackground.frostBlur:
                  l10n.appearanceComposerBackgroundFrost,
              if (LiquidGlass.isSupported)
                ComposerBackground.liquidGlass: l10n.appearanceGlassMaterial,
            },
            onSelected: AppComposerBackground.save,
          ),
        ],
      ),
    ),
    _Panel(
      title: l10n.appearanceNavPillTitle,
      subtitle: l10n.appearanceNavPillSubtitle,
      child: _Choices(
        setting: AppNavPillStyle.current,
        fallback: LiquidGlass.isSupported ? null : NavPillStyle.frostBlur,
        options: {
          NavPillStyle.auto: l10n.appearanceStyleAuto,
          NavPillStyle.glossy: l10n.appearanceNavPillGlossy,
          NavPillStyle.frostBlur: l10n.appearanceNavPillFrost,
          if (LiquidGlass.isSupported)
            NavPillStyle.liquidGlass: l10n.appearanceGlassMaterial,
        },
        onSelected: AppNavPillStyle.save,
      ),
    ),
    SettingsCard(
      children: [
        _Toggle(
          icon: Symbols.blur_on,
          title: l10n.appearanceGradientTitle,
          subtitle: l10n.appearanceGradientSubtitle,
          setting: AppPillGradient.current,
          onChanged: AppPillGradient.save,
        ),
      ],
    ),
  ];
}

void _applyVisualStyle(VisualStyle style) {
  AppVisualStyle.save(style);
  if (style == VisualStyle.liquidGlass) {
    if (AppNavPillStyle.current.value != NavPillStyle.auto) {
      AppNavPillStyle.save(NavPillStyle.liquidGlass);
    }
    AppComposerBackground.save(ComposerBackground.liquidGlass);
    AppChatChrome.save(ChatChromeStyle.liquidGlass);
    return;
  }
  if (AppNavPillStyle.current.value == NavPillStyle.liquidGlass) {
    AppNavPillStyle.save(NavPillStyle.frostBlur);
  }
  if (AppComposerBackground.current.value == ComposerBackground.liquidGlass) {
    AppComposerBackground.save(ComposerBackground.frostBlur);
  }
  if (AppChatChrome.current.value == ChatChromeStyle.liquidGlass) {
    AppChatChrome.save(ChatChromeStyle.transparent);
  }
}

class _Panel extends StatelessWidget {
  const _Panel({
    required this.title,
    required this.subtitle,
    required this.child,
  });

  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: SettingsPanel(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              subtitle,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}

class _Choices<T extends Enum> extends StatelessWidget {
  const _Choices({
    required this.setting,
    required this.options,
    required this.onSelected,
    this.fallback,
  });

  final ValueNotifier<T> setting;
  final Map<T, String> options;
  final ValueChanged<T> onSelected;
  final T? fallback;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder(
    valueListenable: setting,
    builder: (context, value, _) {
      final displayed = options.containsKey(value) ? value : fallback;
      return Wrap(
        spacing: 8,
        runSpacing: 4,
        children: [
          for (final MapEntry(key: option, value: label) in options.entries)
            ChoiceChip(
              label: Text(label),
              selected: displayed == option,
              onSelected: (selected) {
                if (!selected && option == value) return;
                Haptics.selection();
                onSelected(option);
              },
            ),
        ],
      );
    },
  );
}

class _Toggle extends StatelessWidget {
  const _Toggle({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.setting,
    required this.onChanged,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final ValueNotifier<bool> setting;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder(
    valueListenable: setting,
    builder: (context, value, _) => SettingsToggleTile(
      icon: icon,
      label: title,
      subtitle: subtitle,
      value: value,
      onChanged: onChanged,
    ),
  );
}

class _AccentSwatch extends StatelessWidget {
  const _AccentSwatch({
    required this.color,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final Color? color;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final contrast = color == null
        ? cs.onPrimaryContainer
        : ThemeData.estimateBrightnessForColor(color!) == Brightness.dark
        ? Colors.white
        : Colors.black;
    return Semantics(
      label: label,
      selected: selected,
      child: Tooltip(
        message: label,
        excludeFromSemantics: true,
        child: SizedBox.square(
          dimension: 46,
          child: IconButton(
            onPressed: onTap,
            style: IconButton.styleFrom(
              backgroundColor: color ?? cs.primaryContainer,
              foregroundColor: contrast,
              side: BorderSide(
                color: selected ? cs.onSurface : cs.outlineVariant,
                width: selected ? 2 : 1,
              ),
            ),
            icon: Icon(
              selected
                  ? Symbols.check
                  : color == null
                  ? Symbols.auto_awesome
                  : null,
              size: 18,
            ),
          ),
        ),
      ),
    );
  }
}

class _HexColorField extends StatefulWidget {
  const _HexColorField({required this.color, required this.onApply});

  final Color color;
  final ValueChanged<Color> onApply;

  @override
  State<_HexColorField> createState() => _HexColorFieldState();
}

class _HexColorFieldState extends State<_HexColorField> {
  late final _controller = TextEditingController(text: _hex(widget.color));
  final _focus = FocusNode();
  var _invalid = false;

  @override
  void didUpdateWidget(covariant _HexColorField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.color != widget.color && !_focus.hasFocus) {
      _controller.text = _hex(widget.color);
      _invalid = false;
    }
  }

  void _apply() {
    final input = _controller.text.trim();
    final match = RegExp(r'^#?([0-9a-fA-F]{6})$').firstMatch(input);
    if (match == null) {
      setState(() => _invalid = true);
      return;
    }
    final color = Color(0xff000000 | int.parse(match.group(1)!, radix: 16));
    _controller.text = _hex(color);
    setState(() => _invalid = false);
    _focus.unfocus();
    widget.onApply(color);
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return TextField(
      controller: _controller,
      focusNode: _focus,
      textCapitalization: TextCapitalization.characters,
      textInputAction: TextInputAction.done,
      autocorrect: false,
      enableSuggestions: false,
      onSubmitted: (_) => _apply(),
      onChanged: (_) {
        if (_invalid) setState(() => _invalid = false);
      },
      decoration: InputDecoration(
        labelText: 'HEX',
        hintText: '#8C9EFF',
        errorText: _invalid ? l10n.appearanceHexColorError : null,
        border: const OutlineInputBorder(),
        suffixIcon: IconButton(
          onPressed: _apply,
          tooltip: l10n.settingsLinkApply,
          icon: const Icon(Symbols.check),
        ),
      ),
    );
  }
}
