import 'dart:async';
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import '../../../core/hub/hub_content.dart';
import '../../../core/hub/hub_inbox.dart';
import '../../../core/push/notification_bridge.dart';
import '../../../core/utils/app_foreground.dart';
import '../../../l10n/app_localizations.dart';
import '../../widgets/custom_notification.dart';
import '../../widgets/hub/hub_announcement_banner.dart';
import '../../widgets/hub/hub_kind_style.dart';
import 'announcement_screen.dart';
import 'service_chat_screen.dart';

class ServiceChatTiles extends StatefulWidget {
  const ServiceChatTiles({
    super.key,
    required this.accountId,
    required this.phone,
  });
  final int accountId;
  final int phone;
  @override
  State<ServiceChatTiles> createState() => _ServiceChatTilesState();
}

class _ServiceChatTilesState extends State<ServiceChatTiles> {
  late final HubInbox _inbox = HubInbox(
    accountId: widget.accountId,
    phone: widget.phone,
  );
  int? _lastUnread;

  @override
  void initState() {
    super.initState();
    _inbox.addListener(_onInbox);
    unawaited(_inbox.init());
  }

  void _onInbox() {
    final previous = _lastUnread;
    _lastUnread = _inbox.unread;
    if (previous == null ||
        _inbox.unread <= previous ||
        _inbox.readers > 0 ||
        _inbox.muted) {
      return;
    }
    if (!AppForeground.value) {
      _notifyOs();
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        showCustomNotification(
          context,
          AppLocalizations.of(context)!.hubNewAnnouncement,
        );
      }
    });
  }

  void _notifyOs() {
    final message = _inbox.visible.isEmpty ? null : _inbox.visible.last;
    if (message == null) return;
    final l10n = AppLocalizations.of(context)!;
    final title = message.meta.title.isNotEmpty
        ? message.meta.title
        : message.meta.kind.label(l10n);
    unawaited(
      NotificationBridge.instance.showAnnouncement(
        id: message.id,
        title: title,
        body: HubRichText.plain(message.text),
        kind: message.meta.kind.name,
        channelName: l10n.hubNotificationChannel,
        openLabel: l10n.hubNotificationOpen,
      ),
    );
  }

  @override
  void dispose() {
    _inbox.removeListener(_onInbox);
    _inbox.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return ListenableBuilder(
      listenable: _inbox,
      builder: (context, _) => Column(
        children: [
          if (_inbox.banner case final banner?)
            HubAnnouncementBanner(
              message: banner,
              footer: hubStamp(context, banner),
              onDismiss: () => _inbox.dismissBanner(banner.id),
              onOpen: () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => ServiceChatScreen(
                    inbox: _inbox,
                    kind: ServiceChat.announcements,
                  ),
                ),
              ),
            ),
          for (final kind in [
            if (_inbox.adminCandidate) ServiceChat.admin,
            if (_inbox.adminCandidate) ServiceChat.preview,
            ServiceChat.announcements,
          ])
            ListTile(
              leading: CircleAvatar(
                child: Icon(switch (kind) {
                  ServiceChat.announcements => Symbols.campaign,
                  ServiceChat.admin => Symbols.admin_panel_settings,
                  ServiceChat.preview => Symbols.visibility,
                }),
              ),
              title: Text(serviceChatTitle(kind, l10n)),
              subtitle: Text(
                kind == ServiceChat.announcements && _inbox.visible.isNotEmpty
                    ? HubRichText.plain(_inbox.visible.last.text)
                    : l10n.hubServiceChat,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: kind != ServiceChat.announcements
                  ? const Icon(Symbols.push_pin, size: 16)
                  : _inbox.unread > 0
                  ? Badge(label: Text('${_inbox.unread}'))
                  : null,
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => ServiceChatScreen(inbox: _inbox, kind: kind),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
