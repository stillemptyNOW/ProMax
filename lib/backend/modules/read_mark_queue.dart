import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/protocol/opcode_map.dart';
import '../../core/protocol/packet.dart';
import '../../core/storage/token_storage.dart';
import '../../core/utils/logger.dart';
import '../api.dart';

@immutable
class ReadMark {
  const ReadMark({
    required this.accountId,
    required this.chatId,
    required this.messageId,
    required this.mark,
  });

  final int accountId;
  final int chatId;
  final int messageId;
  final int mark;

  (int, int) get chatKey => (accountId, chatId);

  Map<String, int> toJson() => {
    'a': accountId,
    'c': chatId,
    'm': messageId,
    't': mark,
  };

  static ReadMark? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final accountId = raw['a'];
    final chatId = raw['c'];
    final messageId = raw['m'];
    final mark = raw['t'];
    if (accountId is! int ||
        chatId is! int ||
        messageId is! int ||
        mark is! int) {
      return null;
    }
    return ReadMark(
      accountId: accountId,
      chatId: chatId,
      messageId: messageId,
      mark: mark,
    );
  }
}

class ReadMarkQueue {
  ReadMarkQueue();

  static final ReadMarkQueue instance = ReadMarkQueue();

  static const storageKey = 'promax_pending_read_marks_v1';

  final Map<(int, int), ReadMark> _pending = {};
  Api? _api;
  StreamSubscription<SessionState>? _stateSub;
  Future<void> _loaded = Future.value();
  Future<void> _saving = Future.value();
  bool _flushing = false;

  @visibleForTesting
  List<ReadMark> get pending => List.unmodifiable(_pending.values);

  void attach(Api api) {
    if (identical(_api, api)) return;
    _api = api;
    _stateSub?.cancel();
    _stateSub = api.stateStream
        .where((state) => state == SessionState.online)
        .listen((_) => unawaited(flush()));
    _loaded = _load();
  }

  @visibleForTesting
  Future<void> detach() async {
    await _stateSub?.cancel();
    _stateSub = null;
    _api = null;
    await _saving;
    _pending.clear();
  }

  Future<void> submit(Api api, ReadMark mark) async {
    attach(api);
    await _loaded;
    final queued = _pending[mark.chatKey];
    if (queued != null && queued.mark > mark.mark) return;
    _pending[mark.chatKey] = mark;
    _save();
    await _send(api, mark);
  }

  Future<void> flush() async {
    final api = _api;
    if (api == null || _flushing) return;
    await _loaded;
    if (api.state != SessionState.online) return;
    _flushing = true;
    try {
      final accountId = await TokenStorage.getActiveAccountId();
      final due = [
        for (final mark in _pending.values)
          if (mark.accountId == accountId) mark,
      ];
      for (final mark in due) {
        if (api.state != SessionState.online) return;
        await _send(api, mark);
      }
    } finally {
      _flushing = false;
    }
  }

  Future<void> _send(Api api, ReadMark mark) async {
    try {
      await api.sendRequest(Opcode.chatMark, {
        'type': 'READ_MESSAGE',
        'chatId': mark.chatId,
        'messageId': mark.messageId,
        'mark': mark.mark,
      }, silent: true);
      _settle(mark);
    } on SessionExpiredException {
      return;
    } catch (e) {
      if (isPermanentSendFailure(e)) {
        logger.w('Отметка прочтения ${mark.chatId} отклонена: $e');
        _settle(mark);
      }
    }
  }

  void _settle(ReadMark mark) {
    final queued = _pending[mark.chatKey];
    if (queued == null || queued.mark > mark.mark) return;
    _pending.remove(mark.chatKey);
    _save();
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(storageKey);
      if (raw == null) return;
      final decoded = jsonDecode(raw);
      if (decoded is! List) return;
      for (final mark in decoded.map(ReadMark.fromJson).whereType<ReadMark>()) {
        final existing = _pending[mark.chatKey];
        if (existing == null || existing.mark < mark.mark) {
          _pending[mark.chatKey] = mark;
        }
      }
    } catch (e) {
      logger.w('Очередь отметок прочтения не прочиталась: $e');
    }
  }

  void _save() {
    final snapshot = jsonEncode([
      for (final mark in _pending.values) mark.toJson(),
    ]);
    final empty = _pending.isEmpty;
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
}
