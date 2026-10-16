import '../../core/cache/message_session_cache.dart';
import '../../core/storage/app_database.dart';
import '../../core/storage/token_storage.dart';
import '../api.dart';
import 'chats.dart';
import 'messages.dart';
import 'pending_deletions.dart';
import 'server_outcome.dart';

class ApiDeletionGateway implements PendingDeletionGateway {
  ApiDeletionGateway(this._api, this._messages);

  final Api _api;
  final MessagesModule _messages;

  @override
  bool get isOnline => _api.state == SessionState.online;

  @override
  int get sessionEpoch => _api.sessionEpoch;

  @override
  Stream<void> get wentOnline =>
      _api.stateStream.where((state) => state == SessionState.online);

  @override
  Future<int?> activeAccountId() => TokenStorage.getActiveAccountId();

  @override
  Future<ServerOutcome> deleteMessages(
    int chatId,
    List<String> messageIds, {
    required bool forEveryone,
  }) => _messages.deleteMessages(chatId, messageIds, forEveryone: forEveryone);

  @override
  Future<ServerOutcome> deleteChat(
    int accountId,
    int chatId, {
    required bool forAll,
  }) => chats.deleteChat(
    _api,
    chatId: chatId,
    forAll: forAll,
    accountId: accountId,
  );

  @override
  Future<ServerOutcome> leaveChat(int accountId, int chatId) =>
      chats.leaveChat(_api, chatId: chatId, accountId: accountId);

  @override
  Future<void> forgetMessages(
    int accountId,
    int chatId,
    List<String> ids,
  ) async {
    await AppDatabase.deleteMessages(accountId, chatId, ids);
    MessageSessionCache.removeMessages(accountId, chatId, ids);
    await chats.reconcileLastMessage(accountId, chatId);
  }

  @override
  Future<List<CachedMessage>> loadMessages(
    int accountId,
    int chatId,
    List<String> ids,
  ) async => CachedMessage.fromDbRowsAsync(
    await AppDatabase.loadMessagesByIds(accountId, chatId, ids),
  );
}
