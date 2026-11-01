import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:promax/core/storage/quick_replies_store.dart';
import 'package:promax/frontend/screens/chats/chat/quick_reply_panel_controller.dart';

class QuickReplyPanelView extends StatelessWidget {
  const QuickReplyPanelView({super.key, required this.quickReplyPanel});

  final QuickReplyPanelController quickReplyPanel;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: quickReplyPanel.anim,
      child: ValueListenableBuilder<List<QuickReply>>(
        valueListenable: quickReplyPanel.matches,
        builder: (context, matches, _) => QuickReplySuggestionsPanel(
          replies: matches,
          onSelected: quickReplyPanel.select,
        ),
      ),
      builder: (context, child) {
        final t = quickReplyPanel.anim.value;
        if (t == 0) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
          child: IgnorePointer(
            ignoring: t < 1,
            child: Opacity(opacity: t, child: child),
          ),
        );
      },
    );
  }
}

class QuickReplySuggestionsPanel extends StatelessWidget {
  const QuickReplySuggestionsPanel({
    super.key,
    required this.replies,
    required this.onSelected,
    this.maxHeight = 220,
  });

  final List<QuickReply> replies;
  final ValueChanged<QuickReply> onSelected;
  final double maxHeight;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      type: MaterialType.transparency,
      child: Container(
        constraints: BoxConstraints(maxHeight: maxHeight),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.3)),
        ),
        clipBehavior: Clip.antiAlias,
        child: ListView.separated(
          shrinkWrap: true,
          padding: const EdgeInsets.symmetric(vertical: 6),
          itemCount: replies.length,
          separatorBuilder: (_, _) => Divider(
            height: 1,
            thickness: 1,
            indent: 14,
            endIndent: 14,
            color: cs.outlineVariant.withValues(alpha: 0.18),
          ),
          itemBuilder: (context, i) {
            final reply = replies[i];
            return _QuickReplyRow(
              key: ValueKey(reply.id),
              reply: reply,
              onTap: () => onSelected(reply),
            );
          },
        ),
      ),
    );
  }
}

class _QuickReplyRow extends StatelessWidget {
  const _QuickReplyRow({super.key, required this.reply, required this.onTap});

  final QuickReply reply;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final hasTitle = reply.title.isNotEmpty;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 1),
              child: Icon(Symbols.quickreply, size: 20, color: cs.primary),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (hasTitle)
                    Text(
                      reply.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: cs.onSurface,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  Text(
                    reply.text,
                    maxLines: hasTitle ? 1 : 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: hasTitle ? cs.onSurfaceVariant : cs.onSurface,
                      fontSize: hasTitle ? 13.5 : 15,
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
