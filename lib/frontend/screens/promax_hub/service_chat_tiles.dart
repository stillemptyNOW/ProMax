import 'dart:async';
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import '../../../core/hub/hub_inbox.dart';
import '../../../core/utils/app_foreground.dart';
import '../../../l10n/app_localizations.dart';
import '../../widgets/custom_notification.dart';
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
        !AppForeground.value) {
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
                kind == ServiceChat.announcements && _inbox.messages.isNotEmpty
                    ? _inbox.messages.last.text
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
