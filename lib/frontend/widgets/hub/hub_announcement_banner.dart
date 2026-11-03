import 'package:flutter/material.dart';

import '../../../core/hub/hub_client.dart';
import 'hub_announcement_card.dart';

class HubAnnouncementBanner extends StatelessWidget {
  const HubAnnouncementBanner({
    super.key,
    required this.message,
    required this.footer,
    required this.onOpen,
    required this.onDismiss,
  });
  final HubMessage message;
  final String footer;
  final VoidCallback onOpen;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) => Dismissible(
    key: ValueKey('hub_banner_${message.id}'),
    onDismissed: (_) => onDismiss(),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: HubAnnouncementCard(
        text: message.text,
        meta: message.meta,
        footer: footer,
        unread: true,
        maxBodyLines: 2,
        onTap: onOpen,
      ),
    ),
  );
}
