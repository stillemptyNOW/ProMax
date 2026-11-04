import 'package:flutter/material.dart';

import '../../../core/config/promax_settings_link.dart';
import '../../../core/security/app_lock.dart';
import '../../../l10n/app_localizations.dart';
import '../../widgets/confirm_dialog.dart';
import '../../widgets/custom_notification.dart';
import 'promax_import.dart';

bool _importing = false;

Future<void> importProMaxSettingsLink(BuildContext context, String link) async {
  if (_importing || AppLock.instance.locked.value) return;
  _importing = true;
  final l10n = AppLocalizations.of(context)!;
  try {
    final data = ProMaxSettingsLink.decode(link);
    if (!context.mounted) return;
    final confirmed = await showConfirmDialog(
      context,
      title: l10n.settingsLinkTitle,
      message: l10n.settingsLinkConfirm,
      confirmLabel: l10n.settingsLinkApply,
    );
    if (!confirmed || !context.mounted || AppLock.instance.locked.value) return;
    await applyProMaxArchive(context, data);
    if (context.mounted) {
      showCustomNotification(context, l10n.settingsLinkApplied);
    }
  } on FormatException {
    if (context.mounted) {
      showCustomNotification(context, l10n.settingsLinkInvalid);
    }
  } catch (_) {
    if (context.mounted) {
      showCustomNotification(context, l10n.settingsLinkFailed);
    }
  } finally {
    _importing = false;
  }
}
