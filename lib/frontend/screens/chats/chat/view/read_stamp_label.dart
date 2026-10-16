import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

class ReadStampLabel extends StatelessWidget {
  final Listenable listenable;
  final String? Function() text;

  const ReadStampLabel({
    super.key,
    required this.listenable,
    required this.text,
  });

  static const _duration = Duration(milliseconds: 260);

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: listenable,
      builder: (context, _) {
        final label = text();
        return AnimatedSwitcher(
          duration: _duration,
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          transitionBuilder: (child, animation) => SizeTransition(
            sizeFactor: animation,
            alignment: AlignmentDirectional.topCenter,
            child: FadeTransition(
              opacity: animation,
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0, -0.35),
                  end: Offset.zero,
                ).animate(animation),
                child: child,
              ),
            ),
          ),
          layoutBuilder: (current, previous) => Stack(
            alignment: AlignmentDirectional.topEnd,
            children: [...previous, ?current],
          ),
          child: label == null
              ? const SizedBox(key: ValueKey(null), width: double.infinity)
              : _ReadStampPill(key: ValueKey(label), label: label),
        );
      },
    );
  }
}

class _ReadStampPill extends StatelessWidget {
  final String label;

  const _ReadStampPill({super.key, required this.label});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(0, 1, 14, 4),
      child: Align(
        alignment: AlignmentDirectional.centerEnd,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: cs.surfaceContainerHighest.withValues(alpha: 0.85),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2.5),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Symbols.done_all, size: 13, color: cs.primary),
                const SizedBox(width: 4),
                Text(
                  label,
                  style: TextStyle(
                    color: cs.onSurfaceVariant,
                    fontSize: 11,
                    height: 1.2,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
