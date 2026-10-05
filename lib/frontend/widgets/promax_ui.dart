import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../core/config/promax_glass.dart';

class ProMaxSectionTitle extends StatelessWidget {
  const ProMaxSectionTitle(this.text, {super.key, this.trailing});

  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 22, 8, 10),
      child: Row(
        children: [
          Expanded(
            child: Text(
              text.toUpperCase(),
              style: TextStyle(
                color: cs.onSurfaceVariant,
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.9,
              ),
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

class ProMaxSliderTile extends StatelessWidget {
  const ProMaxSliderTile({
    super.key,
    required this.icon,
    required this.label,
    required this.parameter,
    required this.format,
    this.divisions,
  });

  final IconData icon;
  final String label;
  final GlassParameter parameter;
  final String Function(double value) format;
  final int? divisions;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ValueListenableBuilder<double>(
      valueListenable: parameter.current,
      builder: (context, value, _) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 12, 4),
        child: Column(
          children: [
            Row(
              children: [
                Icon(icon, color: cs.onSurfaceVariant, size: 22),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      color: cs.onSurface,
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                Text(
                  format(value),
                  style: TextStyle(
                    color: cs.primary,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                const SizedBox(width: 8),
              ],
            ),
            Slider(
              value: value.clamp(parameter.min, parameter.max).toDouble(),
              min: parameter.min,
              max: parameter.max,
              divisions: divisions,
              onChanged: (next) => parameter.current.value = next,
              onChangeEnd: parameter.save,
            ),
          ],
        ),
      ),
    );
  }
}

class ProMaxColorSwatches extends StatelessWidget {
  const ProMaxColorSwatches({
    super.key,
    required this.colors,
    required this.selected,
    required this.onSelected,
    this.autoLabel,
  });

  final List<Color> colors;
  final int selected;
  final ValueChanged<int> onSelected;
  final String? autoLabel;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        if (autoLabel != null)
          _Swatch(
            selected: selected == 0,
            onTap: () => onSelected(0),
            child: Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: SweepGradient(
                  colors: [cs.primary, cs.tertiary, cs.secondary, cs.primary],
                ),
              ),
              child: Icon(Symbols.auto_awesome, size: 18, color: cs.onPrimary),
            ),
          ),
        for (final color in colors)
          _Swatch(
            selected: selected == color.toARGB32(),
            onTap: () => onSelected(color.toARGB32()),
            child: DecoratedBox(
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
          ),
      ],
    );
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch({
    required this.selected,
    required this.onTap,
    required this.child,
  });

  final bool selected;
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: 40,
        height: 40,
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: selected ? cs.primary : Colors.transparent,
            width: 2.5,
          ),
        ),
        child: ClipOval(child: child),
      ),
    );
  }
}

class ProMaxChoiceChip extends StatelessWidget {
  const ProMaxChoiceChip({
    super.key,
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: selected
              ? cs.primary
              : cs.surfaceContainerHighest.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: selected
                ? cs.primary
                : cs.outlineVariant.withValues(alpha: 0.4),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 18,
              color: selected ? cs.onPrimary : cs.onSurfaceVariant,
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                color: selected ? cs.onPrimary : cs.onSurface,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
