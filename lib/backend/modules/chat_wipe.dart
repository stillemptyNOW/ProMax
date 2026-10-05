import 'messages.dart';

typedef WipeHistoryPage =
    Future<List<CachedMessage>> Function(int? fromTime, int count);
typedef WipeDeleteBatch =
    Future<bool> Function(List<String> ids, {required bool forEveryone});
typedef WipeFinish = Future<String?> Function();

class ChatWipeResult {
  const ChatWipeResult({
    required this.found,
    required this.deletedForBoth,
    required this.keptOnPeerSide,
    required this.chatError,
  });

  final int found;
  final int deletedForBoth;
  final int keptOnPeerSide;
  final String? chatError;

  bool get complete => keptOnPeerSide == 0 && chatError == null;
}

class ChatWipe {
  static const int pageSize = 100;
  static const int batchSize = 100;
  static const int maxPages = 500;

  static Future<ChatWipeResult> run({
    required int myId,
    required WipeHistoryPage fetchPage,
    required WipeDeleteBatch deleteBatch,
    required WipeFinish clearForAll,
    required WipeFinish deleteChatForAll,
    void Function(int scanned, int deleted)? onProgress,
  }) async {
    final all = <String>{};
    final mine = <String>{};
    int? cursor;
    for (var page = 0; page < maxPages; page++) {
      final batch = await fetchPage(cursor, pageSize);
      if (batch.isEmpty) break;
      var oldest = batch.first.time;
      var added = 0;
      for (final message in batch) {
        if (message.time < oldest) oldest = message.time;
        if (message.isControl || message.deleted) continue;
        if (all.add(message.id)) added++;
        if (message.senderId == myId) mine.add(message.id);
      }
      onProgress?.call(all.length, 0);
      if (added == 0 || batch.length < pageSize) break;
      cursor = oldest - 1;
    }

    final ids = all.toList();
    var deleted = 0;
    var kept = 0;
    for (var start = 0; start < ids.length; start += batchSize) {
      final chunk = ids.sublist(
        start,
        start + batchSize > ids.length ? ids.length : start + batchSize,
      );
      if (await deleteBatch(chunk, forEveryone: true)) {
        deleted += chunk.length;
      } else {
        final ownDeleted = await _deleteOneByOne(chunk, mine, deleteBatch);
        deleted += ownDeleted;
        kept += chunk.length - ownDeleted;
      }
      onProgress?.call(ids.length, deleted);
    }

    final clearError = await clearForAll();
    final deleteError = await deleteChatForAll();
    return ChatWipeResult(
      found: ids.length,
      deletedForBoth: deleted,
      keptOnPeerSide: kept,
      chatError: deleteError ?? clearError,
    );
  }

  static Future<int> _deleteOneByOne(
    List<String> chunk,
    Set<String> mine,
    WipeDeleteBatch deleteBatch,
  ) async {
    final own = chunk.where(mine.contains).toList();
    if (own.isEmpty) return 0;
    if (await deleteBatch(own, forEveryone: true)) return own.length;
    var deleted = 0;
    for (final id in own) {
      if (await deleteBatch([id], forEveryone: true)) deleted++;
    }
    return deleted;
  }
}
