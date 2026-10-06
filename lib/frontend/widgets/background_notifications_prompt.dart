import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/config/build_profile.dart';
import '../../core/push/fkm_bridge.dart';
import '../../core/push/fkm_controller.dart';
import '../../l10n/app_localizations.dart';
import 'confirm_dialog.dart';
import 'custom_notification.dart';

const _offeredKey = 'promax_background_notifications_offered';

bool get _needsOwnConnection =>
    !kIsWeb &&
    defaultTargetPlatform == TargetPlatform.android &&
    !BuildProfile.firebasePush;

Future<void> offerBackgroundNotifications(BuildContext context) async {
  if (!_needsOwnConnection) return;
  final fkm = FkmController.instance;
  if (!fkm.isSupported || fkm.enabled.value) return;
  if (await FkmBridge.instance.isEnabled()) return;
  final prefs = await SharedPreferences.getInstance();
  if (prefs.getBool(_offeredKey) ?? false) return;
  if (!context.mounted) return;
  await prefs.setBool(_offeredKey, true);
  if (!context.mounted) return;
  final l10n = AppLocalizations.of(context)!;
  final confirmed = await showConfirmDialog(
    context,
    title: l10n.backgroundNotificationsOfferTitle,
    message: l10n.backgroundNotificationsOfferMessage,
    confirmLabel: l10n.notificationsFkmEnableLabel,
    cancelLabel: l10n.backgroundNotificationsOfferLater,
  );
  if (!confirmed || !context.mounted) return;
  await enableBackgroundNotifications(context);
}

Future<bool> enableBackgroundNotifications(BuildContext context) async {
  final l10n = AppLocalizations.of(context)!;
  final applied = await FkmController.instance.setEnabled(true);
  if (!context.mounted) return applied;
  if (!applied) {
    showCustomNotification(context, l10n.notificationsFkmPermissionDenied);
    return false;
  }
  await offerBatteryExemption(context);
  return true;
}

Future<void> offerBatteryExemption(BuildContext context) async {
  if (await FkmBridge.instance.isIgnoringBatteryOptimizations()) return;
  if (!context.mounted) return;
  final l10n = AppLocalizations.of(context)!;
  final confirmed = await showConfirmDialog(
    context,
    title: l10n.notificationsFkmBatteryTitle,
    message: l10n.notificationsFkmBatteryMessage,
    confirmLabel: l10n.notificationsFkmBatteryAction,
  );
  if (!confirmed) return;
  await FkmBridge.instance.requestIgnoreBatteryOptimizations();
}
