import 'dart:math' show max;

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:promax_effects/promax_effects.dart';

import '../../../l10n/app_localizations.dart';
import '../../widgets/hint_bubble.dart';
import '../../widgets/small_spinner.dart';

String callMaskLabel(AppLocalizations l10n, ProMaxMask mask) => switch (mask) {
  ProMaxMask.none => l10n.proMaxMaskNone,
  ProMaxMask.sunglasses => l10n.proMaxMaskSunglasses,
  ProMaxMask.goggles => l10n.proMaxMaskGoggles,
  ProMaxMask.heartEyes => l10n.proMaxMaskHeartEyes,
  ProMaxMask.crown => l10n.proMaxMaskCrown,
  ProMaxMask.topHat => l10n.proMaxMaskTopHat,
  ProMaxMask.pigNose => l10n.proMaxMaskPigNose,
  ProMaxMask.mustache => l10n.proMaxMaskMustache,
  ProMaxMask.cat => l10n.proMaxMaskCat,
  ProMaxMask.fox => l10n.proMaxMaskFox,
  ProMaxMask.panda => l10n.proMaxMaskPanda,
  ProMaxMask.alien => l10n.proMaxMaskAlien,
  ProMaxMask.robot => l10n.proMaxMaskRobot,
  ProMaxMask.pixels => l10n.proMaxMaskPixels,
};

class CallMaskSheet extends StatefulWidget {
  const CallMaskSheet({
    super.key,
    required this.initial,
    required this.onSelected,
  });

  final ProMaxMask initial;
  final Future<bool> Function(ProMaxMask mask) onSelected;

  @override
  State<CallMaskSheet> createState() => _CallMaskSheetState();
}

class _CallMaskSheetState extends State<CallMaskSheet> {
  static const _tileExtent = 84.0;

  late ProMaxMask _selected = widget.initial;
  ProMaxMask? _pending;
  late final ScrollController _scroll = ScrollController(
    initialScrollOffset: max(0, widget.initial.index * _tileExtent - 120),
  );

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _select(BuildContext tileContext, ProMaxMask mask) async {
    if (_pending != null || mask == _selected) return;
    final failure = AppLocalizations.of(context)!.proMaxEffectFailed;
    setState(() => _pending = mask);
    final applied = await widget.onSelected(mask);
    if (!mounted) return;
    setState(() {
      _pending = null;
      if (applied) _selected = mask;
    });
    if (!applied && tileContext.mounted) showHintBubble(tileContext, failure);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.only(bottom: 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              l10n.proMaxCallMasks,
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 76,
              child: ListView.builder(
                controller: _scroll,
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                itemExtent: _tileExtent,
                itemCount: ProMaxMask.values.length,
                itemBuilder: (context, index) {
                  final mask = ProMaxMask.values[index];
                  return _CallMaskTile(
                    key: ValueKey(mask),
                    mask: mask,
                    label: callMaskLabel(l10n, mask),
                    selected: mask == _selected,
                    busy: mask == _pending,
                    onTap: (tileContext) => _select(tileContext, mask),
                  );
                },
              ),
            ),
            const SizedBox(height: 12),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              child: Text(
                callMaskLabel(l10n, _pending ?? _selected),
                key: ValueKey((_pending ?? _selected).id),
                style: theme.textTheme.titleMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CallMaskTile extends StatelessWidget {
  const _CallMaskTile({
    super.key,
    required this.mask,
    required this.label,
    required this.selected,
    required this.busy,
    required this.onTap,
  });

  final ProMaxMask mask;
  final String label;
  final bool selected;
  final bool busy;
  final ValueChanged<BuildContext> onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final assetPath = mask.assetPath;
    final Widget preview = assetPath == null
        ? Icon(
            mask == ProMaxMask.pixels ? Symbols.blur_on : Symbols.block,
            size: 32,
            color: cs.onSurfaceVariant,
          )
        : Image.asset(
            assetPath,
            package: ProMaxMask.package,
            width: 50,
            height: 50,
            fit: BoxFit.contain,
            filterQuality: FilterQuality.medium,
          );
    return Center(
      child: Tooltip(
        message: label,
        child: Semantics(
          button: true,
          selected: selected,
          label: label,
          excludeSemantics: true,
          child: Builder(
            builder: (tileContext) => GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => onTap(tileContext),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                width: 72,
                height: 72,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: selected
                      ? cs.primaryContainer
                      : cs.surfaceContainerHigh,
                  border: Border.all(
                    color: selected ? cs.primary : Colors.transparent,
                    width: 3,
                  ),
                ),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    AnimatedOpacity(
                      duration: const Duration(milliseconds: 150),
                      opacity: busy ? 0.35 : 1,
                      child: preview,
                    ),
                    if (busy) const SmallSpinner(size: 28),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
