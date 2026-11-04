import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../core/hub/hub_client.dart';
import '../../../core/hub/hub_content.dart';
import '../../../core/hub/hub_inbox.dart';
import '../../../l10n/app_localizations.dart';
import '../../widgets/confirm_dialog.dart';
import '../../widgets/custom_notification.dart';
import '../../widgets/hub/hub_actions.dart';
import '../../widgets/hub/hub_announcement_card.dart';
import '../../widgets/hub/hub_kind_style.dart';
import 'announcement_screen.dart';

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
  final _title = TextEditingController();
  final _image = TextEditingController();
  final _label = TextEditingController();
  final _url = TextEditingController();
  HubKind _kind = HubKind.news;
  HubAction _btnAction = HubAction.link;
  bool _busy = false;
  bool _loading = true;
  bool _refreshing = false;
  bool _confirming = false;
  String? _error;

  HubMeta get _meta => HubMeta(
    kind: _kind,
    title: _title.text.trim(),
    image: _image.text.trim(),
    buttonLabel: _label.text.trim(),
    buttonAction: _btnAction,
    buttonUrl: _url.text.trim(),
  );

  void _applyMeta(HubMeta meta) {
    _kind = meta.kind;
    _btnAction = meta.buttonAction;
    _title.text = meta.title;
    _image.text = meta.image;
    _label.text = meta.buttonLabel;
    _url.text = meta.buttonUrl;
  }

  void _applyDraft() {
    _text.text = widget.inbox.editingText ?? widget.inbox.draft?.text ?? '';
    _applyMeta(
      widget.inbox.editingMeta ?? widget.inbox.draft?.meta ?? HubMeta.plain,
    );
  }

  bool get _unsaved =>
      _text.text != (widget.inbox.draft?.text ?? '') ||
      _meta != (widget.inbox.draft?.meta ?? HubMeta.plain);
  bool get _canSave =>
      !_busy &&
      !_refreshing &&
      _text.text.trim().isNotEmpty &&
      _text.text.runes.length <= 8000;

  @override
  void initState() {
    super.initState();
    _applyDraft();
    _text.addListener(_onEditorChanged);
    for (final field in [_title, _image, _label, _url]) {
      field.addListener(_onEditorChanged);
    }
    _code.addListener(_onCodeChanged);
    widget.inbox.addListener(_onInbox);
    if (widget.kind == ServiceChat.announcements) {
      widget.inbox.readers++;
      _readFrom = widget.inbox.seen;
    }
    unawaited(_load());
  }

  void _onInbox() {
    if (widget.kind == ServiceChat.announcements) {
      unawaited(widget.inbox.markRead());
    } else if (widget.kind == ServiceChat.admin &&
        widget.inbox.editingText == null &&
        !_busy) {
      _applyDraft();
    }
  }

  void _onEditorChanged() {
    final unsaved = _unsaved;
    widget.inbox.editingText = unsaved ? _text.text : null;
    widget.inbox.editingMeta = unsaved ? _meta : null;
    if (mounted) setState(() {});
  }

  void _onCodeChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _load() async {
    if (_refreshing || _busy || _confirming) return;
    setState(() {
      _refreshing = true;
      _error = null;
    });
    try {
      if (widget.kind == ServiceChat.announcements) {
        await widget.inbox.refresh();
        await widget.inbox.markRead();
      } else if (widget.inbox.activated) {
        await widget.inbox.refreshDraft();
        if (mounted && widget.kind == ServiceChat.admin) {
          _applyDraft();
        }
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error = AppLocalizations.of(context)!.hubUnavailable);
        showCustomNotification(
          context,
          AppLocalizations.of(context)!.hubUnavailable,
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
          _refreshing = false;
        });
      }
    }
  }

  Future<void> _action(
    Future<void> Function() operation, {
    String? success,
  }) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await operation();
      if (mounted && success != null) showCustomNotification(context, success);
    } catch (error) {
      if (mounted) {
        final l10n = AppLocalizations.of(context)!;
        final message = error is HubException && error.status == 409
            ? l10n.hubDraftChanged
            : l10n.hubActionFailed;
        setState(() => _error = message);
        showCustomNotification(context, message);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    if (!_canSave) return;
    await _action(() async {
      await widget.inbox.saveDraft(_text.text, meta: _meta);
      if (!mounted) return;
      widget.inbox.editingText = null;
      widget.inbox.editingMeta = null;
      _applyDraft();
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
    if (_busy || _refreshing || _confirming) return;
    final revision = widget.inbox.draft?.revision;
    if (revision == null) return;
    final l10n = AppLocalizations.of(context)!;
    setState(() => _confirming = true);
    try {
      final confirmed = await showConfirmDialog(
        context,
        title: l10n.hubPublish,
        message: l10n.hubPublishConfirm,
        confirmLabel: l10n.hubPublish,
      );
      if (!confirmed || !mounted) return;
      await _action(
        () => widget.inbox.publish(revision: revision),
        success: l10n.hubPublished,
      );
    } finally {
      if (mounted) setState(() => _confirming = false);
    }
  }

  @override
  void dispose() {
    widget.inbox.removeListener(_onInbox);
    if (widget.kind == ServiceChat.announcements) widget.inbox.readers--;
    _text.removeListener(_onEditorChanged);
    for (final field in [_title, _image, _label, _url]) {
      field.removeListener(_onEditorChanged);
      field.dispose();
    }
    _code.removeListener(_onCodeChanged);
    _text.dispose();
    _code.dispose();
    super.dispose();
  }

  int _readFrom = 0;

  Widget _field(TextEditingController controller, String label, int max) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: TextField(
          controller: controller,
          enabled: !_busy,
          maxLength: max,
          decoration: InputDecoration(labelText: label, counterText: ''),
        ),
      );

  Widget _kindPicker(AppLocalizations l10n) => Wrap(
    spacing: 8,
    runSpacing: 4,
    children: [
      for (final kind in HubKind.values)
        ChoiceChip(
          avatar: Icon(kind.icon, size: 16),
          label: Text(kind.label(l10n)),
          selected: _kind == kind,
          onSelected: _busy
              ? null
              : (_) => setState(() {
                  _kind = kind;
                  _onEditorChanged();
                }),
        ),
    ],
  );

  Widget _actionPicker(AppLocalizations l10n) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: DropdownButtonFormField<HubAction>(
      initialValue: _btnAction,
      decoration: InputDecoration(labelText: l10n.hubFieldAction),
      items: [
        for (final action in HubAction.values)
          DropdownMenuItem(value: action, child: Text(action.label(l10n))),
      ],
      onChanged: _busy
          ? null
          : (value) => setState(() {
              _btnAction = value ?? HubAction.link;
              _onEditorChanged();
            }),
    ),
  );

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
            onPressed: _busy || _refreshing || _confirming ? null : _load,
            icon: const Icon(Symbols.refresh),
          ),
        ],
      ),
      body: Column(
        children: [
          if ((_busy || _refreshing) && !_loading)
            const LinearProgressIndicator(),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          Expanded(
            child: ListenableBuilder(
              listenable: inbox,
              builder: (context, _) {
                if (_loading) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (widget.kind != ServiceChat.announcements &&
                    !inbox.activated) {
                  return ListView(
                    padding: const EdgeInsets.all(24),
                    children: [
                      Text(l10n.hubActivationHint),
                      const SizedBox(height: 16),
                      TextField(
                        controller: _code,
                        enabled: !_busy,
                        obscureText: true,
                        maxLength: 128,
                        enableSuggestions: false,
                        autocorrect: false,
                        decoration: InputDecoration(
                          labelText: l10n.hubActivationCode,
                        ),
                      ),
                      const SizedBox(height: 16),
                      FilledButton(
                        onPressed: _busy || _code.text.trim().length < 24
                            ? null
                            : () => _action(() async {
                                try {
                                  await inbox.activate(_code.text);
                                } finally {
                                  if (inbox.activated) _code.clear();
                                }
                                if (mounted) _applyDraft();
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
                        child: inbox.visible.isEmpty
                            ? Center(child: Text(l10n.hubNoAnnouncements))
                            : RefreshIndicator(
                                onRefresh: _load,
                                child: _Feed(inbox: inbox, readFrom: _readFrom),
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
                        HubAnnouncementCard(
                          text: draft.text,
                          meta: draft.meta,
                          footer: published ? l10n.hubPublished : l10n.hubDraft,
                          onAction: () => runHubAction(context, draft.meta),
                        )
                      else
                        Text(l10n.hubDraftEmpty),
                      const SizedBox(height: 16),
                      FilledButton.icon(
                        onPressed:
                            _busy ||
                                _refreshing ||
                                _confirming ||
                                published ||
                                draft == null ||
                                draft.text.trim().isEmpty
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
                          const SizedBox(height: 12),
                          Text(
                            _unsaved
                                ? l10n.hubDraftUnsaved
                                : l10n.hubDraftSaved,
                            style: Theme.of(context).textTheme.labelMedium,
                          ),
                          const SizedBox(height: 8),
                          _kindPicker(l10n),
                          const SizedBox(height: 8),
                          _field(_title, l10n.hubFieldTitle, 120),
                          _field(_image, l10n.hubFieldImage, 500),
                          _field(_label, l10n.hubFieldButtonLabel, 40),
                          _actionPicker(l10n),
                          _field(_url, l10n.hubFieldButtonUrl, 500),
                          if (_text.text.trim().isNotEmpty)
                            HubAnnouncementCard(
                              text: _text.text,
                              meta: _meta,
                              footer: _unsaved
                                  ? l10n.hubDraftUnsaved
                                  : published
                                  ? l10n.hubPublished
                                  : l10n.hubDraft,
                              onAction: () => runHubAction(context, _meta),
                            ),
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
                                key: const ValueKey('hub_compose'),
                                controller: _text,
                                enabled: !_busy,
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
                              onPressed: _canSave ? _save : null,
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
          ),
        ],
      ),
    );
  }
}

class _Feed extends StatelessWidget {
  const _Feed({required this.inbox, required this.readFrom});
  final HubInbox inbox;
  final int readFrom;

  static DateTime _day(HubMessage message) {
    final date = DateTime.fromMillisecondsSinceEpoch(message.created * 1000);
    return DateTime(date.year, date.month, date.day);
  }

  String _dayLabel(BuildContext context, DateTime day) {
    final l10n = AppLocalizations.of(context)!;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final gap = today.difference(day).inDays;
    if (gap == 0) return l10n.hubToday;
    if (gap == 1) return l10n.hubYesterday;
    return MaterialLocalizations.of(context).formatMediumDate(day);
  }

  Future<void> _menu(BuildContext context, HubMessage message) async {
    final l10n = AppLocalizations.of(context)!;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheet) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Symbols.content_copy),
              title: Text(l10n.hubMenuCopy),
              onTap: () async {
                Navigator.pop(sheet);
                await Clipboard.setData(
                  ClipboardData(text: HubRichText.plain(message.text)),
                );
                if (context.mounted) {
                  showCustomNotification(context, l10n.hubCopied);
                }
              },
            ),
            ListTile(
              leading: const Icon(Symbols.visibility_off),
              title: Text(l10n.hubMenuHide),
              onTap: () {
                Navigator.pop(sheet);
                unawaited(inbox.hide(message.id));
              },
            ),
            ListTile(
              leading: Icon(
                inbox.muted ? Symbols.notifications : Symbols.notifications_off,
              ),
              title: Text(inbox.muted ? l10n.hubMenuUnmute : l10n.hubMenuMute),
              onTap: () {
                Navigator.pop(sheet);
                unawaited(inbox.setMuted(!inbox.muted));
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final messages = inbox.visible;
    final pinned = messages.lastWhere(
      (message) => message.meta.kind == HubKind.important,
      orElse: () => messages.last,
    );
    final hasPin = pinned.meta.kind == HubKind.important;
    return ListView.builder(
      reverse: true,
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      itemCount: messages.length,
      itemBuilder: (context, index) {
        final message = messages[messages.length - index - 1];
        final previous = index + 1 < messages.length
            ? messages[messages.length - index - 2]
            : null;
        final day = _day(message);
        final newDay = previous == null || _day(previous) != day;
        return Column(
          key: ValueKey(message.id),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (newDay)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Center(
                  child: Text(
                    _dayLabel(context, day),
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
            Dismissible(
              key: ValueKey('dismiss_${message.id}'),
              onDismissed: (_) => unawaited(inbox.hide(message.id)),
              child: HubAnnouncementCard(
                text: message.text,
                meta: message.meta,
                footer: hubStamp(context, message),
                unread: message.id > readFrom,
                pinned: hasPin && message.id == pinned.id,
                onAction: () => runHubAction(context, message.meta),
                onLongPress: () => _menu(context, message),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => AnnouncementScreen(message: message),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
