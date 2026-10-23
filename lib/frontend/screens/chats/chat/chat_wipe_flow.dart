import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../backend/modules/chat_wipe.dart';
import '../../../../backend/modules/chats.dart';
import '../../../../backend/modules/deletion_policy.dart';
import '../../../../core/cache/message_session_cache.dart';
import '../../../../core/storage/app_database.dart';
import '../../../../core/utils/haptics.dart';
import '../../../../core/utils/logger.dart';
import '../../../../core/utils/server_clock.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../../main.dart';
import '../../../widgets/custom_notification.dart';
import '../profile_action_sheets.dart';
import 'message_deletion.dart';

Future<bool> wipeDialogForBoth(
  BuildContext context, {
  required int myId,
  required int chatId,
  required bool removeForAll,
}) async {
  final l10n = AppLocalizations.of(context)!;
  final policy = DeletionPolicy.instance;
  final age = deletionAgeLimitText(l10n, policy.editTimeout);
  final choice = await showBlurredConfirm(
    context,
    title: removeForAll ? l10n.wipeForBothTitle : l10n.wipeOwnForPeerTitle,
    message: removeForAll
        ? l10n.wipeForBothMessage(age)
        : l10n.wipeOwnForPeerMessage(age),
    confirmLabel: wipeActionLabel(l10n, removeForAll: removeForAll),
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
    final rules = MessageDeletionRules(
      chat: MessageDeletionChat.dialog,
      myId: myId,
      nowMs: ServerClock.now(),
      editTimeout: policy.editTimeout,
    );
    result = await ChatWipe.run(
      fetchPage: (from, count) => messagesModule.fetchHistory(
        myId,
        chatId,
        fromTime: from,
        count: count,
      ),
      deletableForEveryone: rules.allowsForEveryone,
      deleteForEveryone: (ids) =>
          messagesModule.deleteMessages(chatId, ids, forEveryone: true),
      removeChat: (seen) async => (await chats.deleteChat(
        api,
        chatId: chatId,
        forAll: removeForAll,
        seenEventTime: seen,
        accountId: myId,
      )).outcome,
      removeForAll: removeForAll,
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
      _summary(finished, l10n, age),
      duration: const Duration(seconds: 6),
    );
  }
  return finished?.chatRemoved ?? false;
}

String wipeActionLabel(AppLocalizations l10n, {required bool removeForAll}) =>
    removeForAll ? l10n.wipeForBothAction : l10n.wipeOwnForPeerAction;

Future<void> _forgetLocally(int myId, int chatId, List<String> ids) async {
  await AppDatabase.deleteMessages(myId, chatId, ids);
  MessageSessionCache.removeMessages(myId, chatId, ids);
  await chats.reconcileLastMessage(myId, chatId);
}

String _summary(ChatWipeResult? result, AppLocalizations l10n, String age) {
  if (result == null) return l10n.wipeSummaryInterrupted;
  final chatError = result.chatError;
  return [
    l10n.wipeSummaryForPeer(result.deletedForPeer),
    if (result.notConfirmed > 0)
      l10n.wipeSummaryNotConfirmed(result.notConfirmed),
    if (!result.removeForAll && result.keptForPeer > 0)
      l10n.wipeSummaryKeptForPeer(result.keptForPeer, age),
    if (result.historyIncomplete) l10n.wipeSummaryHistoryIncomplete,
    if (result.chatRemoved)
      result.removeForAll
          ? l10n.wipeSummaryChatForAllAccepted
          : l10n.wipeSummaryChatRemovedForMe,
    if (chatError != null) l10n.wipeSummaryChatKept(chatError),
    if (result.unreachable) l10n.wipeSummaryInterrupted,
  ].join('. ');
}
