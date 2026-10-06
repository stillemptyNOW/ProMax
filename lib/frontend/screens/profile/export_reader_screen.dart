import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../core/export/chat_export.dart';
import '../../../core/security/app_lock.dart';
import '../../../core/utils/format.dart';
import '../../widgets/connection_status.dart';
import '../../widgets/custom_notification.dart';
import '../../widgets/promax_bubble_border.dart';
import '../chats/chat_export_sheet.dart';

class ExportReaderScreen extends StatefulWidget {
  const ExportReaderScreen({super.key});

  @override
  State<ExportReaderScreen> createState() => _ExportReaderScreenState();
}

class _ExportReaderScreenState extends State<ExportReaderScreen> {
  ChatExport? _export;
  bool _busy = false;

  Future<void> _open() async {
    final result = await AppLock.instance.external(
      () => FilePicker.platform.pickFiles(),
    );
    final path = result?.files.firstOrNull?.path;
    if (path == null || !mounted) return;
    final password = await askExportPassword(context, confirm: false);
    if (password == null || !mounted) return;
    setState(() => _busy = true);
    try {
      final bytes = await File(path).readAsBytes();
      final export = await ChatExport.decrypt(bytes, password);
      if (mounted) setState(() => _export = export);
    } on FormatException catch (e) {
      if (mounted) showCustomNotification(context, e.message);
    } catch (e) {
      if (mounted) showCustomNotification(context, 'Не удалось открыть: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final export = _export;
    return Scaffold(
      backgroundColor: cs.surface,
      appBar: ConnectionTitleBar(
        titleText: export?.chatName ?? 'Экспорт переписки',
        backgroundColor: cs.surface,
      ),
      body: SafeArea(
        top: false,
        child: export == null
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Symbols.lock_open, size: 56, color: cs.primary),
                      const SizedBox(height: 14),
                      Text(
                        'Открой файл .pmxchat и введи пароль',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: cs.onSurface, fontSize: 16),
                      ),
                      const SizedBox(height: 18),
                      FilledButton.icon(
                        onPressed: _busy ? null : _open,
                        icon: const Icon(Symbols.folder_open),
                        label: Text(_busy ? 'Расшифровываю…' : 'Выбрать файл'),
                      ),
                    ],
                  ),
                ),
              )
            : ListView.builder(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 120),
                itemCount: export.messages.length + 1,
                itemBuilder: (context, index) {
                  if (index == 0) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(
                        'Сообщений: ${export.messages.length}',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: cs.onSurfaceVariant),
                      ),
                    );
                  }
                  final m = export.messages[index - 1];
                  return Align(
                    alignment: m.mine
                        ? Alignment.centerRight
                        : Alignment.centerLeft,
                    child: Container(
                      margin: const EdgeInsets.symmetric(vertical: 3),
                      constraints: BoxConstraints(
                        maxWidth: MediaQuery.sizeOf(context).width * 0.78,
                      ),
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
                      decoration: promaxBubbleDecoration(
                        cs: cs,
                        color: m.mine
                            ? cs.primaryContainer
                            : cs.surfaceContainerHighest,
                        isMe: m.mine,
                        radius: BorderRadius.circular(18),
                        tail: false,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (!m.mine)
                            Text(
                              m.senderName,
                              style: TextStyle(
                                color: cs.primary,
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          Text(
                            m.text.isEmpty ? 'Вложение' : m.text,
                            style: TextStyle(color: cs.onSurface, fontSize: 15),
                          ),
                          Align(
                            alignment: Alignment.centerRight,
                            child: Text(
                              formatChatListStamp(
                                DateTime.fromMillisecondsSinceEpoch(m.time),
                              ),
                              style: TextStyle(
                                color: cs.onSurfaceVariant,
                                fontSize: 11,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
      ),
    );
  }
}
