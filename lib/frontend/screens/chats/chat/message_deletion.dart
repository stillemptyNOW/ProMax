import 'package:flutter/material.dart';

import '../../../../backend/modules/deletion_policy.dart';
import '../../../../backend/modules/messages.dart';
import '../../../../backend/modules/pending_deletions.dart';
import '../../../../core/config/app_shape.dart';
import '../../../../l10n/app_localizations.dart';

class MessageDeletionPlan {
  MessageDeletionPlan({required this.messages, required this.rules})
    : denials = {for (final message in messages) ?rules.denialFor(message)};

  final List<CachedMessage> messages;
  final MessageDeletionRules rules;
  final Set<ForEveryoneDenial> denials;

  bool get isEmpty => messages.isEmpty;

  bool get offersForEveryone => messages.isNotEmpty && denials.isEmpty;

  bool get _someEligible => messages.any(rules.allowsForEveryone);

  List<String> notes(AppLocalizations l10n) {
    if (offersForEveryone || messages.isEmpty) return const [];
    final dialog = rules.chat == MessageDeletionChat.dialog;
    final age = deletionAgeLimitText(l10n, rules.editTimeout);
    return [
      if (denials.contains(ForEveryoneDenial.notMine))
        dialog
            ? l10n.deleteMessagesPeerOnlyForMe
            : l10n.deleteMessagesOthersOnlyForMe,
      if (denials.contains(ForEveryoneDenial.tooOld))
        dialog
            ? l10n.deleteMessagesTooOldForPeer(age)
            : l10n.deleteMessagesTooOldForAll(age),
      if (denials.contains(ForEveryoneDenial.scheduled))
        l10n.deleteMessagesScheduledOnlyForMe,
      if (_someEligible) l10n.deleteMessagesSelectionOnlyForMe,
    ];
  }

  List<DeletionPart> parts({required bool forEveryone}) => [
    (messages: messages, forEveryone: forEveryone && offersForEveryone),
  ];
}

String deletionAgeLimitText(AppLocalizations l10n, Duration limit) {
  final days = limit.inDays;
  if (days >= 2 && limit == Duration(days: days)) {
    return l10n.deletionAgeLimitDays(days);
  }
  final hours = limit.inHours;
  if (hours >= 1 && limit == Duration(hours: hours)) {
    return l10n.deletionAgeLimitHours(hours);
  }
  return l10n.deletionAgeLimitMinutes(
    limit.inMinutes < 1 ? 1 : limit.inMinutes,
  );
}

Future<bool?> showDeleteMessagesDialog(
  BuildContext context, {
  required MessageDeletionPlan plan,
  required String peerName,
}) {
  final cs = Theme.of(context).colorScheme;
  final l10n = AppLocalizations.of(context)!;
  final offersForEveryone = plan.offersForEveryone;
  final notes = plan.notes(l10n);
  var alsoForEveryone = offersForEveryone;
  return showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setLocalState) => AlertDialog(
        backgroundColor: cs.surfaceContainerHigh,
        shape: AppShape.dialogBorder,
        title: Text(l10n.chatScreenDeleteMessageTitle),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.chatScreenDeleteMessageConfirm,
              style: TextStyle(color: cs.onSurfaceVariant, fontSize: 15),
            ),
            if (offersForEveryone) ...[
              const SizedBox(height: 16),
              InkWell(
                onTap: () =>
                    setLocalState(() => alsoForEveryone = !alsoForEveryone),
                borderRadius: BorderRadius.circular(8),
                child: Row(
                  children: [
                    Checkbox(
                      value: alsoForEveryone,
                      onChanged: (v) =>
                          setLocalState(() => alsoForEveryone = v ?? false),
                    ),
                    Expanded(
                      child: Text(
                        l10n.chatScreenDeleteAlsoFor(peerName),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: cs.onSurface, fontSize: 15),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            for (final note in notes) ...[
              const SizedBox(height: 8),
              Text(
                note,
                style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l10n.chatInfoActionCancel),
          ),
          TextButton(
            onPressed: () =>
                Navigator.pop(ctx, offersForEveryone && alsoForEveryone),
            child: Text(
              l10n.msgActionsDelete,
              style: TextStyle(color: cs.error),
            ),
          ),
        ],
      ),
    ),
  );
}
