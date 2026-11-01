import 'dart:async';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../core/storage/quick_replies_store.dart';
import '../../widgets/custom_notification.dart';
import 'chat/quick_reply_panel_controller.dart';

typedef QuickReplyDraft = ({String title, String text});

Future<QuickReplyDraft?> editQuickReply(
  BuildContext context, {
  QuickReply? initial,
}) => showDialog<QuickReplyDraft>(
  context: context,
  builder: (_) => _QuickReplyEditor(initial: initial),
);

class _QuickReplyEditor extends StatefulWidget {
  const _QuickReplyEditor({this.initial});

  final QuickReply? initial;

  @override
  State<_QuickReplyEditor> createState() => _QuickReplyEditorState();
}

class _QuickReplyEditorState extends State<_QuickReplyEditor> {
  late final TextEditingController _title = TextEditingController(
    text: widget.initial?.title,
  );
  late final TextEditingController _text = TextEditingController(
    text: widget.initial?.text,
  );

  @override
  void dispose() {
    _title.dispose();
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.initial == null ? 'Новый шаблон' : 'Шаблон'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _title,
              maxLength: QuickRepliesStore.maxTitleLength,
              textCapitalization: TextCapitalization.sentences,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: 'Название (необязательно)',
                hintText: 'Например: «Перезвоню»',
                counterText: '',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _text,
              autofocus: widget.initial == null,
              minLines: 2,
              maxLines: 6,
              maxLength: QuickRepliesStore.maxLength,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Текст',
                hintText: 'Сейчас не могу, перезвоню',
                counterText: '',
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Отмена'),
        ),
        FilledButton(
          onPressed: () =>
              Navigator.pop(context, (title: _title.text, text: _text.text)),
          child: const Text('Сохранить'),
        ),
      ],
    );
  }
}

void _reportSaveResult(BuildContext context, QuickReplySaveResult result) {
  if (!context.mounted) return;
  switch (result) {
    case QuickReplySaveResult.saved:
      return;
    case QuickReplySaveResult.empty:
      showCustomNotification(context, 'Шаблон без текста не сохранён');
    case QuickReplySaveResult.limitReached:
      showCustomNotification(
        context,
        'Можно хранить до ${QuickRepliesStore.maxCount} шаблонов',
      );
  }
}

Future<void> addQuickReply(BuildContext context, int accountId) async {
  final draft = await editQuickReply(context);
  if (draft == null || !context.mounted) return;
  final result = await QuickRepliesStore.instance.add(
    accountId,
    title: draft.title,
    text: draft.text,
  );
  if (context.mounted) _reportSaveResult(context, result);
}

Future<void> changeQuickReply(
  BuildContext context,
  int accountId,
  QuickReply reply,
) async {
  final draft = await editQuickReply(context, initial: reply);
  if (draft == null || !context.mounted) return;
  final result = await QuickRepliesStore.instance.update(
    accountId,
    reply.id,
    title: draft.title,
    text: draft.text,
  );
  if (context.mounted) _reportSaveResult(context, result);
}

Future<QuickReply?> pickQuickReply(
  BuildContext context, {
  required int accountId,
}) {
  final store = QuickRepliesStore.instance;
  unawaited(store.ensureLoaded(accountId));
  return showModalBottomSheet<QuickReply>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheetContext) {
      final cs = Theme.of(sheetContext).colorScheme;
      return SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.7,
          ),
          child: ListenableBuilder(
            listenable: store,
            builder: (context, _) {
              final items = store.repliesFor(accountId);
              return ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.only(bottom: 12),
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 0, 24, 4),
                    child: Text(
                      'Шаблоны ответов',
                      style: TextStyle(
                        color: cs.onSurface,
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
                    child: Text(
                      items.isEmpty
                          ? 'Сохрани фразы, которые часто пишешь, и вставляй их в одно касание'
                          : 'Нажми, чтобы вставить. Удержи, чтобы изменить. '
                                'В поле ввода шаблоны находятся по «$quickReplyTrigger»',
                      style: TextStyle(
                        color: cs.onSurfaceVariant,
                        fontSize: 13.5,
                      ),
                    ),
                  ),
                  for (final reply in items)
                    QuickReplyTile(
                      key: ValueKey(reply.id),
                      reply: reply,
                      onTap: () => Navigator.pop(sheetContext, reply),
                      onLongPress: () =>
                          changeQuickReply(sheetContext, accountId, reply),
                    ),
                  ListTile(
                    leading: Icon(Symbols.add, color: cs.primary),
                    title: Text(
                      'Новый шаблон',
                      style: TextStyle(color: cs.primary),
                    ),
                    onTap: () => addQuickReply(sheetContext, accountId),
                  ),
                ],
              );
            },
          ),
        ),
      );
    },
  );
}

class QuickReplyTile extends StatelessWidget {
  const QuickReplyTile({
    super.key,
    required this.reply,
    this.onTap,
    this.onLongPress,
    this.trailing,
  });

  final QuickReply reply;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final hasTitle = reply.title.isNotEmpty;
    return ListTile(
      leading: const Icon(Symbols.quickreply),
      title: Text(
        hasTitle ? reply.title : reply.text,
        maxLines: hasTitle ? 1 : 3,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: hasTitle
          ? Text(reply.text, maxLines: 2, overflow: TextOverflow.ellipsis)
          : null,
      trailing: trailing,
      onTap: onTap,
      onLongPress: onLongPress,
    );
  }
}
