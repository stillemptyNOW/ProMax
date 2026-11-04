import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import '../../../core/config/app_performance.dart';
import '../../../core/utils/haptics.dart';
import '../../../l10n/app_localizations.dart';
import '../../widgets/promax_ui.dart';
import '../../widgets/settings_card.dart';

class PerformanceModeCard extends StatelessWidget {
  const PerformanceModeCard({super.key});

  static IconData iconOf(PerformanceMode mode) => switch (mode) {
    PerformanceMode.auto => Symbols.auto_mode,
    PerformanceMode.smooth => Symbols.speed,
    PerformanceMode.beauty => Symbols.auto_awesome,
  };

  static String labelOf(AppLocalizations l10n, PerformanceMode mode) =>
      switch (mode) {
        PerformanceMode.auto => l10n.performanceModeAuto,
        PerformanceMode.smooth => l10n.performanceModeSmooth,
        PerformanceMode.beauty => l10n.performanceModeBeauty,
      };

  static String hintOf(
    AppLocalizations l10n,
    PerformanceMode mode,
    DeviceTier tier,
  ) => switch (mode) {
    PerformanceMode.auto => l10n.performanceModeAutoHint(switch (tier) {
      DeviceTier.low => l10n.performanceTierLow,
      DeviceTier.mid => l10n.performanceTierMid,
      DeviceTier.high => l10n.performanceTierHigh,
    }),
    PerformanceMode.smooth => l10n.performanceModeSmoothHint,
    PerformanceMode.beauty => l10n.performanceModeBeautyHint,
  };

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ProMaxSectionTitle(l10n.performanceModeTitle),
        SettingsPanel(
          child: ListenableBuilder(
            listenable: Listenable.merge([
              AppPerformance.mode,
              AppPerformance.tier,
              AppPerformance.budget,
            ]),
            builder: (context, _) {
              final current = AppPerformance.mode.value;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.performanceModeSubtitle,
                    style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final mode in PerformanceMode.values)
                        ProMaxChoiceChip(
                          key: ValueKey(mode),
                          icon: iconOf(mode),
                          label: labelOf(l10n, mode),
                          selected: mode == current,
                          onTap: () {
                            Haptics.selection();
                            AppPerformance.save(mode);
                          },
                        ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    hintOf(l10n, current, AppPerformance.effectiveTier),
                    style: TextStyle(
                      color: cs.onSurfaceVariant,
                      fontSize: 12.5,
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}
