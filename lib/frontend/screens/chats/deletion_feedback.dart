import '../../../backend/modules/chat_deletion_plan.dart';
import '../../../backend/modules/pending_deletions.dart';
import '../../../backend/modules/server_outcome.dart';
import '../../../l10n/app_localizations.dart';

String? outcomeFailureText(ServerOutcome outcome, AppLocalizations l10n) {
  if (ChatDeletionRefusal.of(outcome) case final refusal?) {
    return switch (refusal) {
      ChatDeletionRefusal.typeUnknown => l10n.chatTypeUnknownForAll,
      ChatDeletionRefusal.eventTimeUnknown => l10n.chatEventTimeUnknown,
    };
  }
  return switch (outcome) {
    ServerDone() => null,
    ServerRejected(:final message) => message,
    ServerUnreachable() => l10n.serverUnreachable,
  };
}

String pendingDeletionReportText(
  PendingDeletionReport report,
  AppLocalizations l10n,
) => switch (report) {
  PendingDeletionFailed(kind: PendingDeletionKind.messages, :final message) =>
    l10n.deleteMessagesFailedWithReason(message),
  PendingDeletionFailed(kind: PendingDeletionKind.deleteChat, :final message) =>
    l10n.deleteChatFailedWithReason(message),
  PendingDeletionFailed(kind: PendingDeletionKind.leaveChat, :final message) =>
    l10n.leaveChatFailedWithReason(message),
  PendingDeletionChatRefused(refusal: ChatDeletionRefusal.typeUnknown) =>
    l10n.deleteChatTypeUnknown,
  PendingDeletionChatRefused(refusal: ChatDeletionRefusal.eventTimeUnknown) =>
    l10n.chatEventTimeUnknown,
  PendingDeletionStalled() => l10n.deletionStillPending,
  PendingDeletionConfirmed(kind: PendingDeletionKind.messages, :final count) =>
    l10n.deleteMessagesConfirmedForAll(count),
  PendingDeletionConfirmed() => l10n.deleteChatForAllAccepted,
  PendingDeletionAlreadyGone(:final count) => l10n.deleteMessagesAlreadyGone(
    count,
  ),
  PendingDeletionNotConfirmed(:final count, forEveryone: true) =>
    l10n.deleteMessagesNotConfirmedForAll(count),
  PendingDeletionNotConfirmed(:final count) => l10n.deleteMessagesNotConfirmed(
    count,
  ),
};
