import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../backend/modules/messages.dart';
import '../../../core/crypto/message_decryption_cache.dart';
import '../../../core/export/chat_export.dart';
import '../../../core/storage/app_database.dart';
import '../../widgets/custom_notification.dart';

Future<String?> askExportPassword(
  BuildContext context, {
  required bool confirm,
}) => showDialog<String>(
  context: context,
  builder: (_) => _ExportPasswordDialog(confirm: confirm),
);

class _ExportPasswordDialog extends StatefulWidget {
  const _ExportPasswordDialog({required this.confirm});

  final bool confirm;

  @override
  State<_ExportPasswordDialog> createState() => _ExportPasswordDialogState();
}

class _ExportPasswordDialogState extends State<_ExportPasswordDialog> {
  final _first = TextEditingController();
  final _second = TextEditingController();
  bool _obscured = true;
  String? _error;

  @override
  void dispose() {
    _first.dispose();
    _second.dispose();
    super.dispose();
  }

  void _submit() {
    if (_first.text.length < 6) {
      setState(() => _error = 'Не короче 6 символов');
      return;
    }
    if (widget.confirm && _first.text != _second.text) {
      setState(() => _error = 'Пароли не совпадают');
      return;
    }
    Navigator.pop(context, _first.text);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final visibility = IconButton(
      icon: Icon(_obscured ? Symbols.visibility : Symbols.visibility_off),
      onPressed: () => setState(() => _obscured = !_obscured),
    );
    return AlertDialog(
      title: Text(widget.confirm ? 'Пароль для экспорта' : 'Пароль экспорта'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _first,
            obscureText: _obscured,
            autofocus: true,
            textInputAction: widget.confirm
                ? TextInputAction.next
                : TextInputAction.done,
            onSubmitted: widget.confirm ? null : (_) => _submit(),
            decoration: InputDecoration(
              labelText: 'Пароль',
              suffixIcon: visibility,
            ),
          ),
          if (widget.confirm)
            TextField(
              controller: _second,
              obscureText: _obscured,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _submit(),
              decoration: const InputDecoration(labelText: 'Повтори пароль'),
            ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(_error!, style: TextStyle(color: cs.error)),
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Отмена'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Готово')),
      ],
    );
  }
}

Future<void> showChatExportSheet(
  BuildContext context, {
  required int accountId,
  required int chatId,
  required String chatName,
}) async {
  final encrypted = await showModalBottomSheet<bool>(
    context: context,
    showDragHandle: true,
    backgroundColor: Theme.of(context).colorScheme.surfaceContainerHigh,
    builder: (sheetContext) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 0, 20, 4),
            child: Text(
              'Экспорт переписки',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Text(
              'Сохраняются сообщения, которые есть в памяти телефона. Чтобы выгрузить всё, сначала открой «Статистику чата» и загрузи историю.',
              style: TextStyle(
                color: Theme.of(sheetContext).colorScheme.onSurfaceVariant,
                fontSize: 13,
              ),
            ),
          ),
          ListTile(
            leading: const Icon(Symbols.lock),
            title: const Text('Зашифрованный файл .pmxchat'),
            subtitle: const Text('Открывается только в ProMax по паролю'),
            onTap: () => Navigator.pop(sheetContext, true),
          ),
          ListTile(
            leading: const Icon(Symbols.description),
            title: const Text('Обычный текст .txt'),
            onTap: () => Navigator.pop(sheetContext, false),
          ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
  if (encrypted == null || !context.mounted) return;
  String? password;
  if (encrypted) {
    password = await askExportPassword(context, confirm: true);
    if (password == null || !context.mounted) return;
  }
  try {
    final rows = await AppDatabase.loadMessages(
      accountId,
      chatId,
      onlyVisible: true,
    );
    final messages = [
      for (final row in rows.reversed) CachedMessage.fromDbRow(row),
    ];
    final export = ChatExport(
      chatId: chatId,
      chatName: chatName,
      exportedAt: DateTime.now().millisecondsSinceEpoch,
      messages: [
        for (final m in messages)
          if (!m.isControl)
            ExportedMessage(
              id: m.id,
              senderId: m.senderId,
              senderName: m.senderId == accountId
                  ? 'Я'
                  : (ContactCache.get(m.senderId) ?? chatName),
              text: MessageDecryptionCache.instance.readableText(m) ?? '',
              time: m.time,
              mine: m.senderId == accountId,
            ),
      ],
    );
    final Uint8List bytes = password != null
        ? await ChatExport.encrypt(export, password)
        : Uint8List.fromList(utf8.encode(export.toText()));
    final dir = await getTemporaryDirectory();
    final safeName = chatName
        .replaceAll(RegExp(r'[^\p{L}\p{N} _-]', unicode: true), '')
        .trim();
    final file = File(
      '${dir.path}/${safeName.isEmpty ? 'chat' : safeName}.${password != null ? 'pmxchat' : 'txt'}',
    );
    await file.writeAsBytes(bytes, flush: true);
    await Share.shareXFiles([XFile(file.path)]);
  } catch (e) {
    if (context.mounted) {
      showCustomNotification(context, 'Не удалось экспортировать: $e');
    }
  }
}
