import 'server_outcome.dart';

enum ChatDeletionRefusal {
  typeUnknown('promax.chat.type-unknown'),
  eventTimeUnknown('promax.chat.event-time-unknown');

  const ChatDeletionRefusal(this.errorKey);

  final String errorKey;

  ServerRejected get outcome =>
      ServerRejected('запрос не отправлен: $name', errorKey: errorKey);

  static ChatDeletionRefusal? of(ServerOutcome outcome) => switch (outcome) {
    ServerRejected(:final errorKey?) =>
      values.where((refusal) => refusal.errorKey == errorKey).firstOrNull,
    _ => null,
  };
}

final class ChatDeletionResult {
  const ChatDeletionResult(this.outcome, {this.forAll = false});

  ChatDeletionResult.refused(ChatDeletionRefusal refusal)
    : outcome = refusal.outcome,
      forAll = false;

  final ServerOutcome outcome;
  final bool forAll;

  ChatDeletionRefusal? get refusal => ChatDeletionRefusal.of(outcome);

  bool get ok => outcome.ok;
}

bool ownerDeletesForAll({
  required int chatId,
  required String? chatType,
  required int? owner,
  required int myId,
}) => chatId != 0 && chatType == 'CHAT' && owner != null && owner == myId;

class ChatDeletionPlan {
  const ChatDeletionPlan._(this.forAll);

  static const forMe = ChatDeletionPlan._(false);
  static const forEveryone = ChatDeletionPlan._(true);

  final bool forAll;

  static ChatDeletionPlan? of({
    required bool forAll,
    required int chatId,
    required String? chatType,
    required int? owner,
    required int myId,
  }) {
    if (!forAll || chatId == 0) return forMe;
    if (chatType == null) return null;
    return ownerDeletesForAll(
          chatId: chatId,
          chatType: chatType,
          owner: owner,
          myId: myId,
        )
        ? forEveryone
        : forMe;
  }

  Map<String, Object> payload({
    required int chatId,
    required int lastEventTime,
  }) => {'chatId': chatId, 'lastEventTime': lastEventTime, 'forAll': forAll};
}
