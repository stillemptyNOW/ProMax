import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/protocol/packet.dart';
import '../../core/storage/app_database.dart';
import '../../core/storage/token_storage.dart';
import '../../core/utils/logger.dart';
import '../api.dart';
import 'chats.dart';
import 'messages.dart';
import 'pending_deletions.dart';

// #***! очередь неотправленных, досылает когда связь вернулась
class OutboxService {
  OutboxService._();

  static final OutboxService instance = OutboxService._();

  static const List<Duration> retryDelays = [
    Duration(seconds: 5),
    Duration(seconds: 15),
    Duration(seconds: 30),
    Duration(seconds: 60),
    Duration(seconds: 120),
  ];

  Api? _api;
  MessagesModule? _messages;
  bool _flushing = false;
  bool _flushRequested = false;
  Future<void> _recovery = Future.value();
  Timer? _retryTimer;
  int _retryRound = 0;

  @visibleForTesting
  bool get retryScheduled => _retryTimer?.isActive ?? false;

  Future<void> recoverInterruptedSends() {
    return _recovery = _recover();
  }

  Future<void> _recover() async {
    try {
      final rows = await AppDatabase.loadInterruptedSends();
      for (final row in rows) {
        final message = CachedMessage.fromDbRow(row);
        if (!message.id.startsWith('temp_')) continue;
        final textOnly =
            (message.attachments?.isEmpty ?? true) &&
            (message.text?.isNotEmpty ?? false);
        await AppDatabase.settleInterruptedSend(
          message.accountId,
          message.id,
          textOnly ? 'pending' : 'error',
        );
      }
    } catch (e) {
      logger.w('Outbox: незавершённые отправки не разобраны: $e');
    }
  }

  void scheduleRetry() {
    if (_retryTimer?.isActive ?? false) return;
    final delay =
        retryDelays[_retryRound.clamp(0, retryDelays.length - 1).toInt()];
    _retryRound++;
    _retryTimer = Timer(delay, () => unawaited(flush()));
  }

  void _settleRetries() {
    _retryRound = 0;
    _retryTimer?.cancel();
    _retryTimer = null;
  }

  Future<bool> retry(int accountId, int chatId, String messageId) async {
    final requeued = await AppDatabase.requeueUnsentMessage(
      accountId,
      chatId,
      messageId,
    );
    if (!requeued) return false;
    _retryRound = 0;
    unawaited(flush());
    return true;
  }

  // #***! подписка на сессию, онлайн значит пробуем разослать
  void init(Api api, MessagesModule messages) {
    if (_api != null) return;
    _api = api;
    _messages = messages;
    api.stateStream.listen((state) {
      if (state == SessionState.online) unawaited(flush());
    });
    if (api.state == SessionState.online) unawaited(flush());
  }

  // #***! _flushing от параллельного прохода
  Future<void> flush() async {
    if (_flushing) {
      _flushRequested = true;
      return;
    }
    final api = _api;
    final messages = _messages;
    if (api == null || messages == null) return;
    if (api.state != SessionState.online) return;

    _flushing = true;
    try {
      do {
        _flushRequested = false;
        await _flushSession(api, messages);
      } while (_flushRequested && api.state == SessionState.online);
    } finally {
      _flushing = false;
    }
  }

  bool _isCurrentSession(Api api, int epoch) =>
      api.state == SessionState.online && api.sessionEpoch == epoch;

  // #***! очередь принадлежит аккаунту, под которым поднята именно эта сессия
  Future<bool> _ownsSession(Api api, int epoch, int accountId) async {
    if (!_isCurrentSession(api, epoch)) return false;
    final activeAccountId = await TokenStorage.getActiveAccountId();
    return _isCurrentSession(api, epoch) && activeAccountId == accountId;
  }

  Future<void> _flushSession(Api api, MessagesModule messages) async {
    final epoch = api.sessionEpoch;
    await _recovery;
    var deferred = false;
    try {
      final accountId = await TokenStorage.getActiveAccountId();
      if (accountId == null || !_isCurrentSession(api, epoch)) return;

      // #***! берём из базы pending и шлём по очереди
      final rows = await AppDatabase.loadPendingMessages(accountId);
      for (final row in rows) {
        if (!await _ownsSession(api, epoch, accountId)) return;
        final pending = CachedMessage.fromDbRow(row);
        final text = pending.text;
        if (text == null || text.isEmpty) continue;

        final payload = await _withClientId(pending);
        final replyToMessageId = _replyIdFromPayload(payload);
        final replySourceChatId = _replySourceChatIdFromPayload(payload);
        final elements = _elementsFromPayload(payload);

        try {
          final actualId = await messages.sendMessage(
            accountId,
            pending.chatId,
            text,
            replyToMessageId: replyToMessageId,
            replySourceChatId: replySourceChatId,
            elements: elements,
            cid: MessagesModule.clientIdOf(payload),
          );
          if (PendingDeletions.instance.claimSent(
            accountId: accountId,
            chatId: pending.chatId,
            tempId: pending.id,
            realId: actualId,
          )) {
            await AppDatabase.deleteMessage(
              accountId,
              pending.chatId,
              pending.id,
            );
            continue;
          }
          // #***! отправилось, сервер дал настоящий id а временный удаляем
          // #***! sealedText не терять, ключ потрачен и текста больше нигде нет
          final sent = CachedMessage(
            id: actualId.isNotEmpty ? actualId : pending.id,
            accountId: accountId,
            chatId: pending.chatId,
            senderId: accountId,
            text: text,
            time: pending.time,
            status: 'sent',
            payload: payload,
            sealedText: pending.sealedText,
            e2ee: pending.e2ee,
          );
          await AppDatabase.saveMessages([sent.toDbRow()]);
          if (sent.id != pending.id) {
            await AppDatabase.deleteMessage(
              accountId,
              pending.chatId,
              pending.id,
            );
          }
          if (!await _ownsSession(api, epoch, accountId)) return;
          chats.emitMessageSent(pending.chatId, pending.id, sent);
          await chats.applyOutgoing(
            accountId,
            pending.chatId,
            messageId: sent.id,
            time: sent.time,
            text: text,
            status: 'sent',
            elements: elements.isEmpty ? null : elements,
          );
          // #***! временную ошибку оставляем в очереди, окончательную помечаем и не трогаем
        } catch (e) {
          if (!await _ownsSession(api, epoch, accountId)) return;
          if (!isPermanentSendFailure(e)) {
            logger.w('Outbox: отправка ${pending.id} не удалась: $e');
            deferred = true;
            continue;
          }
          logger.w('Outbox: ${pending.id} отклонено сервером: $e');
          final failed = pending.copyWith(status: 'error');
          await AppDatabase.saveMessages([failed.toDbRow()]);
          if (!await _ownsSession(api, epoch, accountId)) return;
          chats.emitMessageSent(pending.chatId, pending.id, failed);
          await chats.applyOutgoing(
            accountId,
            pending.chatId,
            messageId: failed.id,
            time: failed.time,
            text: text,
            status: 'error',
            elements: elements.isEmpty ? null : elements,
          );
        }
      }
    } catch (e) {
      logger.e('Outbox flush: $e');
      deferred = true;
    }
    if (deferred) {
      scheduleRetry();
    } else if (_isCurrentSession(api, epoch)) {
      _settleRetries();
    }
  }

  Future<Map<String, dynamic>> _withClientId(CachedMessage pending) async {
    final payload = {...?pending.payload};
    if (MessagesModule.clientIdOf(payload) != null) return payload;
    payload['cid'] = MessagesModule.newClientId();
    await AppDatabase.updateMessagePayload(
      pending.accountId,
      pending.chatId,
      pending.id,
      payload,
    );
    return payload;
  }

  // #***! детали и форматирование в сыром payload, вытаскиваем при переотправке
  int? _replyIdFromPayload(Map<String, dynamic>? payload) {
    if (payload == null) return null;
    final link = payload['link'];
    if (link is! Map) return null;
    if ((link['type'] as String?)?.toUpperCase() != 'REPLY') return null;
    final msg = link['message'];
    if (msg is Map) {
      final id = msg['id'];
      if (id is int) return id;
      if (id != null) return int.tryParse(id.toString());
    }
    final mid = link['messageId'];
    if (mid is int) return mid;
    if (mid != null) return int.tryParse(mid.toString());
    return null;
  }

  int? _replySourceChatIdFromPayload(Map<String, dynamic>? payload) {
    if (payload == null) return null;
    final link = payload['link'];
    if (link is! Map) return null;
    if ((link['type'] as String?)?.toUpperCase() != 'REPLY') return null;
    final chatId = link['chatId'];
    if (chatId is int) return chatId;
    if (chatId != null) return int.tryParse(chatId.toString());
    return null;
  }

  List<Map<String, dynamic>> _elementsFromPayload(
    Map<String, dynamic>? payload,
  ) {
    final raw = payload?['elements'];
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }
}
