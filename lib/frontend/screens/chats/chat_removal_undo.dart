import 'package:flutter/material.dart';

import '../../../backend/modules/pending_deletions.dart';
import '../../widgets/undo_notification.dart';

void removeChatsWithUndo(
  BuildContext context, {
  required String message,
  required int accountId,
  required List<({int chatId, bool forAll})> chats,
  PendingDeletionKind kind = PendingDeletionKind.deleteChat,
}) {
  if (chats.isEmpty) return;
  final pending = PendingDeletions.instance;
  final keys = [
    for (final chat in chats)
      pending.holdChat(
        accountId: accountId,
        chatId: chat.chatId,
        kind: kind,
        forAll: chat.forAll,
      ),
  ];
  showUndoNotification(
    context,
    message,
    onUndo: () => pending.cancel(keys),
    onCommit: () => pending.commit(keys),
  );
}
