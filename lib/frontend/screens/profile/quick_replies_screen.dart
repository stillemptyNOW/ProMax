import 'dart:async';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../core/storage/quick_replies_store.dart';
import '../../widgets/connection_status.dart';
import '../chats/chat/quick_reply_panel_controller.dart';
import '../chats/quick_replies_sheet.dart';

class QuickRepliesScreen extends StatefulWidget {
  const QuickRepliesScreen({super.key, required this.accountId});

  final int accountId;

  @override
  State<QuickRepliesScreen> createState() => _QuickRepliesScreenState();
}

class _QuickRepliesScreenState extends State<QuickRepliesScreen> {
  final QuickRepliesStore _store = QuickRepliesStore.instance;

  @override
  void initState() {
    super.initState();
    unawaited(_store.ensureLoaded(widget.accountId));
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: cs.surface,
      appBar: ConnectionTitleBar(
        titleText: 'Шаблоны ответов',
        backgroundColor: cs.surface,
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => addQuickReply(context, widget.accountId),
        icon: const Icon(Symbols.add),
        label: const Text('Шаблон'),
      ),
      body: SafeArea(
        top: false,
        child: ListenableBuilder(
          listenable: _store,
          builder: (context, _) {
            final items = _store.repliesFor(widget.accountId);
            if (items.isEmpty) return const _EmptyQuickReplies();
            return ReorderableListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
              itemCount: items.length,
              footer: const _TriggerHint(),
              onReorderItem: (from, to) =>
                  _store.move(widget.accountId, from, to),
              itemBuilder: (context, index) {
                final reply = items[index];
                return Padding(
                  key: ValueKey(reply.id),
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Dismissible(
                    key: ValueKey('dismiss-${reply.id}'),
                    direction: DismissDirection.endToStart,
                    background: Container(
                      alignment: Alignment.centerRight,
                      padding: const EdgeInsets.only(right: 20),
                      decoration: BoxDecoration(
                        color: cs.error,
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Icon(Symbols.delete, color: cs.onError),
                    ),
                    onDismissed: (_) =>
                        _store.remove(widget.accountId, reply.id),
                    child: Material(
                      color: cs.surfaceContainerHigh,
                      borderRadius: BorderRadius.circular(18),
                      clipBehavior: Clip.antiAlias,
                      child: QuickReplyTile(
                        reply: reply,
                        trailing: ReorderableDragStartListener(
                          index: index,
                          child: const Icon(Symbols.drag_indicator),
                        ),
                        onTap: () =>
                            changeQuickReply(context, widget.accountId, reply),
                      ),
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}

class _EmptyQuickReplies extends StatelessWidget {
  const _EmptyQuickReplies();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Symbols.quickreply, size: 56, color: cs.onSurfaceVariant),
            const SizedBox(height: 12),
            Text(
              'Шаблонов пока нет',
              style: TextStyle(
                color: cs.onSurface,
                fontSize: 17,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Начни слово с «$quickReplyTrigger» в поле ввода, чтобы найти '
              'шаблон по названию или тексту, или открой его из меню ProMax в чате',
              textAlign: TextAlign.center,
              style: TextStyle(color: cs.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

class _TriggerHint extends StatelessWidget {
  const _TriggerHint();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 0),
      child: Text(
        'В поле ввода напиши «$quickReplyTrigger» и начало названия, например '
        '«$quickReplyTriggerперезвоню», и выбери шаблон из списка: он '
        'вставится туда, где стоит курсор. Шаблоны свои у каждого аккаунта. '
        'Смахни влево, чтобы удалить, потяни за ручку, чтобы переставить.',
        style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
      ),
    );
  }
}
