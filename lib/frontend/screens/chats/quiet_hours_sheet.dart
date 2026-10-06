import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../core/push/quiet_hours.dart';

Future<void> showQuietHoursSheet(
  BuildContext context,
  int chatId,
) => showModalBottomSheet<void>(
  context: context,
  showDragHandle: true,
  backgroundColor: Theme.of(context).colorScheme.surfaceContainerHigh,
  builder: (sheetContext) {
    final cs = Theme.of(sheetContext).colorScheme;
    final service = QuietHours.instance;
    return SafeArea(
      child: ValueListenableBuilder<Map<int, QuietWindow>>(
        valueListenable: service.windows,
        builder: (context, _, _) {
          final current = service.windowFor(chatId);
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
                child: Text(
                  'Тихие часы',
                  style: TextStyle(
                    color: cs.onSurface,
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Text(
                  'В это время уведомления из этого чата не показываются. Сообщения приходят как обычно.',
                  style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
                ),
              ),
              ListTile(
                leading: const Icon(Symbols.notifications_active),
                title: const Text('Выключены'),
                trailing: current == null
                    ? Icon(Symbols.check, color: cs.primary)
                    : null,
                onTap: () => service.set(chatId, null),
              ),
              for (final window in QuietHours.presets)
                ListTile(
                  leading: const Icon(Symbols.bedtime),
                  title: Text(window.label),
                  trailing: window == current
                      ? Icon(Symbols.check, color: cs.primary)
                      : null,
                  onTap: () => service.set(chatId, window),
                ),
            ],
          );
        },
      ),
    );
  },
);
