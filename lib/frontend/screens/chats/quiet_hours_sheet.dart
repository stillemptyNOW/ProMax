import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../core/push/quiet_hours.dart';

Future<void> showQuietHoursSheet(
  BuildContext context,
  int chatId,
) => _showWindowSheet(
  context,
  title: 'Тихие часы',
  offLabel: 'Выключены',
  subtitle:
      'В это время уведомления из этого чата не показываются. Сообщения приходят как обычно.',
  listenable: QuietHours.instance.windows,
  current: () => QuietHours.instance.windowFor(chatId),
  choose: (window) => QuietHours.instance.set(chatId, window),
);

Future<void> showGlobalQuietHoursSheet(
  BuildContext context,
) => _showWindowSheet(
  context,
  title: 'Не беспокоить',
  offLabel: 'Выключено',
  subtitle:
      'По расписанию ProMax молчит во всех чатах сразу. Сообщения приходят как обычно, уведомления о них не показываются.',
  listenable: QuietHours.instance.global,
  current: () => QuietHours.instance.global.value,
  choose: QuietHours.instance.setGlobal,
);

Future<void> _showWindowSheet(
  BuildContext context, {
  required String title,
  required String offLabel,
  required String subtitle,
  required Listenable listenable,
  required QuietWindow? Function() current,
  required Future<void> Function(QuietWindow? window) choose,
}) => showModalBottomSheet<void>(
  context: context,
  showDragHandle: true,
  builder: (sheetContext) {
    final cs = Theme.of(sheetContext).colorScheme;
    return SafeArea(
      child: ListenableBuilder(
        listenable: listenable,
        builder: (context, _) {
          final selected = current();
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
                child: Text(
                  title,
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
                  subtitle,
                  style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
                ),
              ),
              ListTile(
                leading: const Icon(Symbols.notifications_active),
                title: Text(offLabel),
                trailing: selected == null
                    ? Icon(Symbols.check, color: cs.primary)
                    : null,
                onTap: () => choose(null),
              ),
              for (final window in QuietHours.presets)
                ListTile(
                  leading: const Icon(Symbols.bedtime),
                  title: Text(window.label),
                  trailing: window == selected
                      ? Icon(Symbols.check, color: cs.primary)
                      : null,
                  onTap: () => choose(window),
                ),
            ],
          );
        },
      ),
    );
  },
);
