import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../core/storage/chat_notes_store.dart';
import '../../widgets/custom_notification.dart';
import '../../widgets/with_text_controller.dart';

Future<void> showChatNoteSheet(
  BuildContext context, {
  required int chatId,
  required String chatName,
}) async {
  final store = ChatNotesStore.instance;
  final existing = store.noteFor(chatId);
  final result = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheetContext) => WithTextController(
      initialText: existing,
      builder: (context, controller) {
        final cs = Theme.of(context).colorScheme;
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Icon(Symbols.sticky_note_2, color: cs.primary),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Заметка о «$chatName»',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: cs.onSurface,
                            fontSize: 19,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Видна только тебе и хранится на этом устройстве',
                    style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: controller,
                    autofocus: existing == null,
                    minLines: 4,
                    maxLines: 10,
                    maxLength: ChatNotesStore.maxLength,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(
                      hintText: 'Дни рождения, договорённости, важные детали…',
                      counterText: '',
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      if (existing != null) ...[
                        Expanded(
                          child: OutlinedButton(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: cs.error,
                            ),
                            onPressed: () => Navigator.pop(sheetContext, ''),
                            child: const Text('Удалить'),
                          ),
                        ),
                        const SizedBox(width: 12),
                      ],
                      Expanded(
                        child: FilledButton(
                          onPressed: () =>
                              Navigator.pop(sheetContext, controller.text),
                          child: const Text('Сохранить'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    ),
  );
  if (result == null) return;
  await store.save(chatId, result);
  if (!context.mounted) return;
  if (result.trim().isEmpty && existing != null) {
    showCustomNotification(context, 'Заметка удалена');
  } else if (result.trim().isNotEmpty) {
    showCustomNotification(context, 'Заметка сохранена');
  }
}
