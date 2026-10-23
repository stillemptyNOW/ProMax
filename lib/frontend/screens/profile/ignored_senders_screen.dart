import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../backend/modules/messages.dart' show ContactCache;
import '../../../core/config/app_shape.dart';
import '../../../core/storage/ignored_senders.dart';
import '../../../core/storage/token_storage.dart';
import '../../../l10n/app_localizations.dart';
import '../../widgets/connection_status.dart';
import '../../widgets/custom_notification.dart';
import '../../widgets/hint_bubble.dart';
import '../../widgets/promax_avatar.dart';
import '../../widgets/promax_ui.dart';

class IgnoredSendersScreen extends StatefulWidget {
  const IgnoredSendersScreen({super.key});

  @override
  State<IgnoredSendersScreen> createState() => _IgnoredSendersScreenState();
}

class _IgnoredSendersScreenState extends State<IgnoredSendersScreen> {
  int? _accountId;

  @override
  void initState() {
    super.initState();
    _loadAccount();
  }

  Future<void> _loadAccount() async {
    await IgnoredSenders.instance.load();
    final accountId = await TokenStorage.getActiveAccountId();
    if (mounted) setState(() => _accountId = accountId);
  }

  Future<void> _add() async {
    final l10n = AppLocalizations.of(context)!;
    final accountId = _accountId;
    if (accountId == null) {
      showCustomNotification(context, l10n.ignoredSendersNoAccount);
      return;
    }
    final added = await showDialog<bool>(
      context: context,
      builder: (_) => _AddIgnoredSenderDialog(accountId: accountId),
    );
    if (added == true && mounted) {
      showCustomNotification(context, l10n.ignoredSendersAdded);
    }
  }

  Future<void> _remove(int userId) async {
    final accountId = _accountId;
    if (accountId == null) return;
    final removed = await IgnoredSenders.instance.remove(accountId, userId);
    if (removed && mounted) {
      showCustomNotification(
        context,
        AppLocalizations.of(context)!.ignoredSendersRemoved,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      backgroundColor: cs.surface,
      appBar: ConnectionTitleBar(
        titleText: l10n.ignoredSendersTitle,
        backgroundColor: cs.surface,
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _add,
        icon: const Icon(Symbols.person_add),
        label: Text(l10n.ignoredSendersAdd),
      ),
      body: SafeArea(
        top: false,
        child: ValueListenableBuilder<int>(
          valueListenable: IgnoredSenders.instance.revision,
          builder: (context, _, _) {
            final accountId = _accountId;
            final ids = accountId == null
                ? const <int>[]
                : IgnoredSenders.instance.of(accountId);
            return ListView.builder(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
              itemCount: ids.isEmpty ? 2 : ids.length + 1,
              itemBuilder: (context, index) {
                if (index == 0) return const _IgnoredSendersExplanation();
                if (ids.isEmpty) return const _IgnoredSendersEmpty();
                final userId = ids[index - 1];
                return _IgnoredSenderTile(
                  key: ValueKey(userId),
                  userId: userId,
                  onRemove: () => _remove(userId),
                );
              },
            );
          },
        ),
      ),
    );
  }
}

class _IgnoredSendersExplanation extends StatelessWidget {
  const _IgnoredSendersExplanation();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ProMaxSectionTitle(l10n.ignoredSendersHowItWorks),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: cs.surfaceContainerHigh,
            borderRadius: AppShape.cardRadius,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.ignoredSendersExplanation,
                style: TextStyle(color: cs.onSurface, fontSize: 14.5),
              ),
              const SizedBox(height: 12),
              Text(
                l10n.ignoredSendersCaveat,
                style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }
}

class _IgnoredSendersEmpty extends StatelessWidget {
  const _IgnoredSendersEmpty();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 16),
      child: Column(
        children: [
          Icon(Symbols.speaker_notes_off, size: 48, color: cs.outline),
          const SizedBox(height: 12),
          Text(
            l10n.ignoredSendersEmpty,
            style: TextStyle(
              color: cs.onSurface,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            l10n.ignoredSendersEmptyHint,
            textAlign: TextAlign.center,
            style: TextStyle(color: cs.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _IgnoredSenderTile extends StatelessWidget {
  const _IgnoredSenderTile({
    super.key,
    required this.userId,
    required this.onRemove,
  });

  final int userId;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    final idLabel = l10n.ignoredSendersUserId(userId);
    final name = ContactCache.get(userId) ?? idLabel;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: cs.surfaceContainerHigh,
        borderRadius: AppShape.cardRadius,
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              ProMaxAvatar(
                name: name,
                size: 44,
                imageUrl: ContactCache.getAvatar(userId),
                userId: userId,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: cs.onSurface,
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    if (name != idLabel)
                      Text(
                        idLabel,
                        style: TextStyle(
                          color: cs.onSurfaceVariant,
                          fontSize: 13,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              TextButton(
                onPressed: onRemove,
                child: Text(l10n.ignoredSendersRemove),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AddIgnoredSenderDialog extends StatefulWidget {
  const _AddIgnoredSenderDialog({required this.accountId});

  final int accountId;

  @override
  State<_AddIgnoredSenderDialog> createState() =>
      _AddIgnoredSenderDialogState();
}

class _AddIgnoredSenderDialogState extends State<_AddIgnoredSenderDialog> {
  final _controller = TextEditingController();
  final _fieldKey = GlobalKey();
  bool _saving = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_saving) return;
    final l10n = AppLocalizations.of(context)!;
    final anchor = _fieldKey.currentContext ?? context;
    final userId = IgnoredSenders.parseUserId(_controller.text);
    if (userId == null) {
      showHintBubble(anchor, l10n.ignoredSendersInvalidId);
      return;
    }
    if (userId == widget.accountId) {
      showHintBubble(anchor, l10n.ignoredSendersSelfId);
      return;
    }
    if (IgnoredSenders.instance.isIgnored(widget.accountId, userId)) {
      showHintBubble(anchor, l10n.ignoredSendersAlreadyAdded);
      return;
    }
    setState(() => _saving = true);
    final added = await IgnoredSenders.instance.add(widget.accountId, userId);
    if (!mounted) return;
    Navigator.pop(context, added);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return AlertDialog(
      title: Text(l10n.ignoredSendersTitle),
      content: TextField(
        key: _fieldKey,
        controller: _controller,
        autofocus: true,
        keyboardType: TextInputType.number,
        inputFormatters: [
          FilteringTextInputFormatter.digitsOnly,
          LengthLimitingTextInputFormatter(16),
        ],
        decoration: InputDecoration(
          labelText: l10n.ignoredSendersIdLabel,
          hintText: l10n.ignoredSendersIdHint,
        ),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(l10n.ignoredSendersCancel),
        ),
        FilledButton(
          onPressed: _saving ? null : _submit,
          child: Text(l10n.ignoredSendersConfirmAdd),
        ),
      ],
    );
  }
}
