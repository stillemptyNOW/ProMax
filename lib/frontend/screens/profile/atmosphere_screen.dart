import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../core/config/app_shape.dart';
import '../../../core/config/promax_atmosphere.dart';
import '../../widgets/atmosphere_overlay.dart';
import '../../widgets/connection_status.dart';
import '../../widgets/promax_ui.dart';
import '../../widgets/settings_card.dart';

IconData atmosphereIcon(AtmosphereEffect effect) => switch (effect) {
  AtmosphereEffect.none => Symbols.block,
  AtmosphereEffect.snow => Symbols.ac_unit,
  AtmosphereEffect.rain => Symbols.rainy,
  AtmosphereEffect.stars => Symbols.star,
  AtmosphereEffect.leaves => Symbols.eco,
  AtmosphereEffect.sakura => Symbols.local_florist,
  AtmosphereEffect.hearts => Symbols.favorite,
  AtmosphereEffect.confetti => Symbols.celebration,
  AtmosphereEffect.sparkles => Symbols.auto_awesome,
  AtmosphereEffect.bubbles => Symbols.bubble_chart,
  AtmosphereEffect.fireflies => Symbols.emoji_objects,
};

class AtmosphereScreen extends StatelessWidget {
  const AtmosphereScreen({super.key});

  static const List<Color> palette = [
    Color(0xFFFFFFFF),
    Color(0xFFBFD7FF),
    Color(0xFF8EC5FF),
    Color(0xFF7B5CFF),
    Color(0xFFFF8FB8),
    Color(0xFFFF4D6D),
    Color(0xFFFFC23D),
    Color(0xFF7EE081),
    Color(0xFF22D3EE),
    Color(0xFFE6FF7A),
  ];

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: cs.surface,
      appBar: ConnectionTitleBar(
        titleText: 'Атмосфера',
        backgroundColor: cs.surface,
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
          children: [
            const _AtmospherePreview(),
            const ProMaxSectionTitle('Эффект'),
            SettingsPanel(
              child: ValueListenableBuilder<AtmosphereEffect>(
                valueListenable: ProMaxAtmosphere.effect,
                builder: (context, current, _) => Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final effect in AtmosphereEffect.values)
                      ProMaxChoiceChip(
                        icon: atmosphereIcon(effect),
                        label: effect.title,
                        selected: effect == current,
                        onTap: () => ProMaxAtmosphere.setEffect(effect),
                      ),
                  ],
                ),
              ),
            ),
            const ProMaxSectionTitle('Где показывать'),
            SettingsPanel(
              child: ValueListenableBuilder<AtmosphereScope>(
                valueListenable: ProMaxAtmosphere.scope,
                builder: (context, current, _) => Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final scope in AtmosphereScope.values)
                      ProMaxChoiceChip(
                        icon: scope == AtmosphereScope.everywhere
                            ? Symbols.fullscreen
                            : Symbols.chat,
                        label: scope.title,
                        selected: scope == current,
                        onTap: () => ProMaxAtmosphere.setScope(scope),
                      ),
                  ],
                ),
              ),
            ),
            ProMaxSectionTitle(
              'Настройка',
              trailing: TextButton(
                onPressed: ProMaxAtmosphere.resetTuning,
                child: const Text('Сбросить'),
              ),
            ),
            SettingsCard(
              children: [
                ProMaxSliderTile(
                  icon: Symbols.grain,
                  label: 'Плотность',
                  parameter: ProMaxAtmosphere.density,
                  format: (v) => '${(v * 100).round()}%',
                ),
                ProMaxSliderTile(
                  icon: Symbols.speed,
                  label: 'Скорость',
                  parameter: ProMaxAtmosphere.speed,
                  format: (v) => '${v.toStringAsFixed(1)}×',
                ),
                ProMaxSliderTile(
                  icon: Symbols.photo_size_select_small,
                  label: 'Размер',
                  parameter: ProMaxAtmosphere.size,
                  format: (v) => '${v.toStringAsFixed(1)}×',
                ),
                ProMaxSliderTile(
                  icon: Symbols.opacity,
                  label: 'Прозрачность',
                  parameter: ProMaxAtmosphere.opacity,
                  format: (v) => '${(v * 100).round()}%',
                ),
                ProMaxSliderTile(
                  icon: Symbols.air,
                  label: 'Ветер',
                  parameter: ProMaxAtmosphere.wind,
                  format: (v) => v.abs() < 0.05
                      ? 'нет'
                      : (v < 0
                            ? '← ${(v.abs() * 100).round()}%'
                            : '${(v * 100).round()}% →'),
                ),
              ],
            ),
            const ProMaxSectionTitle('Цвет частиц'),
            SettingsPanel(
              child: ValueListenableBuilder<int>(
                valueListenable: ProMaxAtmosphere.color,
                builder: (context, current, _) => ProMaxColorSwatches(
                  colors: palette,
                  selected: current,
                  autoLabel: 'Авто',
                  onSelected: ProMaxAtmosphere.setColor,
                ),
              ),
            ),
            const ProMaxSectionTitle('Реакции на слова'),
            SettingsCard(
              children: [
                ValueListenableBuilder<bool>(
                  valueListenable: ProMaxAtmosphere.triggers,
                  builder: (context, value, _) => SettingsToggleTile(
                    icon: Symbols.celebration,
                    label: 'Эффекты по ключевым словам',
                    subtitle:
                        '«С днём рождения» — конфетти, «люблю» и ❤️ — сердечки, «С Новым годом» — снег, ✨ — искры, 🌸 — сакура, 🍂 — листопад',
                    value: value,
                    onChanged: ProMaxAtmosphere.setTriggers,
                  ),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 14, 12, 0),
              child: Text(
                'Отдельный эффект для конкретного чата выбирается в меню этого чата: «Атмосфера чата».',
                style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AtmospherePreview extends StatelessWidget {
  const _AtmospherePreview();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppShape.card),
      child: SizedBox(
        height: 190,
        child: Stack(
          fit: StackFit.expand,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color.alphaBlend(
                      cs.primary.withValues(alpha: 0.35),
                      const Color(0xFF101018),
                    ),
                    const Color(0xFF05050A),
                  ],
                ),
              ),
            ),
            ListenableBuilder(
              listenable: ProMaxAtmosphere.listenable,
              builder: (context, _) {
                final effect = ProMaxAtmosphere.effect.value;
                if (effect == AtmosphereEffect.none) {
                  return Center(
                    child: Text(
                      'Выбери эффект ниже',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.6),
                        fontSize: 15,
                      ),
                    ),
                  );
                }
                return AtmosphereLayer(
                  key: ValueKey(effect),
                  style: AtmosphereStyle.fromSettings(effect),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> showChatAtmosphereSheet(BuildContext context, int chatId) =>
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      backgroundColor: Theme.of(context).colorScheme.surfaceContainerHigh,
      builder: (sheetContext) => _ChatAtmosphereSheet(chatId: chatId),
    );

class _ChatAtmosphereSheet extends StatelessWidget {
  const _ChatAtmosphereSheet({required this.chatId});

  final int chatId;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: ValueListenableBuilder<Map<int, AtmosphereEffect>>(
          valueListenable: ProMaxAtmosphere.chatEffects,
          builder: (context, effects, _) {
            final current = effects[chatId];
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Атмосфера чата',
                  style: TextStyle(
                    color: cs.onSurface,
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Эффект виден только тебе и только в этом чате',
                  style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ProMaxChoiceChip(
                      icon: Symbols.public,
                      label: 'Как везде',
                      selected: current == null,
                      onTap: () => ProMaxAtmosphere.setChatEffect(chatId, null),
                    ),
                    for (final effect in AtmosphereEffect.values)
                      ProMaxChoiceChip(
                        icon: atmosphereIcon(effect),
                        label: effect.title,
                        selected: current == effect,
                        onTap: () =>
                            ProMaxAtmosphere.setChatEffect(chatId, effect),
                      ),
                  ],
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
