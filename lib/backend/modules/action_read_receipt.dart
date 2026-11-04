import '../../core/config/promax_settings.dart';
import '../../core/protocol/opcode_map.dart';
import '../../core/storage/app_database.dart';
import '../../core/storage/token_storage.dart';
import '../api.dart';

enum _ReadAction { reaction, reply, send }

class ActionReadReceipt {
  ActionReadReceipt._(
    this.api,
    this.accountId,
    this.chatId,
    this.messageId,
    this.mark,
    this.epoch,
    this._action,
  );

  final Api api;
  final int accountId;
  final int chatId;
  final int messageId;
  final int mark;
  final int epoch;
  final _ReadAction _action;

  static bool _enabled(_ReadAction action) =>
      ProMaxSettings.antiRead.value &&
      switch (action) {
        _ReadAction.reaction => ProMaxSettings.readOnReaction.value,
        _ReadAction.reply => ProMaxSettings.readOnReply.value,
        _ReadAction.send => ProMaxSettings.readOnSend.value,
      };

  static Future<ActionReadReceipt?> forReaction(
    Api api,
    int chatId,
    String messageId,
  ) => _capture(api, chatId, _ReadAction.reaction, messageId: messageId);

  static Future<ActionReadReceipt?> forSend(
    Api api,
    Map<String, dynamic> payload, {
    int? accountId,
  }) async {
    final message = payload['message'];
    final chatId = payload['chatId'];
    if (message is! Map ||
        chatId is! int ||
        message['delayedAttributes'] != null) {
      return null;
    }
    final link = message['link'];
    if (link is Map && link['type'] == 'REPLY') {
      if (link['chatId'] != chatId || link['messageId'] == null) return null;
      return _capture(
        api,
        chatId,
        _ReadAction.reply,
        messageId: '${link['messageId']}',
        accountId: accountId,
      );
    }
    return _capture(api, chatId, _ReadAction.send, accountId: accountId);
  }

  static Future<ActionReadReceipt?> _capture(
    Api api,
    int chatId,
    _ReadAction action, {
    String? messageId,
    int? accountId,
  }) async {
    if (!_enabled(action)) return null;
    final epoch = api.sessionEpoch;
    try {
      final activeAccount = await TokenStorage.getActiveAccountId();
      if (activeAccount == null ||
          (accountId != null && activeAccount != accountId)) {
        return null;
      }
      final row = messageId == null
          ? await AppDatabase.loadLatestIncomingMessage(activeAccount, chatId)
          : await AppDatabase.loadMessage(activeAccount, chatId, messageId);
      if (row == null ||
          row['sender_id'] == activeAccount ||
          row['deleted'] != 0) {
        return null;
      }
      final id = int.tryParse('${row['id']}');
      final mark = row['time'];
      if (id == null || id <= 0 || mark is! int || mark <= 0) return null;
      return ActionReadReceipt._(
        api,
        activeAccount,
        chatId,
        id,
        mark,
        epoch,
        action,
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> send() async {
    try {
      if (!_enabled(_action) ||
          await TokenStorage.getActiveAccountId() != accountId ||
          api.sessionEpoch != epoch) {
        return;
      }
      await api.sendRequest(
        Opcode.chatMark,
        {
          'type': 'READ_MESSAGE',
          'chatId': chatId,
          'messageId': messageId,
          'mark': mark,
        },
        silent: true,
        beforeSend: () {
          if (api.sessionEpoch != epoch || !_enabled(_action)) {
            throw StateError('Read action is no longer current');
          }
        },
      );
    } catch (_) {}
  }
}
