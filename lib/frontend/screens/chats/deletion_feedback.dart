import '../../../backend/modules/pending_deletions.dart';
import '../../../backend/modules/server_outcome.dart';
import '../../../l10n/app_localizations.dart';

String? outcomeFailureText(ServerOutcome outcome, AppLocalizations l10n) =>
    switch (outcome) {
      ServerDone() => null,
      ServerRejected(:final message) => message,
      ServerUnreachable() => l10n.serverUnreachable,
    };

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
  PendingDeletionKeptForPeer(:final count) => l10n.deleteMessagesKeptForPeer(
    count,
  ),
};
