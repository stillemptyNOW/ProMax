import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../core/disappearing/disappearing_messages.dart';

Future<void> showDisappearingSheet(
  BuildContext context,
  int chatId,
) => showModalBottomSheet<void>(
  context: context,
  showDragHandle: true,
  backgroundColor: Theme.of(context).colorScheme.surfaceContainerHigh,
  builder: (sheetContext) {
    final cs = Theme.of(sheetContext).colorScheme;
    final service = DisappearingMessages.instance;
    return SafeArea(
      child: ValueListenableBuilder<Map<int, int>>(
        valueListenable: service.timers,
        builder: (context, _, _) {
          final current = service.timerFor(chatId);
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
                child: Text(
                  'Исчезающие сообщения',
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
                  'Твои новые сообщения в этом чате удалятся у обоих через выбранное время. ProMax удаляет их, когда запущен; если он был закрыт, удалит при следующем запуске.',
                  style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
                ),
              ),
              for (final seconds in DisappearingMessages.options)
                ListTile(
                  leading: Icon(
                    seconds == 0 ? Symbols.timer_off : Symbols.timer,
                  ),
                  title: Text(DisappearingMessages.label(seconds)),
                  trailing: seconds == current
                      ? Icon(Symbols.check, color: cs.primary)
                      : null,
                  onTap: () => service.setTimer(chatId, seconds),
                ),
            ],
          );
        },
      ),
    );
  },
);
