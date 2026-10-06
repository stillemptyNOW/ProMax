import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../backend/modules/chats.dart';
import '../../../core/reminders/message_reminders.dart';
import '../../../core/security/double_bottom.dart';
import '../../../core/utils/format.dart';
import '../../widgets/connection_status.dart';
import '../../widgets/letter_avatar.dart';
import '../chats/chat_screen.dart';

class RemindersScreen extends StatelessWidget {
  const RemindersScreen({super.key});

  void _open(BuildContext context, MessageReminder reminder) {
    final chat = chats
        .chatsSnapshot(includeHidden: true)
        .where((c) => c.id == reminder.chatId)
        .firstOrNull;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChatScreen(
          chatId: reminder.chatId,
          name: reminder.chatName,
          imageUrl: chat?.iconUrl ?? '',
          chatType: chat?.type ?? (reminder.chatId > 0 ? 'DIALOG' : 'CHAT'),
          initialMessageId: reminder.messageId,
          initialMessageTime: reminder.messageTime,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: cs.surface,
      appBar: ConnectionTitleBar(
        titleText: 'Напоминания',
        backgroundColor: cs.surface,
      ),
      body: SafeArea(
        top: false,
        child: ListenableBuilder(
          listenable: Listenable.merge([
            MessageReminders.instance.items,
            DoubleBottom.listenable,
          ]),
          builder: (context, _) {
            final shown = [
              for (final r in MessageReminders.instance.items.value)
                if (!DoubleBottom.hides(r.chatId)) r,
            ];
            if (shown.isEmpty) return const _EmptyReminders();
            return ListView.builder(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
              itemCount: shown.length,
              itemBuilder: (context, index) {
                final reminder = shown[index];
                return Padding(
                  key: ValueKey(reminder.id),
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Dismissible(
                    key: ValueKey('dismiss-${reminder.id}'),
                    direction: DismissDirection.endToStart,
                    background: Container(
                      alignment: Alignment.centerRight,
                      padding: const EdgeInsets.only(right: 20),
                      decoration: BoxDecoration(
                        color: cs.error,
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Icon(Symbols.alarm_off, color: cs.onError),
                    ),
                    onDismissed: (_) =>
                        MessageReminders.instance.remove(reminder),
                    child: _ReminderCard(
                      reminder: reminder,
                      onTap: () => _open(context, reminder),
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

class _ReminderCard extends StatelessWidget {
  const _ReminderCard({required this.reminder, required this.onTap});

  final MessageReminder reminder;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: cs.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  LetterAvatarFill(
                    name: reminder.chatName,
                    seed: avatarSeedFor(reminder.chatName),
                    size: 28,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      reminder.chatName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: cs.onSurface,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: cs.primaryContainer,
                      borderRadius: BorderRadius.circular(50),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Symbols.alarm,
                            size: 15,
                            color: cs.onPrimaryContainer,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            formatReminderStamp(reminder.dueAt),
                            style: TextStyle(
                              color: cs.onPrimaryContainer,
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                reminder.preview,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: cs.onSurface,
                  fontSize: 15,
                  height: 1.3,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyReminders extends StatelessWidget {
  const _EmptyReminders();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Symbols.alarm, size: 56, color: cs.onSurfaceVariant),
            const SizedBox(height: 12),
            Text(
              'Напоминаний нет',
              style: TextStyle(
                color: cs.onSurface,
                fontSize: 17,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Зажми сообщение и выбери «Напомнить» — ProMax вернёт тебя к нему в нужное время',
              textAlign: TextAlign.center,
              style: TextStyle(color: cs.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}
