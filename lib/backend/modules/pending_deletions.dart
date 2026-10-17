import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/utils/logger.dart';
import 'chat_deletion_plan.dart';
import 'messages.dart';
import 'server_outcome.dart';

enum PendingDeletionKind { messages, deleteChat, leaveChat }

typedef RestoredMessages = ({
  int accountId,
  int chatId,
  List<CachedMessage> messages,
});

typedef DeletionPart = ({
  List<CachedMessage> messages,
  bool forEveryone,
  bool fallbackToSelf,
});

@immutable
class PendingDeletion {
  const PendingDeletion({
    required this.key,
    required this.accountId,
    required this.chatId,
    required this.kind,
    this.messageIds = const [],
    this.forEveryone = false,
    this.fallbackToSelf = false,
    this.historyErased = false,
    this.attempts = 0,
  });

  final String key;
  final int accountId;
  final int chatId;
  final PendingDeletionKind kind;
  final List<String> messageIds;
  final bool forEveryone;
  final bool fallbackToSelf;
  final bool historyErased;
  final int attempts;

  bool get isChat => kind != PendingDeletionKind.messages;

  List<String> get serverMessageIds => [
    for (final id in messageIds)
      if (int.tryParse(id) != null) id,
  ];

  PendingDeletion retried({bool historyErased = false}) => PendingDeletion(
    key: key,
    accountId: accountId,
    chatId: chatId,
    kind: kind,
    messageIds: messageIds,
    forEveryone: forEveryone,
    fallbackToSelf: fallbackToSelf,
    historyErased: this.historyErased || historyErased,
    attempts: attempts + 1,
  );

  Map<String, Object> toJson() => {
    'k': key,
    'a': accountId,
    'c': chatId,
    't': kind.name,
    'm': messageIds,
    'e': forEveryone,
    'f': fallbackToSelf,
    'h': historyErased,
    'n': attempts,
  };

  static PendingDeletion? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final key = raw['k'];
    final accountId = raw['a'];
    final chatId = raw['c'];
    final kindName = raw['t'];
    final ids = raw['m'];
    if (key is! String || accountId is! int || chatId is! int) return null;
    final kind = PendingDeletionKind.values
        .where((k) => k.name == kindName)
        .firstOrNull;
    if (kind == null) return null;
    final messageIds = ids is List
        ? ids.whereType<String>().toList(growable: false)
        : const <String>[];
    if (kind == PendingDeletionKind.messages && messageIds.isEmpty) {
      return null;
    }
    final attempts = raw['n'];
    return PendingDeletion(
      key: key,
      accountId: accountId,
      chatId: chatId,
      kind: kind,
      messageIds: messageIds,
      forEveryone: raw['e'] == true,
      fallbackToSelf: raw['f'] == true,
      historyErased: raw['h'] == true,
      attempts: attempts is int ? attempts : 0,
    );
  }
}

sealed class PendingDeletionReport {
  const PendingDeletionReport();
}

final class PendingDeletionFailed extends PendingDeletionReport {
  const PendingDeletionFailed(this.kind, this.count, this.message);

  final PendingDeletionKind kind;
  final int count;
  final String message;
}

final class PendingDeletionErasedOnly extends PendingDeletionReport {
  const PendingDeletionErasedOnly(this.message);

  final String message;
}

final class PendingDeletionChatTypeUnknown extends PendingDeletionReport {
  const PendingDeletionChatTypeUnknown();
}

final class PendingDeletionStalled extends PendingDeletionReport {
  const PendingDeletionStalled(this.kind, this.reason);

  final PendingDeletionKind kind;
  final String reason;
}

final class PendingDeletionKeptForPeer extends PendingDeletionReport {
  const PendingDeletionKeptForPeer(this.count);

  final int count;
}

abstract interface class PendingDeletionGateway {
  bool get isOnline;
  int get sessionEpoch;
  Stream<void> get wentOnline;
  Future<int?> activeAccountId();
  Future<ServerOutcome> deleteMessages(
    int chatId,
    List<String> messageIds, {
    required bool forEveryone,
  });
  Future<ChatDeletionResult> deleteChat(
    int accountId,
    int chatId, {
    required bool forAll,
    required bool historyErased,
  });
  Future<ServerOutcome> leaveChat(int accountId, int chatId);
  Future<void> forgetMessages(int accountId, int chatId, List<String> ids);
  Future<List<CachedMessage>> loadMessages(
    int accountId,
    int chatId,
    List<String> ids,
  );
}

typedef _Sent = ({
  ServerOutcome outcome,
  int keptForPeer,
  bool historyErased,
  bool typeUnknown,
});

class PendingDeletions {
  PendingDeletions._();

  static final PendingDeletions instance = PendingDeletions._();

  static const storageKey = 'promax_pending_deletions_v1';
  static const List<Duration> retryDelays = [
    Duration(seconds: 5),
    Duration(seconds: 15),
    Duration(seconds: 30),
    Duration(seconds: 60),
  ];
  static const int stallReportAttempt = 2;

  final ValueNotifier<int> chatHolds = ValueNotifier(0);
  final Map<String, PendingDeletion> _entries = {};
  final Set<String> _open = {};
  final Map<String, Future<void>> _running = {};
  final Map<String, Map<String, CachedMessage>> _snapshots = {};
  final Map<(int, int), Set<String>> _heldMessages = {};
  final Set<(int, int)> _heldChats = {};
  final Set<String> _sendingCancelled = {};
  final StreamController<RestoredMessages> _restored =
      StreamController.broadcast(sync: true);
  final StreamController<PendingDeletionReport> _reports =
      StreamController.broadcast();
  final StreamController<void> _undoWindowsClosed = StreamController.broadcast(
    sync: true,
  );

  PendingDeletionGateway? _gateway;
  StreamSubscription<void>? _onlineSub;
  Timer? _retryTimer;
  int _retryRound = 0;
  bool _stallReported = false;
  Future<void> _saving = Future.value();
  int _keySeq = 0;

  Stream<RestoredMessages> get restored => _restored.stream;
  Stream<PendingDeletionReport> get reports => _reports.stream;
  Stream<void> get undoWindowsClosed => _undoWindowsClosed.stream;

  List<PendingDeletion> get entries => List.unmodifiable(_entries.values);

  bool get hasWork => _entries.isNotEmpty;

  Future<void> start(PendingDeletionGateway gateway) async {
    _gateway = gateway;
    final prefs = await SharedPreferences.getInstance();
    for (final entry in _decode(prefs.getString(storageKey))) {
      _entries.putIfAbsent(entry.key, () => entry);
    }
    _reindex();
    await _onlineSub?.cancel();
    _onlineSub = gateway.wentOnline.listen((_) => unawaited(flush()));
    unawaited(flush());
  }

  @visibleForTesting
  Future<void> stop() async {
    await _onlineSub?.cancel();
    _onlineSub = null;
    _retryTimer?.cancel();
    _retryTimer = null;
    _gateway = null;
    await Future.wait(_running.values);
    await _saving;
    _entries.clear();
    _open.clear();
    _snapshots.clear();
    _sendingCancelled.clear();
    _retryRound = 0;
    _stallReported = false;
    _reindex();
  }

  bool isMessageHeld(int accountId, int chatId, String messageId) =>
      _heldMessages[(accountId, chatId)]?.contains(messageId) ?? false;

  bool isChatHeld(int chatId, {Set<int>? accounts}) {
    if (accounts == null || accounts.isEmpty) {
      return _heldChats.any((held) => held.$2 == chatId);
    }
    return accounts.any((account) => _heldChats.contains((account, chatId)));
  }

  List<String> holdMessages({
    required int accountId,
    required int chatId,
    required List<DeletionPart> parts,
  }) {
    final keys = <String>[];
    for (final part in parts) {
      final messages = [
        for (final message in part.messages)
          if (int.tryParse(message.id) != null) message,
      ];
      if (messages.isEmpty) continue;
      final entry = PendingDeletion(
        key: _nextKey(),
        accountId: accountId,
        chatId: chatId,
        kind: PendingDeletionKind.messages,
        messageIds: [for (final message in messages) message.id],
        forEveryone: part.forEveryone,
        fallbackToSelf: part.forEveryone && part.fallbackToSelf,
      );
      _entries[entry.key] = entry;
      _open.add(entry.key);
      _snapshots[entry.key] = {
        for (final message in messages) message.id: message,
      };
      keys.add(entry.key);
    }
    if (keys.isNotEmpty) _changed();
    return keys;
  }

  String holdChat({
    required int accountId,
    required int chatId,
    required PendingDeletionKind kind,
    bool forAll = false,
  }) {
    assert(kind != PendingDeletionKind.messages);
    final entry = PendingDeletion(
      key: _nextKey(),
      accountId: accountId,
      chatId: chatId,
      kind: kind,
      forEveryone: forAll,
    );
    _entries[entry.key] = entry;
    _open.add(entry.key);
    _changed();
    return entry.key;
  }

  bool cancel(Iterable<String> keys) {
    final cancelled = <PendingDeletion>[];
    for (final key in keys) {
      if (!_open.remove(key)) continue;
      final entry = _entries.remove(key);
      if (entry != null) cancelled.add(entry);
    }
    if (cancelled.isEmpty) return false;
    _changed();
    for (final entry in cancelled) {
      final snapshot = _snapshots.remove(entry.key);
      if (snapshot != null && snapshot.isNotEmpty) {
        _restored.add((
          accountId: entry.accountId,
          chatId: entry.chatId,
          messages: snapshot.values.toList(),
        ));
      }
    }
    return true;
  }

  void commit(Iterable<String> keys) {
    final committed = [
      for (final key in keys)
        if (_open.remove(key)) key,
    ];
    for (final key in committed) {
      final entry = _entries[key];
      if (entry != null) unawaited(_process(entry));
    }
  }

  void closeUndoWindows() {
    if (_open.isEmpty) return;
    _open.clear();
    _undoWindowsClosed.add(null);
  }

  void cancelSending(int accountId, int chatId, Iterable<String> tempIds) {
    for (final id in tempIds) {
      if (int.tryParse(id) == null) {
        _sendingCancelled.add(_sendingKey(accountId, chatId, id));
      }
    }
  }

  bool claimSent({
    required int accountId,
    required int chatId,
    required String tempId,
    required String realId,
  }) {
    if (!_sendingCancelled.remove(_sendingKey(accountId, chatId, tempId))) {
      return false;
    }
    final entry = PendingDeletion(
      key: _nextKey(),
      accountId: accountId,
      chatId: chatId,
      kind: PendingDeletionKind.messages,
      messageIds: [if (realId.isNotEmpty) realId, if (realId != tempId) tempId],
      forEveryone: true,
    );
    _entries[entry.key] = entry;
    _changed();
    unawaited(_process(entry));
    return true;
  }

  Future<void> flush({Duration? timeout, bool closeUndoWindows = false}) async {
    if (closeUndoWindows) this.closeUndoWindows();
    final work = _flushActiveAccount();
    if (timeout == null) return work;
    await work.timeout(timeout, onTimeout: () {});
  }

  Future<void> settleBeforeAccountChange({
    Duration timeout = const Duration(seconds: 4),
  }) async {
    await flush(timeout: timeout, closeUndoWindows: true);
    _sendingCancelled.clear();
  }

  void forgetAccount(int accountId) {
    final keys = [
      for (final entry in _entries.values)
        if (entry.accountId == accountId) entry.key,
    ];
    if (keys.isEmpty) return;
    for (final key in keys) {
      _entries.remove(key);
      _open.remove(key);
      _snapshots.remove(key);
    }
    _sendingCancelled.removeWhere((key) => key.startsWith('$accountId:'));
    _changed();
  }

  Future<void> _flushActiveAccount() async {
    final gateway = _gateway;
    if (gateway == null || !gateway.isOnline) {
      await Future.wait(_running.values);
      return;
    }
    final accountId = await gateway.activeAccountId();
    if (accountId == null) return;
    final due = [
      for (final entry in _entries.values)
        if (entry.accountId == accountId && !_open.contains(entry.key)) entry,
    ];
    for (final entry in due) {
      await _process(entry);
    }
    await Future.wait(_running.values);
  }

  Future<void> _process(PendingDeletion entry) {
    final key = entry.key;
    final running = _running[key];
    if (running != null) return running;
    final work = _execute(key);
    _running[key] = work;
    return work.whenComplete(() => _running.remove(key));
  }

  Future<bool> _owns(PendingDeletionGateway gateway, int accountId) async {
    if (!gateway.isOnline) return false;
    final epoch = gateway.sessionEpoch;
    final active = await gateway.activeAccountId();
    return gateway.isOnline &&
        gateway.sessionEpoch == epoch &&
        active == accountId;
  }

  Future<void> _execute(String key) async {
    try {
      await _attempt(key);
    } catch (e) {
      logger.w('PendingDeletions: $key не отправлено: $e');
      _scheduleRetry();
    }
  }

  Future<void> _attempt(String key) async {
    final gateway = _gateway;
    final initial = _entries[key];
    if (gateway == null || initial == null || _open.contains(key)) return;
    if (!await _owns(gateway, initial.accountId)) return;
    final entry = _entries[key];
    if (entry == null || _open.contains(key)) return;

    final sent = await _send(gateway, entry);
    switch (sent.outcome) {
      case ServerDone():
        await _complete(gateway, entry, keptForPeer: sent.keptForPeer);
      case ServerRejected(:final notFound)
          when notFound &&
              (entry.kind == PendingDeletionKind.messages ||
                  entry.attempts > 0):
        await _complete(gateway, entry, keptForPeer: sent.keptForPeer);
      case ServerRejected(:final message):
        await _reject(gateway, entry, _refusalReport(entry, sent, message));
      case ServerUnreachable(:final reason):
        final retried = entry.retried(historyErased: sent.historyErased);
        _entries[key] = retried;
        _save();
        _scheduleRetry();
        _reportStall(retried, reason);
    }
  }

  static PendingDeletionReport _refusalReport(
    PendingDeletion entry,
    _Sent sent,
    String message,
  ) {
    if (sent.typeUnknown) return const PendingDeletionChatTypeUnknown();
    if (sent.historyErased || entry.historyErased) {
      return PendingDeletionErasedOnly(message);
    }
    return PendingDeletionFailed(
      entry.kind,
      entry.kind == PendingDeletionKind.messages
          ? entry.serverMessageIds.length
          : 1,
      message,
    );
  }

  void _reportStall(PendingDeletion entry, String reason) {
    if (entry.attempts != stallReportAttempt || _stallReported) return;
    _stallReported = true;
    _reports.add(PendingDeletionStalled(entry.kind, reason));
  }

  Future<_Sent> _send(
    PendingDeletionGateway gateway,
    PendingDeletion entry,
  ) async => switch (entry.kind) {
    PendingDeletionKind.messages => await _sendMessages(gateway, entry),
    PendingDeletionKind.deleteChat => _sentChatDeletion(
      await gateway.deleteChat(
        entry.accountId,
        entry.chatId,
        forAll: entry.forEveryone,
        historyErased: entry.historyErased,
      ),
    ),
    PendingDeletionKind.leaveChat => _sent(
      await gateway.leaveChat(entry.accountId, entry.chatId),
    ),
  };

  static _Sent _sent(ServerOutcome outcome, {int keptForPeer = 0}) => (
    outcome: outcome,
    keptForPeer: keptForPeer,
    historyErased: false,
    typeUnknown: false,
  );

  static _Sent _sentChatDeletion(ChatDeletionResult result) => (
    outcome: result.outcome,
    keptForPeer: 0,
    historyErased: result.historyErased,
    typeUnknown: result.typeUnknown,
  );

  Future<_Sent> _sendMessages(
    PendingDeletionGateway gateway,
    PendingDeletion entry,
  ) async {
    final outcome = await gateway.deleteMessages(
      entry.chatId,
      entry.messageIds,
      forEveryone: entry.forEveryone,
    );
    if (outcome is! ServerRejected ||
        outcome.notFound ||
        !entry.forEveryone ||
        !entry.fallbackToSelf) {
      return _sent(outcome);
    }
    final refused = <String>[];
    for (final id in entry.serverMessageIds) {
      final single = await gateway.deleteMessages(entry.chatId, [
        id,
      ], forEveryone: true);
      switch (single) {
        case ServerDone():
        case ServerRejected(notFound: true):
          break;
        case ServerRejected():
          refused.add(id);
        case ServerUnreachable():
          return _sent(single);
      }
    }
    if (refused.isEmpty) return _sent(const ServerDone());
    final mine = await gateway.deleteMessages(
      entry.chatId,
      refused,
      forEveryone: false,
    );
    return _sent(mine, keptForPeer: mine.ok ? refused.length : 0);
  }

  Future<void> _complete(
    PendingDeletionGateway gateway,
    PendingDeletion entry, {
    required int keptForPeer,
  }) async {
    if (entry.kind == PendingDeletionKind.messages) {
      try {
        await gateway.forgetMessages(
          entry.accountId,
          entry.chatId,
          entry.messageIds,
        );
      } catch (_) {}
    }
    _entries.remove(entry.key);
    _snapshots.remove(entry.key);
    _retryRound = 0;
    _stallReported = false;
    _changed();
    if (keptForPeer > 0) _reports.add(PendingDeletionKeptForPeer(keptForPeer));
  }

  Future<void> _reject(
    PendingDeletionGateway gateway,
    PendingDeletion entry,
    PendingDeletionReport report,
  ) async {
    _entries.remove(entry.key);
    _stallReported = false;
    final snapshot = _snapshots.remove(entry.key);
    var restored = snapshot?.values.toList() ?? const <CachedMessage>[];
    if (entry.kind == PendingDeletionKind.messages && restored.isEmpty) {
      try {
        restored = await gateway.loadMessages(
          entry.accountId,
          entry.chatId,
          entry.messageIds,
        );
      } catch (_) {}
    }
    _changed();
    if (restored.isNotEmpty) {
      _restored.add((
        accountId: entry.accountId,
        chatId: entry.chatId,
        messages: restored,
      ));
    }
    _reports.add(report);
  }

  void _scheduleRetry() {
    if (_retryTimer?.isActive ?? false) return;
    final delay =
        retryDelays[_retryRound.clamp(0, retryDelays.length - 1).toInt()];
    _retryRound++;
    _retryTimer = Timer(delay, () => unawaited(flush()));
  }

  void _changed() {
    _reindex();
    _save();
  }

  void _reindex() {
    final previousChats = Set.of(_heldChats);
    _heldMessages.clear();
    _heldChats.clear();
    for (final entry in _entries.values) {
      if (entry.isChat) {
        _heldChats.add((entry.accountId, entry.chatId));
      } else {
        _heldMessages
            .putIfAbsent((entry.accountId, entry.chatId), () => {})
            .addAll(entry.messageIds);
      }
    }
    if (!setEquals(previousChats, _heldChats)) chatHolds.value++;
  }

  void _save() {
    final snapshot = jsonEncode([
      for (final entry in _entries.values) entry.toJson(),
    ]);
    final empty = _entries.isEmpty;
    _saving = _saving.then((_) async {
      try {
        final prefs = await SharedPreferences.getInstance();
        if (empty) {
          await prefs.remove(storageKey);
        } else {
          await prefs.setString(storageKey, snapshot);
        }
      } catch (_) {}
    });
  }

  String _nextKey() => '${DateTime.now().microsecondsSinceEpoch}-${_keySeq++}';

  static String _sendingKey(int accountId, int chatId, String tempId) =>
      '$accountId:$chatId:$tempId';

  static List<PendingDeletion> _decode(String? raw) {
    if (raw == null) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return decoded
          .map(PendingDeletion.fromJson)
          .whereType<PendingDeletion>()
          .toList();
    } catch (_) {
      return const [];
    }
  }
}
