import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../core/config/app_shape.dart';
import '../../../core/config/promax_glass.dart';
import '../../../core/config/promax_theme_presets.dart';
import '../../../core/utils/haptics.dart';
import '../../../main.dart';
import '../../widgets/atmosphere_overlay.dart';
import '../../widgets/connection_status.dart';
import '../../widgets/liquid_glass.dart';
import '../../widgets/promax_ui.dart';
import '../../widgets/settings_card.dart';
import 'app_icon_screen.dart';
import 'appearance_screen.dart';
import 'atmosphere_screen.dart';
import '../../../core/config/promax_atmosphere.dart';

class ProMaxDesignScreen extends StatelessWidget {
  const ProMaxDesignScreen({super.key});

  Future<void> _apply(BuildContext context, ProMaxThemePreset preset) async {
    Haptics.selection();
    final app = ProMaxApp.stateOf(context);
    await app?.applyAccentColor(preset.accent);
    await app?.applyAmoled(preset.amoled);
    await ProMaxThemePresets.applyLook(preset);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: cs.surface,
      appBar: ConnectionTitleBar(
        titleText: 'Темы и стекло',
        backgroundColor: cs.surface,
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
          children: [
            const GlassPreview(),
            const ProMaxSectionTitle('Темы ProMax'),
            ValueListenableBuilder<String?>(
              valueListenable: ProMaxThemePresets.selected,
              builder: (context, selected, _) => GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 1.45,
                children: [
                  for (final preset in ProMaxThemePresets.all)
                    _PresetCard(
                      preset: preset,
                      selected: preset.id == selected,
                      onTap: () => _apply(context, preset),
                    ),
                ],
              ),
            ),
            ProMaxSectionTitle(
              'Стекло',
              trailing: TextButton(
                onPressed: () async {
                  await ProMaxGlass.reset();
                  await ProMaxThemePresets.remember(null);
                },
                child: const Text('Сбросить'),
              ),
            ),
            SettingsCard(
              children: [
                ProMaxSliderTile(
                  icon: Symbols.blur_on,
                  label: 'Размытие',
                  parameter: ProMaxGlass.blur,
                  format: (v) => '${(v * 100).round()}%',
                ),
                ProMaxSliderTile(
                  icon: Symbols.water_drop,
                  label: 'Преломление',
                  parameter: ProMaxGlass.refraction,
                  format: (v) => v.toStringAsFixed(0),
                ),
                ProMaxSliderTile(
                  icon: Symbols.flare,
                  label: 'Блик',
                  parameter: ProMaxGlass.specular,
                  format: (v) => '${(v * 100).round()}%',
                ),
                ProMaxSliderTile(
                  icon: Symbols.gradient,
                  label: 'Радужность',
                  parameter: ProMaxGlass.chroma,
                  format: (v) => '${(v * 250).round()}%',
                ),
                ProMaxSliderTile(
                  icon: Symbols.rounded_corner,
                  label: 'Ободок',
                  parameter: ProMaxGlass.rim,
                  format: (v) => v.toStringAsFixed(1),
                ),
                ProMaxSliderTile(
                  icon: Symbols.format_color_fill,
                  label: 'Тонировка',
                  parameter: ProMaxGlass.tint,
                  format: (v) => '${(v * 100).round()}%',
                ),
              ],
            ),
            const ProMaxSectionTitle('Ещё'),
            SettingsCard(
              children: [
                SettingsNavTile(
                  icon: Symbols.ac_unit,
                  label: 'Атмосфера',
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const AtmosphereScreen()),
                  ),
                ),
                SettingsNavTile(
                  icon: Symbols.apps,
                  label: 'Иконка приложения',
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const AppIconScreen()),
                  ),
                ),
                SettingsNavTile(
                  icon: Symbols.tune,
                  label: 'Шрифты, пузыри, обои и панели',
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const AppearanceScreen()),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _PresetCard extends StatelessWidget {
  const _PresetCard({
    required this.preset,
    required this.selected,
    required this.onTap,
  });

  final ProMaxThemePreset preset;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppShape.card),
          border: Border.all(
            color: selected ? cs.primary : Colors.transparent,
            width: 2.5,
          ),
          boxShadow: [
            if (selected)
              BoxShadow(
                color: cs.primary.withValues(alpha: 0.35),
                blurRadius: 18,
              ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(AppShape.card - 2),
          child: Stack(
            fit: StackFit.expand,
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: preset.preview,
                  ),
                ),
              ),
              Positioned(
                right: -18,
                top: -18,
                child: Container(
                  width: 70,
                  height: 70,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withValues(alpha: 0.12),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            preset.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              shadows: [
                                Shadow(color: Colors.black38, blurRadius: 6),
                              ],
                            ),
                          ),
                        ),
                        if (selected)
                          const Icon(
                            Symbols.check_circle,
                            color: Colors.white,
                            fill: 1,
                            size: 20,
                          ),
                      ],
                    ),
                    const Spacer(),
                    Text(
                      preset.subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.85),
                        fontSize: 12.5,
                        height: 1.25,
                        shadows: const [
                          Shadow(color: Colors.black38, blurRadius: 6),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class GlassPreview extends StatelessWidget {
  const GlassPreview({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppShape.card),
      child: SizedBox(
        height: 230,
        child: Stack(
          fit: StackFit.expand,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    cs.primary.withValues(alpha: 0.9),
                    cs.tertiary.withValues(alpha: 0.7),
                    cs.surface,
                  ],
                ),
              ),
            ),
            Positioned(
              left: -30,
              bottom: -40,
              child: Container(
                width: 160,
                height: 160,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: cs.secondary.withValues(alpha: 0.55),
                ),
              ),
            ),
            ListenableBuilder(
              listenable: ProMaxAtmosphere.listenable,
              builder: (context, _) {
                final effect = ProMaxAtmosphere.effect.value;
                if (effect == AtmosphereEffect.none) {
                  return const SizedBox.shrink();
                }
                return AtmosphereLayer(
                  key: ValueKey(effect),
                  style: AtmosphereStyle.fromSettings(effect),
                );
              },
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
              child: Column(
                children: [
                  _PreviewBubble(
                    text: 'Как тебе новое стекло?',
                    incoming: true,
                    color: cs.surfaceContainerHigh,
                    textColor: cs.onSurface,
                  ),
                  const SizedBox(height: 8),
                  _PreviewBubble(
                    text: 'Выглядит как iOS 26 🔥',
                    incoming: false,
                    color: cs.primary,
                    textColor: cs.onPrimary,
                  ),
                  const Spacer(),
                  SizedBox(
                    height: 50,
                    child: GlassSurface(
                      liquid: true,
                      borderRadius: BorderRadius.circular(25),
                      frostTint: cs.surface.withValues(alpha: 0.35),
                      liquidTint: cs.surface.withValues(alpha: 0.12),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Row(
                          children: [
                            Icon(Symbols.add, color: cs.onSurface),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                'Сообщение',
                                style: TextStyle(
                                  color: cs.onSurfaceVariant,
                                  fontSize: 15,
                                ),
                              ),
                            ),
                            Icon(Symbols.mic, color: cs.onSurface),
                          ],
                        ),
                      ),
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

class _PreviewBubble extends StatelessWidget {
  const _PreviewBubble({
    required this.text,
    required this.incoming,
    required this.color,
    required this.textColor,
  });

  final String text;
  final bool incoming;
  final Color color;
  final Color textColor;

  @override
  Widget build(BuildContext context) => Align(
    alignment: incoming ? Alignment.centerLeft : Alignment.centerRight,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(18),
          topRight: const Radius.circular(18),
          bottomLeft: Radius.circular(incoming ? 6 : 18),
          bottomRight: Radius.circular(incoming ? 18 : 6),
        ),
      ),
      child: Text(text, style: TextStyle(color: textColor, fontSize: 15)),
    ),
  );
}
