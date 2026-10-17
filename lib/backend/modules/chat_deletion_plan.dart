import 'server_outcome.dart';

class ChatDeletionPlan {
  const ChatDeletionPlan._({
    required this.clearForAll,
    required this.deleteForAll,
  });

  static const forMe = ChatDeletionPlan._(
    clearForAll: false,
    deleteForAll: false,
  );
  static const eraseForPeer = ChatDeletionPlan._(
    clearForAll: true,
    deleteForAll: false,
  );
  static const removeForMembers = ChatDeletionPlan._(
    clearForAll: false,
    deleteForAll: true,
  );

  final bool clearForAll;
  final bool deleteForAll;

  static ChatDeletionPlan of({
    required String? chatType,
    required bool forAll,
  }) {
    if (!forAll) return forMe;
    if (chatType == null || chatType == 'DIALOG') return eraseForPeer;
    return removeForMembers;
  }

  Future<ServerOutcome> run({
    required Future<ServerOutcome> Function() clearHistoryForAll,
    required Future<ServerOutcome> Function({required bool forAll}) deleteChat,
  }) async {
    if (clearForAll) {
      final cleared = await clearHistoryForAll();
      if (cleared is! ServerDone) return cleared;
    }
    return deleteChat(forAll: deleteForAll);
  }
}
