import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../core/config/app_shape.dart';
import '../../core/security/file_name_policy.dart';
import '../../core/security/sandbox_settings.dart';
import '../../l10n/app_localizations.dart';
import 'confirm_dialog.dart';

enum MiniAppDownloadChoice { cancel, keep, saveAs }

enum ExternalNavigationChoice { cancel, browser, here }

Future<bool> confirmOpenReceivedFile(
  BuildContext context, {
  required String name,
  String? path,
}) async {
  final displayName = sanitizeFileName(
    name.isNotEmpty ? name : p.basename(path ?? ''),
  );
  final extension =
      riskyExtensionOf(displayName) ??
      (path == null ? null : riskyExtensionOf(p.basename(path)));
  if (extension == null && !await SandboxSettings.confirmEveryFile()) {
    return true;
  }
  if (!context.mounted) return false;
  final l10n = AppLocalizations.of(context)!;
  if (extension != null) {
    return showConfirmDialog(
      context,
      title: l10n.sandboxRiskyFileTitle,
      message: l10n.sandboxRiskyFileMessage(displayName, extension),
      confirmLabel: l10n.sandboxRiskyFileOpen,
      destructive: true,
    );
  }
  return showConfirmDialog(
    context,
    title: l10n.sandboxOpenFileTitle,
    message: l10n.sandboxOpenFileMessage(displayName),
    confirmLabel: l10n.sandboxOpenFileConfirm,
  );
}

Future<MiniAppDownloadChoice> askMiniAppDownload(
  BuildContext context, {
  required String appTitle,
  required String fileName,
  required String host,
}) async {
  final l10n = AppLocalizations.of(context)!;
  final risky = riskyExtensionOf(fileName);
  final message = l10n.sandboxDownloadMessage(appTitle, fileName, host);
  final choice = await _showChoiceDialog<MiniAppDownloadChoice>(
    context,
    title: l10n.sandboxDownloadTitle,
    message: risky == null
        ? message
        : '$message\n\n${l10n.sandboxDownloadRiskyNote(risky)}',
    choices: [
      (MiniAppDownloadChoice.saveAs, l10n.sandboxDownloadSaveAs),
      (MiniAppDownloadChoice.keep, l10n.sandboxDownloadKeep),
    ],
  );
  return choice ?? MiniAppDownloadChoice.cancel;
}

Future<ExternalNavigationChoice> askExternalNavigation(
  BuildContext context, {
  required Uri target,
  bool allowInPlace = false,
}) async {
  final l10n = AppLocalizations.of(context)!;
  final host = target.host.isNotEmpty ? target.host : target.toString();
  final choice = await _showChoiceDialog<ExternalNavigationChoice>(
    context,
    title: l10n.sandboxLeaveTitle,
    message: allowInPlace
        ? l10n.sandboxLeaveMessage(host)
        : l10n.sandboxLeaveExternalMessage(host),
    choices: [
      if (allowInPlace) (ExternalNavigationChoice.here, l10n.sandboxLeaveHere),
      (ExternalNavigationChoice.browser, l10n.sandboxLeaveBrowser),
    ],
  );
  return choice ?? ExternalNavigationChoice.cancel;
}

Future<T?> _showChoiceDialog<T>(
  BuildContext context, {
  required String title,
  required String message,
  required List<(T, String)> choices,
}) {
  final cs = Theme.of(context).colorScheme;
  final l10n = AppLocalizations.of(context)!;
  return showDialog<T>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      backgroundColor: cs.surfaceContainerHigh,
      shape: AppShape.dialogBorder,
      title: Text(title, style: TextStyle(color: cs.onSurface)),
      content: Text(
        message,
        style: TextStyle(color: cs.onSurface, fontSize: 15, height: 1.35),
      ),
      actionsOverflowButtonSpacing: 4,
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: Text(
            l10n.chatInfoActionCancel,
            style: TextStyle(color: cs.onSurfaceVariant),
          ),
        ),
        for (var i = 0; i < choices.length; i++)
          i == choices.length - 1
              ? FilledButton.tonal(
                  onPressed: () =>
                      Navigator.of(dialogContext).pop(choices[i].$1),
                  child: Text(choices[i].$2),
                )
              : TextButton(
                  onPressed: () =>
                      Navigator.of(dialogContext).pop(choices[i].$1),
                  child: Text(choices[i].$2),
                ),
      ],
    ),
  );
}
