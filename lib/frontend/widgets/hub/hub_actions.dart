import 'package:flutter/material.dart';

import '../../../core/config/build_profile.dart';
import '../../../core/hub/hub_content.dart';
import '../../../core/utils/link_opener.dart';
import '../../../core/utils/update_checker.dart';
import '../../../l10n/app_localizations.dart';
import '../../screens/profile/promax_settings_screen.dart';
import '../custom_notification.dart';
import '../update_dialog.dart';

Future<void> runHubAction(BuildContext context, HubMeta meta) async {
  switch (meta.buttonAction) {
    case HubAction.link:
      if (meta.buttonUrl.isNotEmpty) {
        await openExternalUrl(context, meta.buttonUrl);
      }
    case HubAction.settings:
      await Navigator.push(
        context,
        MaterialPageRoute<void>(builder: (_) => const ProMaxSettingsScreen()),
      );
    case HubAction.update:
      if (!BuildProfile.selfUpdate) {
        if (meta.buttonUrl.isNotEmpty) {
          await openExternalUrl(context, meta.buttonUrl);
        }
        return;
      }
      final result = await UpdateChecker.checkNow();
      if (!context.mounted) return;
      if (result.status == UpdateCheckStatus.updateAvailable) {
        await showUpdateDialog(context, result.update!);
      } else if (result.status == UpdateCheckStatus.upToDate) {
        showCustomNotification(
          context,
          AppLocalizations.of(context)!.updateUpToDate,
        );
      }
  }
}
