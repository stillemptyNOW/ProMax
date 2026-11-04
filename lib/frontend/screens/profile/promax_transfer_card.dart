import '../../../core/config/promax_settings_link.dart';
import '../../../core/utils/share_origin.dart';
import 'package:share_plus/share_plus.dart';
import 'promax_import.dart';
import 'settings_link_import.dart';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import 'package:flutter/services.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:path_provider/path_provider.dart';

import '../../../core/config/promax_archive.dart';
import '../../../core/security/app_lock.dart';
import '../../../core/storage/token_storage.dart';
import '../../../core/utils/save_file_as.dart';
import '../../../l10n/app_localizations.dart';
import '../../widgets/confirm_dialog.dart';
import '../../widgets/with_text_controller.dart';
import '../../widgets/custom_notification.dart';
import '../../widgets/settings_card.dart';

class ProMaxTransferCard extends StatefulWidget {
  const ProMaxTransferCard({super.key});

  @override
  State<ProMaxTransferCard> createState() => _ProMaxTransferCardState();
}

class _ProMaxTransferCardState extends State<ProMaxTransferCard> {
  bool _busy = false;

  Future<void> _export() async {
    if (_busy) return;
    setState(() => _busy = true);
    File? file;
    try {
      final bytes = await ProMaxArchive.export();
      final directory = await getTemporaryDirectory();
      file = File(
        '${directory.path}/ProMax-${DateTime.now().microsecondsSinceEpoch}.promax',
      );
      await file.writeAsBytes(bytes, flush: true);
      final result = Platform.isIOS
          ? await AppLock.instance.external(() async {
              final path =
                  await const MethodChannel(
                    'io.github.stillemptynow.promax/video',
                  ).invokeMethod<String>('exportPromaxArchive', {
                    'path': file!.path,
                  });
              return SaveFileAsResult(
                saved: path != null,
                cancelled: path == null,
                path: path,
              );
            })
          : await saveFileAs(
              source: file,
              fileName: 'ProMax.promax',
              dialogTitle: 'Экспорт настроек ProMax',
            );
      if (mounted && !result.cancelled) {
        showCustomNotification(
          context,
          result.saved
              ? 'Файл .promax сохранён'
              : 'Не удалось сохранить .promax',
        );
      }
    } catch (_) {
      if (mounted) {
        showCustomNotification(context, 'Не удалось экспортировать .promax');
      }
    } finally {
      if (file != null && await file.exists()) await file.delete();
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _exportLink() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final link = await ProMaxSettingsLink.export();
      if (!mounted) return;
      final l10n = AppLocalizations.of(context)!;
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(l10n.settingsLinkTitle),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l10n.settingsLinkPrivacy),
                  const SizedBox(height: 16),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 140),
                    child: SingleChildScrollView(child: SelectableText(link)),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(l10n.settingsLinkDone),
            ),
            TextButton(
              onPressed: () async {
                try {
                  await Clipboard.setData(ClipboardData(text: link));
                  if (!dialogContext.mounted) return;
                  Navigator.pop(dialogContext);
                  if (mounted) {
                    showCustomNotification(context, l10n.settingsLinkCopied);
                  }
                } catch (_) {
                  if (dialogContext.mounted) {
                    showCustomNotification(
                      dialogContext,
                      l10n.settingsLinkFailed,
                    );
                  }
                }
              },
              child: Text(l10n.settingsLinkCopy),
            ),
            FilledButton(
              onPressed: () async {
                try {
                  await AppLock.instance.external(
                    () => Share.share(
                      link,
                      sharePositionOrigin: shareOriginOf(dialogContext),
                    ),
                  );
                } catch (_) {
                  if (dialogContext.mounted) {
                    showCustomNotification(
                      dialogContext,
                      l10n.settingsLinkFailed,
                    );
                  }
                }
              },
              child: Text(l10n.settingsLinkShare),
            ),
          ],
        ),
      );
    } catch (_) {
      if (mounted) {
        showCustomNotification(
          context,
          AppLocalizations.of(context)!.settingsLinkFailed,
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _importLink() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final l10n = AppLocalizations.of(context)!;
      final link = await showDialog<String>(
        context: context,
        builder: (_) => WithTextController(
          builder: (dialogContext, controller) => AlertDialog(
            title: Text(l10n.settingsLinkImport),
            content: TextField(
              controller: controller,
              maxLength: ProMaxSettingsLink.maxLength,
              maxLines: 4,
              autocorrect: false,
              enableSuggestions: false,
              keyboardType: TextInputType.url,
              decoration: InputDecoration(hintText: l10n.settingsLinkPaste),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: Text(l10n.settingsLinkCancel),
              ),
              FilledButton(
                onPressed: () =>
                    Navigator.pop(dialogContext, controller.text.trim()),
                child: Text(l10n.settingsLinkApply),
              ),
            ],
          ),
        ),
      );
      if (link == null || !mounted) return;
      await importProMaxSettingsLink(context, link);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<String?> _askKey() async {
    return showDialog<String>(
      context: context,
      builder: (_) => WithTextController(
        builder: (dialogContext, controller) => AlertDialog(
          title: const Text('Ключ восстановления истории'),
          content: TextField(
            controller: controller,
            obscureText: true,
            autocorrect: false,
            enableSuggestions: false,
            decoration: const InputDecoration(hintText: '64 символа ключа'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Отмена'),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.pop(dialogContext, controller.text.trim()),
              child: const Text('Восстановить'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _import() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final selected = await AppLock.instance.external(
        () =>
            FilePicker.platform.pickFiles(type: FileType.any, withData: false),
      );
      final picked = selected?.files.single;
      if (picked == null || !mounted) return;
      if (!picked.name.toLowerCase().endsWith('.promax') ||
          picked.size > ProMaxArchive.maxBytes ||
          picked.path == null) {
        throw const FormatException('Выберите файл .promax до 64 МБ');
      }
      final data = ProMaxArchive.decode(await File(picked.path!).readAsBytes());
      final accountId = await TokenStorage.getActiveAccountId();
      final backup = data['deleted'];
      Map<String, dynamic>? deleted;
      if (backup is Map &&
          backup['accountId'] == accountId &&
          accountId != null) {
        try {
          deleted = await ProMaxArchive.prepareDeleted(data);
        } catch (_) {
          if (!mounted) return;
          final key = await _askKey();
          if (key == null) return;
          deleted = await ProMaxArchive.prepareDeleted(data, suppliedKey: key);
        }
      }
      if (!mounted) return;
      final confirmed = await showConfirmDialog(
        context,
        title: 'Импорт ProMax',
        message: deleted != null
            ? 'Применить настройки и добавить удалённые сообщения вашего аккаунта? Текущая история сохранится.'
            : 'Применить настройки? История другого аккаунта не будет импортирована, ваши сообщения сохранятся.',
        confirmLabel: 'Импортировать',
      );
      if (!confirmed || !mounted) return;
      final restored = await applyProMaxArchive(
        context,
        data,
        deleted: deleted,
      );
      if (mounted) {
        showCustomNotification(
          context,
          'Настройки применены. Восстановлено сообщений: $restored. Откройте чат заново для обновления истории.',
        );
      }
    } on FormatException catch (error) {
      if (mounted) showCustomNotification(context, error.message);
    } catch (_) {
      if (mounted) {
        showCustomNotification(
          context,
          'Не удалось импортировать файл. Проверьте ключ и файл .promax.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _showKey() async {
    final accountId = await TokenStorage.getActiveAccountId();
    if (accountId == null) {
      if (mounted) showCustomNotification(context, 'Сначала войдите в аккаунт');
      return;
    }
    final key = await ProMaxArchive.recoveryKey(accountId);
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Ключ вашей истории'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Сохраните ключ отдельно от .promax. Он нужен для восстановления удалённых сообщений этого аккаунта на другом устройстве. Настройки импортируются без ключа.',
            ),
            const SizedBox(height: 16),
            SelectableText(key),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: key));
              if (dialogContext.mounted) Navigator.pop(dialogContext);
            },
            child: const Text('Скопировать'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Готово'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => SettingsCard(
    children: [
      SettingsNavTile(
        icon: Symbols.download,
        label: _busy
            ? AppLocalizations.of(context)!.proMaxArchiveBusy
            : AppLocalizations.of(context)!.proMaxArchiveExport,
        onTap: _export,
      ),
      SettingsNavTile(
        icon: Symbols.upload,
        label: AppLocalizations.of(context)!.proMaxArchiveImport,
        onTap: _import,
      ),
      SettingsNavTile(
        icon: Symbols.link,
        label: AppLocalizations.of(context)!.settingsLinkExport,
        onTap: _exportLink,
      ),
      SettingsNavTile(
        icon: Symbols.add_link,
        label: AppLocalizations.of(context)!.settingsLinkImport,
        onTap: _importLink,
      ),
      SettingsNavTile(
        icon: Symbols.key,
        label: AppLocalizations.of(context)!.proMaxArchiveKey,
        onTap: _showKey,
        isLast: true,
      ),
    ],
  );
}
