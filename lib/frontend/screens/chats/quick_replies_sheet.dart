import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../core/storage/quick_replies_store.dart';
import '../../widgets/custom_notification.dart';
import '../../widgets/with_text_controller.dart';

Future<String?> editQuickReply(BuildContext context, {String? initial}) =>
    showDialog<String>(
      context: context,
      builder: (_) => WithTextController(
        initialText: initial,
        builder: (dialogContext, controller) => AlertDialog(
          title: Text(initial == null ? 'Новый шаблон' : 'Шаблон'),
          content: TextField(
            controller: controller,
            autofocus: true,
            minLines: 2,
            maxLines: 6,
            maxLength: QuickRepliesStore.maxLength,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              hintText: 'Например: «Сейчас не могу, перезвоню»',
              counterText: '',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Отмена'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, controller.text),
              child: const Text('Сохранить'),
            ),
          ],
        ),
      ),
    );

Future<void> addQuickReply(BuildContext context) async {
  final text = await editQuickReply(context);
  if (text == null || text.trim().isEmpty || !context.mounted) return;
  final added = await QuickRepliesStore.instance.add(text);
  if (!added && context.mounted) {
    showCustomNotification(
      context,
      'Можно хранить до ${QuickRepliesStore.maxCount} шаблонов',
    );
  }
}

Future<String?> pickQuickReply(
  BuildContext context,
) => showModalBottomSheet<String>(
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
        child: ValueListenableBuilder<List<String>>(
          valueListenable: QuickRepliesStore.instance.items,
          builder: (context, items, _) => ListView(
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
                      : 'Нажми, чтобы вставить. Удержи, чтобы изменить',
                  style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13.5),
                ),
              ),
              for (final (index, text) in items.indexed)
                ListTile(
                  key: ValueKey(text),
                  leading: const Icon(Symbols.quickreply),
                  title: Text(
                    text,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  onTap: () => Navigator.pop(sheetContext, text),
                  onLongPress: () async {
                    final edited = await editQuickReply(
                      sheetContext,
                      initial: text,
                    );
                    if (edited == null) return;
                    await QuickRepliesStore.instance.update(index, edited);
                  },
                ),
              ListTile(
                leading: Icon(Symbols.add, color: cs.primary),
                title: Text(
                  'Новый шаблон',
                  style: TextStyle(color: cs.primary),
                ),
                onTap: () => addQuickReply(sheetContext),
              ),
            ],
          ),
        ),
      ),
    );
  },
);
