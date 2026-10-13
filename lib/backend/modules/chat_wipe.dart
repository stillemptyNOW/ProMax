import 'dart:math' as math;

import 'messages.dart';
import 'server_outcome.dart';

typedef WipeHistoryPage =
    Future<List<CachedMessage>> Function(int? fromTime, int count);
typedef WipeDeleteBatch =
    Future<ServerOutcome> Function(
      List<String> ids, {
      required bool forEveryone,
    });
typedef WipeChatAction = Future<ServerOutcome> Function(int seenEventTime);

class ChatWipeResult {
  const ChatWipeResult({
    required this.found,
    required this.ownForBoth,
    required this.peerForBoth,
    required this.onlyForMe,
    required this.deletedIds,
    required this.historyIncomplete,
    required this.unreachable,
    required this.chatRemoved,
    this.clearError,
    this.chatError,
  });

  final int found;
  final int ownForBoth;
  final int peerForBoth;
  final int onlyForMe;
  final List<String> deletedIds;
  final bool historyIncomplete;
  final bool unreachable;
  final bool chatRemoved;
  final String? clearError;
  final String? chatError;

  int get deletedForBoth => ownForBoth + peerForBoth;

  int get notDeleted => found - deletedForBoth - onlyForMe;

  bool get complete =>
      chatRemoved &&
      !historyIncomplete &&
      onlyForMe == 0 &&
      notDeleted == 0 &&
      clearError == null;
}

class ChatWipe {
  static const int pageSize = 100;
  static const int batchSize = 100;
  static const int maxPages = 2000;

  static Future<ChatWipeResult> run({
    required int myId,
    required WipeHistoryPage fetchPage,
    required WipeDeleteBatch deleteBatch,
    required WipeChatAction clearForAll,
    required WipeChatAction deleteChatForAll,
    void Function(int scanned, int deleted)? onProgress,
  }) async {
    final wipe = _Wipe(deleteBatch, onProgress);
    final scan = await _scan(myId, fetchPage, wipe, onProgress);

    wipe.total = scan.own.length + scan.peer.length;
    await wipe.deleteOwn(scan.own);
    await wipe.deletePeer(scan.peer);

    String? clearError;
    String? chatError;
    var chatRemoved = false;
    if (!wipe.unreachable) {
      switch (await _guard(() => clearForAll(scan.newest))) {
        case ServerDone():
          break;
        case ServerRejected(:final message):
          clearError = message;
        case ServerUnreachable():
          wipe.unreachable = true;
      }
    }
    if (!wipe.unreachable) {
      switch (await _guard(() => deleteChatForAll(scan.newest))) {
        case ServerDone():
          chatRemoved = true;
        case ServerRejected(:final message):
          chatError = message;
        case ServerUnreachable():
          wipe.unreachable = true;
      }
    }

    return ChatWipeResult(
      found: scan.own.length + scan.peer.length,
      ownForBoth: scan.own.where(wipe.forBoth.contains).length,
      peerForBoth: scan.peer.where(wipe.forBoth.contains).length,
      onlyForMe: wipe.forMe.length,
      deletedIds: [...wipe.forBoth, ...wipe.forMe],
      historyIncomplete: scan.incomplete,
      unreachable: wipe.unreachable,
      chatRemoved: chatRemoved,
      clearError: clearError,
      chatError: chatError,
    );
  }

  static Future<
    ({List<String> own, List<String> peer, int newest, bool incomplete})
  >
  _scan(
    int myId,
    WipeHistoryPage fetchPage,
    _Wipe wipe,
    void Function(int scanned, int deleted)? onProgress,
  ) async {
    final seen = <String>{};
    final own = <String>[];
    final peer = <String>[];
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
        (message.senderId == myId ? own : peer).add(message.id);
      }
      onProgress?.call(own.length + peer.length, 0);
      if (added == 0 || oldest == null) break;
      cursor = oldest;
    }
    return (own: own, peer: peer, newest: newest, incomplete: incomplete);
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
  _Wipe(this._deleteBatch, this._onProgress);

  final WipeDeleteBatch _deleteBatch;
  final void Function(int scanned, int deleted)? _onProgress;
  final Set<String> forBoth = {};
  final Set<String> forMe = {};
  int total = 0;
  int _chunkSize = ChatWipe.batchSize;
  bool? _peerForBothAllowed;
  bool unreachable = false;

  Future<void> deleteOwn(List<String> ids) async {
    final refused = await _deleteAll(ids, forEveryone: true);
    await _deleteAll(refused, forEveryone: false);
  }

  Future<void> deletePeer(List<String> ids) async {
    final refused = <String>[];
    for (final chunk in _chunks(ids)) {
      if (unreachable) return;
      refused.addAll(await _deletePeerChunk(chunk));
    }
    await _deleteAll(refused, forEveryone: false);
  }

  Future<List<String>> _deletePeerChunk(List<String> chunk) async {
    if (_peerForBothAllowed == false) return chunk;
    if (_peerForBothAllowed == true) {
      return _deleteChunk(chunk, forEveryone: true);
    }
    final probe = await _deleteChunk([chunk.first], forEveryone: true);
    if (unreachable) return const [];
    if (probe.isNotEmpty) {
      _peerForBothAllowed = false;
      return chunk;
    }
    _peerForBothAllowed = true;
    if (chunk.length == 1) return const [];
    return _deleteChunk(chunk.sublist(1), forEveryone: true);
  }

  Future<List<String>> _deleteAll(
    List<String> ids, {
    required bool forEveryone,
  }) async {
    final refused = <String>[];
    for (final chunk in _chunks(ids)) {
      if (unreachable) break;
      refused.addAll(await _deleteChunk(chunk, forEveryone: forEveryone));
    }
    return refused;
  }

  Iterable<List<String>> _chunks(List<String> ids) sync* {
    var start = 0;
    while (start < ids.length) {
      final end = math.min(start + _chunkSize, ids.length);
      yield ids.sublist(start, end);
      start = end;
    }
  }

  Future<List<String>> _deleteChunk(
    List<String> chunk, {
    required bool forEveryone,
  }) async {
    if (unreachable || chunk.isEmpty) return const [];
    final ServerOutcome outcome;
    try {
      outcome = await _deleteBatch(chunk, forEveryone: forEveryone);
    } catch (e) {
      return _settle(chunk, outcomeOfError(e), forEveryone: forEveryone);
    }
    return _settle(chunk, outcome, forEveryone: forEveryone);
  }

  Future<List<String>> _settle(
    List<String> chunk,
    ServerOutcome outcome, {
    required bool forEveryone,
  }) async {
    switch (outcome) {
      case ServerDone():
        _record(chunk, forEveryone: forEveryone);
        return const [];
      case ServerUnreachable():
        unreachable = true;
        return const [];
      case ServerRejected(:final notFound) when chunk.length == 1:
        if (notFound) {
          _record(chunk, forEveryone: forEveryone);
          return const [];
        }
        return chunk;
      case ServerRejected():
        final half = chunk.length ~/ 2;
        final refused = [
          ...await _deleteChunk(
            chunk.sublist(0, half),
            forEveryone: forEveryone,
          ),
          ...await _deleteChunk(chunk.sublist(half), forEveryone: forEveryone),
        ];
        if (refused.isEmpty && !unreachable) {
          _chunkSize = math.max(1, math.min(_chunkSize, half));
        }
        return refused;
    }
  }

  void _record(List<String> ids, {required bool forEveryone}) {
    (forEveryone ? forBoth : forMe).addAll(ids);
    _onProgress?.call(total, forBoth.length + forMe.length);
  }
}
