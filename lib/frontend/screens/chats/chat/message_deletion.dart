import 'package:flutter/material.dart';

import '../../../../backend/modules/messages.dart';
import '../../../../backend/modules/pending_deletions.dart';
import '../../../../core/config/app_shape.dart';
import '../../../../l10n/app_localizations.dart';

class MessageDeletionPlan {
  MessageDeletionPlan({
    required int myId,
    required List<CachedMessage> messages,
    required this.isDialog,
    required this.canDeleteOthersForEveryone,
  }) : own = [
         for (final message in messages)
           if (message.senderId == myId) message,
       ],
       peer = [
         for (final message in messages)
           if (message.senderId != myId) message,
       ];

  final List<CachedMessage> own;
  final List<CachedMessage> peer;
  final bool isDialog;
  final bool canDeleteOthersForEveryone;

  bool get isEmpty => own.isEmpty && peer.isEmpty;

  bool get _peerForEveryone => isDialog || canDeleteOthersForEveryone;

  bool get offersForEveryone =>
      own.isNotEmpty || (peer.isNotEmpty && _peerForEveryone);

  String? note(AppLocalizations l10n) {
    if (peer.isEmpty) return null;
    if (isDialog) return l10n.deleteMessagesPeerFallbackNote;
    if (!_peerForEveryone && own.isNotEmpty) {
      return l10n.deleteMessagesOthersOnlyForMe(peer.length);
    }
    return null;
  }

  List<DeletionPart> parts({required bool forEveryone}) => [
    if (own.isNotEmpty)
      (messages: own, forEveryone: forEveryone, fallbackToSelf: false),
    if (peer.isNotEmpty)
      (
        messages: peer,
        forEveryone: forEveryone && _peerForEveryone,
        fallbackToSelf: isDialog,
      ),
  ];
}

Future<bool?> showDeleteMessagesDialog(
  BuildContext context, {
  required MessageDeletionPlan plan,
  required String peerName,
}) {
  final cs = Theme.of(context).colorScheme;
  final l10n = AppLocalizations.of(context)!;
  final offersForEveryone = plan.offersForEveryone;
  final note = plan.note(l10n);
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
            if (note != null && offersForEveryone && alsoForEveryone) ...[
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
