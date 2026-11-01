import 'dart:async';
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../core/hub/hub_client.dart';
import '../../../core/hub/hub_inbox.dart';
import '../../../l10n/app_localizations.dart';
import '../../widgets/confirm_dialog.dart';
import '../../widgets/custom_notification.dart';

enum ServiceChat { announcements, admin, preview }

String serviceChatTitle(ServiceChat kind, AppLocalizations l10n) =>
    switch (kind) {
      ServiceChat.announcements => l10n.hubAnnouncements,
      ServiceChat.admin => l10n.hubAdmin,
      ServiceChat.preview => l10n.hubPreview,
    };

class ServiceChatScreen extends StatefulWidget {
  const ServiceChatScreen({super.key, required this.inbox, required this.kind});
  final HubInbox inbox;
  final ServiceChat kind;
  @override
  State<ServiceChatScreen> createState() => _ServiceChatScreenState();
}

class _ServiceChatScreenState extends State<ServiceChatScreen> {
  final _text = TextEditingController();
  final _code = TextEditingController();
  bool _busy = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    widget.inbox.addListener(_onInbox);
    if (widget.kind == ServiceChat.announcements) widget.inbox.readers++;
    unawaited(_load());
  }

  void _onInbox() {
    if (widget.kind == ServiceChat.announcements) {
      unawaited(widget.inbox.markRead());
    }
  }

  Future<void> _load() async {
    try {
      if (widget.kind == ServiceChat.announcements) {
        await widget.inbox.refresh();
        await widget.inbox.markRead();
      } else if (widget.inbox.activated) {
        await widget.inbox.refreshDraft();
        if (mounted) _text.text = widget.inbox.draft?.text ?? '';
      }
    } catch (_) {
      if (mounted) {
        showCustomNotification(
          context,
          AppLocalizations.of(context)!.hubUnavailable,
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _action(
    Future<void> Function() operation, {
    String? success,
  }) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await operation();
      if (mounted && success != null) showCustomNotification(context, success);
    } catch (error) {
      if (mounted) {
        final l10n = AppLocalizations.of(context)!;
        showCustomNotification(
          context,
          error is HubException && error.status == 409
              ? l10n.hubDraftChanged
              : l10n.hubActionFailed,
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    await _action(() async {
      await widget.inbox.saveDraft(_text.text);
      if (!mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute<void>(
          builder: (_) =>
              ServiceChatScreen(inbox: widget.inbox, kind: ServiceChat.preview),
        ),
      );
    });
  }

  Future<void> _publish() async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showConfirmDialog(
      context,
      title: l10n.hubPublish,
      message: l10n.hubPublishConfirm,
      confirmLabel: l10n.hubPublish,
    );
    if (!confirmed || !mounted) return;
    await _action(widget.inbox.publish, success: l10n.hubPublished);
  }

  @override
  void dispose() {
    widget.inbox.removeListener(_onInbox);
    if (widget.kind == ServiceChat.announcements) widget.inbox.readers--;
    _text.dispose();
    _code.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final inbox = widget.inbox;
    return Scaffold(
      appBar: AppBar(
        title: Text(serviceChatTitle(widget.kind, l10n)),
        actions: [
          IconButton(
            tooltip: l10n.hubRefresh,
            onPressed: _busy ? null : _load,
            icon: const Icon(Symbols.refresh),
          ),
        ],
      ),
      body: ListenableBuilder(
        listenable: inbox,
        builder: (context, _) {
          if (_loading) return const Center(child: CircularProgressIndicator());
          if (widget.kind != ServiceChat.announcements && !inbox.activated) {
            return ListView(
              padding: const EdgeInsets.all(24),
              children: [
                Text(l10n.hubActivationHint),
                const SizedBox(height: 16),
                TextField(
                  controller: _code,
                  obscureText: true,
                  enableSuggestions: false,
                  autocorrect: false,
                  decoration: InputDecoration(
                    labelText: l10n.hubActivationCode,
                  ),
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: _busy
                      ? null
                      : () => _action(() async {
                          await inbox.activate(_code.text);
                          _code.clear();
                          if (mounted) _text.text = inbox.draft?.text ?? '';
                        }),
                  child: Text(l10n.hubActivate),
                ),
              ],
            );
          }
          if (widget.kind == ServiceChat.announcements) {
            return Column(
              children: [
                if (inbox.offline)
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(l10n.hubOffline),
                  ),
                Expanded(
                  child: inbox.messages.isEmpty
                      ? Center(child: Text(l10n.hubNoAnnouncements))
                      : RefreshIndicator(
                          onRefresh: _load,
                          child: ListView.builder(
                            reverse: true,
                            padding: const EdgeInsets.all(16),
                            itemCount: inbox.messages.length,
                            itemBuilder: (context, index) {
                              final message = inbox
                                  .messages[inbox.messages.length - index - 1];
                              final date = DateTime.fromMillisecondsSinceEpoch(
                                message.created * 1000,
                              );
                              return _MessageCard(
                                key: ValueKey(message.id),
                                text: message.text,
                                footer:
                                    '${MaterialLocalizations.of(context).formatMediumDate(date)} '
                                    '${MaterialLocalizations.of(context).formatTimeOfDay(TimeOfDay.fromDateTime(date))}',
                              );
                            },
                          ),
                        ),
                ),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(l10n.hubReadOnly),
                ),
              ],
            );
          }
          final draft = inbox.draft;
          final published =
              draft != null && draft.revision == draft.publishedRevision;
          if (widget.kind == ServiceChat.preview) {
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(l10n.hubPreviewHint),
                const SizedBox(height: 16),
                if (draft != null && draft.text.isNotEmpty)
                  _MessageCard(
                    text: draft.text,
                    footer: published ? l10n.hubPublished : l10n.hubDraft,
                  )
                else
                  Text(l10n.hubDraftEmpty),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed:
                      _busy || published || draft == null || draft.text.isEmpty
                      ? null
                      : _publish,
                  icon: const Icon(Symbols.campaign),
                  label: Text(l10n.hubPublish),
                ),
              ],
            );
          }
          return Column(
            children: [
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Text(l10n.hubAdminHint),
                    if (draft != null && draft.text.isNotEmpty)
                      _MessageCard(text: draft.text, footer: l10n.hubDraft),
                  ],
                ),
              ),
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _text,
                          minLines: 1,
                          maxLines: 8,
                          maxLength: 8000,
                          decoration: InputDecoration(
                            hintText: l10n.hubCompose,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton.filled(
                        tooltip: l10n.hubSendToPreview,
                        onPressed: _busy ? null : _save,
                        icon: const Icon(Symbols.visibility),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _MessageCard extends StatelessWidget {
  const _MessageCard({super.key, required this.text, required this.footer});
  final String text;
  final String footer;
  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.symmetric(vertical: 6),
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SelectableText(text),
          const SizedBox(height: 8),
          Text(footer, style: Theme.of(context).textTheme.labelSmall),
        ],
      ),
    ),
  );
}
