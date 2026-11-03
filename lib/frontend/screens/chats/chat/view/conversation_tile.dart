import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

class ConversationTile extends StatelessWidget {
  const ConversationTile({
    super.key,
    required this.avatar,
    required this.title,
    required this.preview,
    required this.time,
    this.muted = false,
    this.pinned = false,
    this.verified = false,
    this.selected = false,
    this.titleIcon,
    this.titleBadge,
    this.indicator,
    this.action,
  });

  final Widget avatar;
  final String title;
  final Widget preview;
  final String time;
  final bool muted;
  final bool pinned;
  final bool verified;
  final bool selected;
  final IconData? titleIcon;
  final Widget? titleBadge;
  final Widget? indicator;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: selected ? cs.primary.withValues(alpha: 0.10) : null,
          borderRadius: BorderRadius.circular(18),
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 84),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
            child: Row(
              children: [
                SizedBox(width: 56, child: Center(child: avatar)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          if (titleIcon != null) ...[
                            Icon(
                              titleIcon,
                              size: 16,
                              color: cs.onSurfaceVariant,
                            ),
                            const SizedBox(width: 4),
                          ],
                          Expanded(
                            child: Text(
                              title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: cs.onSurface,
                                fontSize: 17,
                                fontWeight: FontWeight.w600,
                                height: 1.2,
                              ),
                            ),
                          ),
                          if (verified) ...[
                            const SizedBox(width: 4),
                            Icon(
                              Symbols.verified,
                              size: 16,
                              color: cs.primary,
                              fill: 1,
                            ),
                          ],
                          ?titleBadge,
                          const SizedBox(width: 8),
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 88),
                            child: Text(
                              time,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: cs.onSurfaceVariant,
                                fontSize: 12,
                                height: 1.2,
                                fontFeatures: const [
                                  FontFeature.tabularFigures(),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Expanded(
                            child: DefaultTextStyle(
                              style: TextStyle(
                                color: cs.onSurfaceVariant,
                                fontSize: 14,
                                height: 1.3,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              child: preview,
                            ),
                          ),
                          if (muted) ...[
                            const SizedBox(width: 6),
                            Icon(
                              Symbols.notifications_off,
                              size: 14,
                              color: cs.outline,
                            ),
                          ],
                          if (pinned) ...[
                            const SizedBox(width: 6),
                            Icon(Symbols.keep, size: 14, color: cs.outline),
                          ],
                          if (indicator != null) ...[
                            const SizedBox(width: 8),
                            indicator!,
                          ],
                          if (action != null) ...[
                            const SizedBox(width: 4),
                            action!,
                          ],
                        ],
                      ),
                    ],
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
