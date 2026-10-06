import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../core/reminders/message_reminders.dart';
import '../../../core/utils/format.dart';
import '../../widgets/custom_notification.dart';

Future<void> showMessageReminderSheet(
  BuildContext context, {
  required int chatId,
  required String messageId,
  required String chatName,
  required String text,
  required int messageTime,
}) async {
  final service = MessageReminders.instance;
  final existing = service.find(chatId, messageId);
  final choice = await showModalBottomSheet<Object>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) {
      final cs = Theme.of(sheetContext).colorScheme;
      final now = DateTime.now();
      return SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 4),
                child: Text(
                  'Напомнить о сообщении',
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
                  existing == null
                      ? 'ProMax пришлёт уведомление и откроет этот чат'
                      : 'Сейчас напомню ${formatReminderStamp(existing.dueAt, now: now)}',
                  style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13.5),
                ),
              ),
              for (final preset in ReminderPreset.forNow(now))
                ListTile(
                  leading: const Icon(Symbols.alarm),
                  title: Text(preset.label),
                  trailing: Text(
                    formatReminderStamp(preset.at, now: now),
                    style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
                  ),
                  onTap: () => Navigator.pop(sheetContext, preset.at),
                ),
              ListTile(
                leading: const Icon(Symbols.calendar_month),
                title: const Text('Выбрать дату и время'),
                onTap: () => Navigator.pop(sheetContext, #custom),
              ),
              if (existing != null)
                ListTile(
                  leading: Icon(Symbols.alarm_off, color: cs.error),
                  title: Text(
                    'Отменить напоминание',
                    style: TextStyle(color: cs.error),
                  ),
                  onTap: () => Navigator.pop(sheetContext, #cancel),
                ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      );
    },
  );
  if (choice == null || !context.mounted) return;
  if (choice == #cancel) {
    if (existing != null) await service.remove(existing);
    if (context.mounted) {
      showCustomNotification(context, 'Напоминание отменено');
    }
    return;
  }
  final at = choice is DateTime ? choice : await _pickDateTime(context);
  if (at == null || !context.mounted) return;
  if (!at.isAfter(DateTime.now())) {
    showCustomNotification(context, 'Это время уже прошло');
    return;
  }
  final reminder = await service.add(
    chatId: chatId,
    messageId: messageId,
    chatName: chatName,
    text: text,
    messageTime: messageTime,
    at: at,
  );
  if (!context.mounted) return;
  showCustomNotification(
    context,
    reminder == null
        ? 'Разреши уведомления, чтобы ProMax мог напомнить'
        : 'Напомню ${formatReminderStamp(at)}',
  );
}

Future<DateTime?> _pickDateTime(BuildContext context) async {
  final now = DateTime.now();
  final date = await showDatePicker(
    context: context,
    initialDate: now,
    firstDate: DateTime(now.year, now.month, now.day),
    lastDate: now.add(const Duration(days: 365)),
  );
  if (date == null || !context.mounted) return null;
  final time = await showTimePicker(
    context: context,
    initialTime: TimeOfDay.fromDateTime(now.add(const Duration(hours: 1))),
  );
  if (time == null) return null;
  return DateTime(date.year, date.month, date.day, time.hour, time.minute);
}
