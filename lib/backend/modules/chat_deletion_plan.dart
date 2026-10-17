import 'server_outcome.dart';

final class ChatDeletionResult {
  const ChatDeletionResult(this.outcome, {this.historyErased = false})
    : typeUnknown = false;

  const ChatDeletionResult.typeUnknown()
    : outcome = const ServerRejected('chat type unknown'),
      historyErased = false,
      typeUnknown = true;

  final ServerOutcome outcome;
  final bool historyErased;
  final bool typeUnknown;

  bool get ok => outcome.ok;
}

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

  static ChatDeletionPlan? of({
    required String? chatType,
    required bool forAll,
  }) {
    if (!forAll) return forMe;
    return switch (chatType) {
      null => null,
      'DIALOG' => eraseForPeer,
      _ => removeForMembers,
    };
  }

  Future<ChatDeletionResult> run({
    required Future<ServerOutcome> Function() clearHistoryForAll,
    required Future<ServerOutcome> Function({required bool forAll}) deleteChat,
    bool historyErased = false,
  }) async {
    final eraseNow = clearForAll && !historyErased;
    if (eraseNow) {
      final cleared = await clearHistoryForAll();
      if (cleared is! ServerDone) return ChatDeletionResult(cleared);
    }
    final deleted = await deleteChat(forAll: deleteForAll);
    final gone = clearForAll && deleted is ServerRejected && deleted.notFound;
    return ChatDeletionResult(
      gone ? const ServerDone() : deleted,
      historyErased: clearForAll,
    );
  }
}
