import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../core/config/app_native_glass.dart';
import '../../../core/plugins/motion_blur/motion_blur_plugin.dart';
import '../../../core/plugins/motion_blur/motion_blur_settings.dart';
import '../../../core/utils/haptics.dart';
import '../../../l10n/app_localizations.dart';
import '../../widgets/motion_blur/motion_blur_box.dart';
import '../../widgets/motion_blur/motion_blur_scroll_behavior.dart';
import '../../widgets/promax_ui.dart';
import '../../widgets/settings_card.dart';

class MotionBlurSettingsScreen extends StatefulWidget {
  const MotionBlurSettingsScreen({super.key});

  @override
  State<MotionBlurSettingsScreen> createState() =>
      _MotionBlurSettingsScreenState();
}

class _MotionBlurSettingsScreenState extends State<MotionBlurSettingsScreen> {
  MotionBlurPlugin get _plugin => MotionBlurPlugin.instance;

  @override
  void initState() {
    super.initState();
    _plugin.ensureShader().then((_) {
      if (mounted) setState(() {});
    });
  }

  Future<void> _save(MotionBlurSettings next) => _plugin.update(next);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        title: Text(l10n.motionBlurTitle),
        backgroundColor: cs.surface,
      ),
      body: ListenableBuilder(
        listenable: Listenable.merge([_plugin.settings, _plugin.lowEnd]),
        builder: (context, _) {
          final settings = _plugin.settings.value;
          return ListView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 120),
            children: [
              SettingsCard(
                children: [
                  SettingsToggleTile(
                    icon: Symbols.motion_blur,
                    label: l10n.motionBlurEnabled,
                    subtitle: l10n.motionBlurEnabledSubtitle,
                    value: settings.enabled,
                    onChanged: (value) =>
                        _save(settings.copyWith(enabled: value)),
                  ),
                ],
              ),
              if (reduceMotion)
                _Notice(
                  icon: Symbols.motion_photos_off,
                  text: l10n.motionBlurReduceMotionNotice,
                ),
              if (_plugin.lowEnd.value)
                _Notice(icon: Symbols.speed, text: l10n.motionBlurLowEndNotice),
              if (_plugin.program == null)
                _Notice(
                  icon: Symbols.blur_on,
                  text: l10n.motionBlurFallbackNotice,
                ),
              ProMaxSectionTitle(l10n.motionBlurSectionPreview),
              const MotionBlurPreview(),
              ProMaxSectionTitle(l10n.motionBlurSectionTuning),
              SettingsPanel(
                padding: const EdgeInsets.fromLTRB(4, 8, 4, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _MotionBlurSlider(
                      icon: Symbols.line_weight,
                      label: l10n.motionBlurStrength,
                      hint: l10n.motionBlurStrengthHint,
                      value: settings.strength,
                      min: MotionBlurSettings.minStrength,
                      max: MotionBlurSettings.maxStrength,
                      divisions: 36,
                      format: (value) =>
                          l10n.motionBlurStrengthValue(value.round()),
                      onChanged: (value) =>
                          _plugin.preview(settings.copyWith(strength: value)),
                      onChangeEnd: (value) =>
                          _save(settings.copyWith(strength: value)),
                    ),
                    _MotionBlurSlider(
                      icon: Symbols.speed,
                      label: l10n.motionBlurSensitivity,
                      hint: l10n.motionBlurSensitivityHint,
                      value: settings.sensitivity,
                      min: MotionBlurSettings.minSensitivity,
                      max: MotionBlurSettings.maxSensitivity,
                      divisions: 11,
                      format: (value) => l10n.motionBlurSensitivityValue(
                        value.toStringAsFixed(2),
                      ),
                      onChanged: (value) => _plugin.preview(
                        settings.copyWith(sensitivity: value),
                      ),
                      onChangeEnd: (value) =>
                          _save(settings.copyWith(sensitivity: value)),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                      child: _SliderHeader(
                        icon: Symbols.high_quality,
                        label: l10n.motionBlurQuality,
                        hint: l10n.motionBlurQualityHint,
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                      child: SizedBox(
                        width: double.infinity,
                        child: SegmentedButton<MotionBlurQuality>(
                          showSelectedIcon: false,
                          segments: [
                            ButtonSegment(
                              value: MotionBlurQuality.low,
                              label: Text(l10n.motionBlurQualityLow),
                            ),
                            ButtonSegment(
                              value: MotionBlurQuality.balanced,
                              label: Text(l10n.motionBlurQualityBalanced),
                            ),
                            ButtonSegment(
                              value: MotionBlurQuality.high,
                              label: Text(l10n.motionBlurQualityHigh),
                            ),
                          ],
                          selected: {settings.quality},
                          onSelectionChanged: (selection) {
                            Haptics.selection();
                            _save(settings.copyWith(quality: selection.first));
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              ProMaxSectionTitle(l10n.motionBlurSectionTargets),
              SettingsCard(
                children: [
                  for (final target in MotionBlurTarget.values)
                    SettingsToggleTile(
                      icon: _targetIcon(target),
                      label: _targetLabel(l10n, target),
                      subtitle: _targetSubtitle(l10n, target),
                      value: settings.targets.contains(target),
                      onChanged: (value) =>
                          _save(settings.withTarget(target, value)),
                    ),
                ],
              ),
              if (NativeGlass.isSupported)
                _Notice(
                  icon: Symbols.info,
                  text: l10n.motionBlurPlatformViewsNote,
                ),
              const SizedBox(height: 12),
              Center(
                child: TextButton.icon(
                  icon: const Icon(Symbols.restart_alt),
                  label: Text(l10n.motionBlurReset),
                  onPressed: () =>
                      _save(MotionBlurSettings(enabled: settings.enabled)),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  static IconData _targetIcon(MotionBlurTarget target) => switch (target) {
    MotionBlurTarget.scrolling => Symbols.swap_vert,
    MotionBlurTarget.transitions => Symbols.open_in_new,
    MotionBlurTarget.pages => Symbols.swipe,
    MotionBlurTarget.lens => Symbols.toggle_on,
  };

  static String _targetLabel(AppLocalizations l10n, MotionBlurTarget target) =>
      switch (target) {
        MotionBlurTarget.scrolling => l10n.motionBlurTargetScrolling,
        MotionBlurTarget.transitions => l10n.motionBlurTargetTransitions,
        MotionBlurTarget.pages => l10n.motionBlurTargetPages,
        MotionBlurTarget.lens => l10n.motionBlurTargetLens,
      };

  static String _targetSubtitle(
    AppLocalizations l10n,
    MotionBlurTarget target,
  ) => switch (target) {
    MotionBlurTarget.scrolling => l10n.motionBlurTargetScrollingSubtitle,
    MotionBlurTarget.transitions => l10n.motionBlurTargetTransitionsSubtitle,
    MotionBlurTarget.pages => l10n.motionBlurTargetPagesSubtitle,
    MotionBlurTarget.lens => l10n.motionBlurTargetLensSubtitle,
  };
}

class MotionBlurPreview extends StatefulWidget {
  const MotionBlurPreview({super.key});

  @override
  State<MotionBlurPreview> createState() => _MotionBlurPreviewState();
}

class _MotionBlurPreviewState extends State<MotionBlurPreview>
    with SingleTickerProviderStateMixin {
  static const int _rowCount = 60;
  static const double _listHeight = 220;
  static const double _stageHeight = 132;

  late final AnimationController _transition = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
  );
  late final CurvedAnimation _curve = CurvedAnimation(
    parent: _transition,
    curve: Curves.easeOutCubic,
    reverseCurve: Curves.easeInCubic,
  );

  @override
  void dispose() {
    _curve.dispose();
    _transition.dispose();
    super.dispose();
  }

  void _play() {
    Haptics.tap();
    if (_transition.value > 0.5) {
      _transition.reverse();
    } else {
      _transition.forward();
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    return SettingsPanel(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l10n.motionBlurPreviewHint,
            style: TextStyle(
              color: cs.onSurfaceVariant,
              fontSize: 13,
              height: 1.3,
            ),
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: ColoredBox(
              color: cs.surfaceContainerLow,
              child: SizedBox(
                height: _listHeight,
                child: ScrollConfiguration(
                  behavior: const MotionBlurScrollBehavior(
                    MaterialScrollBehavior(),
                    preview: true,
                  ),
                  child: ListView.builder(
                    physics: const BouncingScrollPhysics(),
                    itemCount: _rowCount,
                    itemBuilder: (context, index) => _PreviewRow(
                      key: ValueKey(index),
                      index: index,
                      label: l10n.motionBlurPreviewRow(index + 1),
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: ColoredBox(
              color: cs.surfaceContainerLow,
              child: SizedBox(
                height: _stageHeight,
                child: LayoutBuilder(
                  builder: (context, constraints) => AnimatedBuilder(
                    animation: _curve,
                    child: MotionBlurBox(
                      target: MotionBlurTarget.transitions,
                      motion: [_transition],
                      preview: true,
                      child: _PreviewScreen(title: l10n.motionBlurPreviewCard),
                    ),
                    builder: (context, child) => Transform.translate(
                      offset: Offset(
                        (1 - _curve.value) * constraints.maxWidth * 0.62 -
                            constraints.maxWidth * 0.31,
                        0,
                      ),
                      child: child,
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.tonalIcon(
            onPressed: _play,
            icon: const Icon(Symbols.play_arrow),
            label: Text(l10n.motionBlurPreviewPlay),
          ),
        ],
      ),
    );
  }
}

class _PreviewRow extends StatelessWidget {
  const _PreviewRow({super.key, required this.index, required this.label});

  final int index;
  final String label;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final accent = HSLColor.fromAHSL(1, (index * 37) % 360, 0.55, 0.55);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      child: Row(
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: accent.toColor(),
            child: Text(
              '${index + 1}',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: cs.onSurface,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                FractionallySizedBox(
                  widthFactor: 0.4 + (index % 5) * 0.12,
                  child: Container(
                    height: 8,
                    decoration: BoxDecoration(
                      color: cs.onSurfaceVariant.withValues(alpha: 0.25),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PreviewScreen extends StatelessWidget {
  const _PreviewScreen({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Container(
        width: 180,
        height: 108,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: cs.primaryContainer,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Symbols.motion_blur, color: cs.onPrimaryContainer),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: TextStyle(
                    color: cs.onPrimaryContainer,
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
            const Spacer(),
            for (final width in const [0.9, 0.7, 0.5])
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: FractionallySizedBox(
                  widthFactor: width,
                  child: Container(
                    height: 7,
                    decoration: BoxDecoration(
                      color: cs.onPrimaryContainer.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _MotionBlurSlider extends StatelessWidget {
  const _MotionBlurSlider({
    required this.icon,
    required this.label,
    required this.hint,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.format,
    required this.onChanged,
    required this.onChangeEnd,
  });

  final IconData icon;
  final String label;
  final String hint;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final String Function(double value) format;
  final ValueChanged<double> onChanged;
  final ValueChanged<double> onChangeEnd;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 0),
      child: Column(
        children: [
          _SliderHeader(
            icon: icon,
            label: label,
            hint: hint,
            trailing: Text(
              format(value),
              style: TextStyle(
                color: cs.primary,
                fontSize: 14,
                fontWeight: FontWeight.w600,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
          Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            divisions: divisions,
            onChanged: onChanged,
            onChangeEnd: onChangeEnd,
          ),
        ],
      ),
    );
  }
}

class _SliderHeader extends StatelessWidget {
  const _SliderHeader({
    required this.icon,
    required this.label,
    required this.hint,
    this.trailing,
  });

  final IconData icon;
  final String label;
  final String hint;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: cs.onSurfaceVariant, size: 22),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  color: cs.onSurface,
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                hint,
                style: TextStyle(
                  color: cs.onSurfaceVariant,
                  fontSize: 13,
                  height: 1.3,
                ),
              ),
            ],
          ),
        ),
        if (trailing != null) ...[const SizedBox(width: 8), trailing!],
      ],
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 12, 8, 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: cs.onSurfaceVariant),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: cs.onSurfaceVariant,
                fontSize: 13,
                height: 1.3,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
