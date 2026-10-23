import 'dart:math' as math;

import 'messages.dart';
import 'server_outcome.dart';

typedef WipeHistoryPage =
    Future<List<CachedMessage>> Function(int? fromTime, int count);
typedef WipeDeleteForEveryone =
    Future<MessageDeletionReply> Function(List<String> ids);
typedef WipeRemoveChat = Future<ServerOutcome> Function(int seenEventTime);

class ChatWipeResult {
  const ChatWipeResult({
    required this.found,
    required this.eligible,
    required this.deletedIds,
    required this.notConfirmed,
    required this.historyIncomplete,
    required this.unreachable,
    required this.removeForAll,
    required this.chatRemoved,
    this.chatError,
  });

  final int found;
  final int eligible;
  final List<String> deletedIds;
  final int notConfirmed;
  final bool historyIncomplete;
  final bool unreachable;
  final bool removeForAll;
  final bool chatRemoved;
  final String? chatError;

  int get deletedForPeer => deletedIds.length;

  int get keptForPeer => found - eligible;

  bool get complete =>
      chatRemoved && !historyIncomplete && !unreachable && notConfirmed == 0;
}

class ChatWipe {
  static const int pageSize = 100;
  static const int batchSize = 100;
  static const int maxPages = 2000;

  static Future<ChatWipeResult> run({
    required WipeHistoryPage fetchPage,
    required bool Function(CachedMessage message) deletableForEveryone,
    required WipeDeleteForEveryone deleteForEveryone,
    required WipeRemoveChat removeChat,
    required bool removeForAll,
    void Function(int total, int deleted)? onProgress,
  }) async {
    final wipe = _Wipe(deleteForEveryone, onProgress);
    final scan = await _scan(fetchPage, wipe, onProgress);
    final eligible = [
      for (final message in scan.messages)
        if (deletableForEveryone(message)) message.id,
    ];

    wipe.total = eligible.length;
    await wipe.deleteAll(eligible);

    String? chatError;
    var chatRemoved = false;
    if (!wipe.unreachable) {
      switch (await _guard(() => removeChat(scan.newest))) {
        case ServerDone():
          chatRemoved = true;
        case ServerRejected(:final message):
          chatError = message;
        case ServerUnreachable():
          wipe.unreachable = true;
      }
    }

    return ChatWipeResult(
      found: scan.messages.length,
      eligible: eligible.length,
      deletedIds: wipe.deleted.toList(),
      notConfirmed: wipe.refused.length,
      historyIncomplete: scan.incomplete,
      unreachable: wipe.unreachable,
      removeForAll: removeForAll,
      chatRemoved: chatRemoved,
      chatError: chatError,
    );
  }

  static Future<({List<CachedMessage> messages, int newest, bool incomplete})>
  _scan(
    WipeHistoryPage fetchPage,
    _Wipe wipe,
    void Function(int total, int deleted)? onProgress,
  ) async {
    final seen = <String>{};
    final messages = <CachedMessage>[];
    var newest = 0;
    var incomplete = false;
    int? cursor;
    for (var page = 0; page < maxPages; page++) {
      final List<CachedMessage> batch;
      try {
        batch = await fetchPage(cursor, pageSize);
      } catch (e) {
        if (outcomeOfError(e) is ServerUnreachable) {
          wipe.unreachable = true;
        } else {
          incomplete = true;
        }
        break;
      }
      var oldest = cursor;
      var added = 0;
      for (final message in batch) {
        if (oldest == null || message.time < oldest) oldest = message.time;
        if (message.time > newest) newest = message.time;
        if (!seen.add(message.id)) continue;
        added++;
        if (message.isControl || message.deleted) continue;
        messages.add(message);
      }
      onProgress?.call(messages.length, 0);
      if (added == 0 || oldest == null) break;
      cursor = oldest;
    }
    return (messages: messages, newest: newest, incomplete: incomplete);
  }

  static Future<ServerOutcome> _guard(
    Future<ServerOutcome> Function() action,
  ) async {
    try {
      return await action();
    } catch (e) {
      return outcomeOfError(e);
    }
  }
}

class _Wipe {
  _Wipe(this._delete, this._onProgress);

  final WipeDeleteForEveryone _delete;
  final void Function(int total, int deleted)? _onProgress;
  final Set<String> deleted = {};
  final Set<String> refused = {};
  int total = 0;
  int _chunkSize = ChatWipe.batchSize;
  bool unreachable = false;

  Future<void> deleteAll(List<String> ids) async {
    var start = 0;
    while (start < ids.length && !unreachable) {
      final end = math.min(start + _chunkSize, ids.length);
      await _deleteChunk(ids.sublist(start, end));
      start = end;
    }
  }

  Future<void> _deleteChunk(List<String> chunk) async {
    if (unreachable || chunk.isEmpty) return;
    MessageDeletionReply reply;
    try {
      reply = await _delete(chunk);
    } catch (e) {
      reply = MessageDeletionReply(outcomeOfError(e));
    }
    switch (reply.outcome) {
      case ServerDone():
        final unconfirmed = reply.unconfirmedOf(chunk);
        deleted.addAll(chunk.where((id) => !unconfirmed.contains(id)));
        refused.addAll(unconfirmed);
        _onProgress?.call(total, deleted.length);
      case ServerUnreachable():
        unreachable = true;
      case ServerRejected(:final notFound) when chunk.length == 1:
        (notFound ? deleted : refused).addAll(chunk);
        _onProgress?.call(total, deleted.length);
      case ServerRejected():
        final half = chunk.length ~/ 2;
        final refusedBefore = refused.length;
        await _deleteChunk(chunk.sublist(0, half));
        await _deleteChunk(chunk.sublist(half));
        if (refused.length == refusedBefore && !unreachable) {
          _chunkSize = math.max(1, math.min(_chunkSize, half));
        }
    }
  }
}
