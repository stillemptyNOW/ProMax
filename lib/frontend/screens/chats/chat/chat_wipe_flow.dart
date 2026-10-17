import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../backend/modules/chat_wipe.dart';
import '../../../../backend/modules/chats.dart';
import '../../../../core/cache/message_session_cache.dart';
import '../../../../core/storage/app_database.dart';
import '../../../../core/utils/haptics.dart';
import '../../../../core/utils/logger.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../../main.dart';
import '../../../widgets/custom_notification.dart';
import '../profile_action_sheets.dart';

Future<bool> wipeDialogForBoth(
  BuildContext context, {
  required int myId,
  required int chatId,
}) async {
  final l10n = AppLocalizations.of(context)!;
  final choice = await showBlurredConfirm(
    context,
    title: l10n.wipeForBothTitle,
    message: l10n.wipeForBothMessage,
    confirmLabel: l10n.wipeForBothAction,
    cancelLabel: l10n.chatInfoActionCancel,
    destructive: true,
  );
  if (!context.mounted || !choice.confirmed) return false;

  final progress = ValueNotifier<String>(l10n.wipeCollecting);
  final navigator = Navigator.of(context, rootNavigator: true);
  final overlay = Overlay.of(context, rootOverlay: true);
  unawaited(
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => PopScope(
        canPop: false,
        child: AlertDialog(
          content: Row(
            children: [
              const SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(strokeWidth: 3),
              ),
              const SizedBox(width: 18),
              Expanded(
                child: ValueListenableBuilder<String>(
                  valueListenable: progress,
                  builder: (context, text, _) => Text(text),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );

  ChatWipeResult? result;
  try {
    result = await ChatWipe.run(
      myId: myId,
      fetchPage: (from, count) => messagesModule.fetchHistory(
        myId,
        chatId,
        fromTime: from,
        count: count,
      ),
      deleteBatch: (ids, {required forEveryone}) =>
          messagesModule.deleteMessages(chatId, ids, forEveryone: forEveryone),
      clearForAll: (seen) => chats.clearHistory(
        api,
        chatId: chatId,
        forAll: true,
        seenEventTime: seen,
      ),
      removeChat: (seen) async => (await chats.deleteChat(
        api,
        chatId: chatId,
        forAll: false,
        seenEventTime: seen,
        accountId: myId,
      )).outcome,
      onProgress: (total, deleted) => progress.value = deleted == 0
          ? l10n.wipeFound(total)
          : l10n.wipeDeleting(deleted, total),
    );
    if (!result.chatRemoved && result.deletedIds.isNotEmpty) {
      await _forgetLocally(myId, chatId, result.deletedIds);
    }
  } catch (e) {
    logger.e('Удаление у обоих сорвалось: $e');
  } finally {
    navigator.pop();
    progress.dispose();
  }

  final finished = result;
  if (finished == null || !finished.complete) Haptics.error();
  if (overlay.mounted) {
    showCustomNotificationOnOverlay(
      overlay,
      _summary(finished, l10n),
      duration: const Duration(seconds: 6),
    );
  }
  return finished?.chatRemoved ?? false;
}

Future<void> _forgetLocally(int myId, int chatId, List<String> ids) async {
  await AppDatabase.deleteMessages(myId, chatId, ids);
  MessageSessionCache.removeMessages(myId, chatId, ids);
  await chats.reconcileLastMessage(myId, chatId);
}

String _summary(ChatWipeResult? result, AppLocalizations l10n) {
  if (result == null) return l10n.wipeSummaryInterrupted;
  final clearError = result.clearError;
  final chatError = result.chatError;
  return [
    l10n.wipeSummaryForBoth(result.deletedForBoth),
    if (result.onlyForMe > 0) l10n.wipeSummaryOnlyForMe(result.onlyForMe),
    if (result.notDeleted > 0) l10n.wipeSummaryNotDeleted(result.notDeleted),
    if (result.historyIncomplete) l10n.wipeSummaryHistoryIncomplete,
    if (clearError != null) l10n.wipeSummaryClearFailed(clearError),
    if (chatError != null) l10n.wipeSummaryChatKept(chatError),
    if (result.unreachable) l10n.wipeSummaryInterrupted,
  ].join('. ');
}
