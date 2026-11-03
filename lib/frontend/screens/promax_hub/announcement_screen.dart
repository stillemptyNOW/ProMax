import 'package:flutter/material.dart';

import '../../../core/hub/hub_client.dart';
import '../../../l10n/app_localizations.dart';
import '../../widgets/hub/hub_actions.dart';
import '../../widgets/hub/hub_announcement_card.dart';
import '../../widgets/hub/hub_kind_style.dart';

String hubStamp(BuildContext context, HubMessage message) {
  final date = DateTime.fromMillisecondsSinceEpoch(message.created * 1000);
  final material = MaterialLocalizations.of(context);
  return '${material.formatMediumDate(date)} '
      '${material.formatTimeOfDay(TimeOfDay.fromDateTime(date))}';
}

class AnnouncementScreen extends StatelessWidget {
  const AnnouncementScreen({super.key, required this.message});
  final HubMessage message;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(message.meta.kind.label(AppLocalizations.of(context)!)),
    ),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        HubAnnouncementCard(
          text: message.text,
          meta: message.meta,
          footer: hubStamp(context, message),
          onAction: () => runHubAction(context, message.meta),
        ),
      ],
    ),
  );
}
