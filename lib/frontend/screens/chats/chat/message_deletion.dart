import 'package:flutter/material.dart';

import '../../../../backend/modules/messages.dart';
import '../../../../backend/modules/pending_deletions.dart';
import '../../../../core/config/app_shape.dart';
import '../../../../l10n/app_localizations.dart';

class MessageModeration {
  const MessageModeration({
    required this.myId,
    this.canDeleteAny = false,
    this.canDeleteOwnPosts = false,
  });

  final int myId;
  final bool canDeleteAny;
  final bool canDeleteOwnPosts;

  bool covers(CachedMessage message) =>
      int.tryParse(message.id) != null &&
      (canDeleteAny || (canDeleteOwnPosts && message.senderId == myId));
}

class MessageDeletionPlan {
  const MessageDeletionPlan({
    required this.messages,
    this.moderation = const MessageModeration(myId: 0),
  });

  final List<CachedMessage> messages;
  final MessageModeration moderation;

  bool get isEmpty => messages.isEmpty;

  bool get offersForMembers =>
      messages.isNotEmpty && messages.every(moderation.covers);

  List<String> notes(AppLocalizations l10n) => [
    if (!offersForMembers && messages.any(moderation.covers))
      l10n.deleteMessagesSelectionOnlyForMe,
  ];

  List<DeletionPart> parts({required bool forMembers}) => [
    (messages: messages, forEveryone: forMembers && offersForMembers),
  ];
}

Future<bool?> showDeleteMessagesDialog(
  BuildContext context, {
  required MessageDeletionPlan plan,
}) {
  final cs = Theme.of(context).colorScheme;
  final l10n = AppLocalizations.of(context)!;
  final offersForMembers = plan.offersForMembers;
  final notes = plan.notes(l10n);
  var forMembers = offersForMembers;
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
            if (offersForMembers) ...[
              const SizedBox(height: 16),
              InkWell(
                onTap: () => setLocalState(() => forMembers = !forMembers),
                borderRadius: BorderRadius.circular(8),
                child: Row(
                  children: [
                    Checkbox(
                      value: forMembers,
                      onChanged: (v) =>
                          setLocalState(() => forMembers = v ?? false),
                    ),
                    Expanded(
                      child: Text(
                        l10n.chatDeleteForAllMembers,
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
            onPressed: () => Navigator.pop(ctx, offersForMembers && forMembers),
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
