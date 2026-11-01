import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../backend/api.dart';
import '../../frontend/widgets/max_link_nav.dart';
import '../../main.dart';
import '../storage/app_database.dart';
import '../storage/ignored_senders.dart';
import '../storage/token_storage.dart';
import '../utils/logger.dart';
import 'native_event_stream.dart';

// #***! открытие чата по тапу на уведомление
class NotificationBridge {
  NotificationBridge._();
  static final NotificationBridge instance = NotificationBridge._();

  static const _method = MethodChannel(
    'io.github.stillemptynow.promax/notifications',
  );
  static const _events = EventChannel(
    'io.github.stillemptynow.promax/notification_events',
  );
  static const _retryDelay = Duration(milliseconds: 300);
  static const _maxRetries = 100;

  // #***! стек открытых чатов, натив не уведомляет про то что на экране
  final List<int> _activeChats = [];

  bool _started = false;
  bool _ready = false;
  int _pendingChatId = 0;
  int _openingChatId = 0;
  int? _sentChatId;
  int _retriesLeft = 0;
  Timer? _retry;

  int get activeChatId => _activeChats.isEmpty ? 0 : _activeChats.last;

  @visibleForTesting
  bool debugNative = false;

  bool get _native {
    if (debugNative) return true;
    try {
      return Platform.isAndroid || Platform.isIOS;
    } catch (_) {
      return false;
    }
  }

  // #***! подписка на уведомления и сессию
  void init() {
    if (_started) return;
    _started = true;
    if (_native) {
      NativeEventStream(_events, 'NotificationBridge').listen(_onEvent);
    }
    api.stateStream.listen((state) {
      if (state == SessionState.online) _flushPending();
    });
  }

  void openChat(int chatId) => _onEvent(chatId);

  void markReady() {
    _ready = true;
    _flushPending();
  }

  // #***! запустили тапом по уведомлению, забираем чат который натив придержал
  Future<void> checkInitialChat() async {
    if (!_native) return;
    try {
      _onEvent(await _method.invokeMethod<dynamic>('consumeInitialChat'));
    } catch (e) {
      logger.w('NotificationBridge.checkInitialChat: $e');
    }
  }

  // #***! вошли в чат, говорим нативу чтоб не уведомлял
  Future<void> pushActiveChat(int chatId) async {
    if (chatId == 0) return;
    if (_openingChatId == chatId) _openingChatId = 0;
    _activeChats.add(chatId);
    if (_native) await _syncActiveChat();
  }

  Future<void> popActiveChat(int chatId) async {
    if (chatId == 0) return;
    final index = _activeChats.lastIndexOf(chatId);
    if (index < 0) return;
    _activeChats.removeAt(index);
    if (_native) await _syncActiveChat();
  }

  Future<void> cancelChat(int chatId) async {
    if (!_native || chatId == 0) return;
    try {
      await _method.invokeMethod<void>('cancelChat', {'chatId': chatId});
    } catch (e) {
      logger.w('NotificationBridge.cancelChat: $e');
    }
  }

  Future<void> pruneChat(int chatId, int seen) async {
    if (!_native || chatId == 0 || seen <= 0) return;
    try {
      await _method.invokeMethod<void>('pruneChat', {
        'chatId': chatId,
        'seen': seen,
      });
    } catch (e) {
      logger.w('NotificationBridge.pruneChat: $e');
    }
  }

  Future<void> dismissReadChats() async {
    if (!_native) return;
    final List<int> notified;
    try {
      notified =
          (await _method.invokeListMethod<int>('notifiedChats')) ?? const [];
    } catch (e) {
      logger.w('NotificationBridge.notifiedChats: $e');
      return;
    }
    if (notified.isEmpty) return;
    final accountId = await TokenStorage.getActiveAccountId();
    if (accountId == null) return;
    await IgnoredSenders.instance.load();
    for (final chatId in notified) {
      final rows = await AppDatabase.loadChat(accountId, chatId);
      if (rows.isEmpty) continue;
      final read = (rows.first['unread_count'] as int? ?? 0) == 0;
      final ignored =
          IgnoredSenders.instance.ignoredPeer(accountId, chatId) != null;
      if (read || ignored) await cancelChat(chatId);
    }
  }

  Future<void> onAppResumed() async {
    if (!_native) return;
    _sentChatId = null;
    await _syncActiveChat();
    final chatId = activeChatId;
    if (chatId != 0) await cancelChat(chatId);
  }

  Future<void> _syncActiveChat() async {
    final chatId = activeChatId;
    if (chatId == _sentChatId) return;
    _sentChatId = chatId;
    try {
      if (chatId != 0) {
        await _method.invokeMethod<void>('setActiveChat', {'chatId': chatId});
      } else {
        await _method.invokeMethod<void>('clearActiveChat');
      }
    } catch (e) {
      logger.w('NotificationBridge: активный чат не синхронизирован: $e');
    }
  }

  // #***! событие это просто id чата
  void _onEvent(Object? event) {
    final chatId = event is int ? event : int.tryParse(event?.toString() ?? '');
    if (chatId == null || chatId == 0) return;
    _pendingChatId = chatId;
    _retriesLeft = _maxRetries;
    _flushPending();
  }

  // #***! ждём дерево и сессию иначе ретраим, открытый чат не переоткрываем
  void _flushPending() {
    final chatId = _pendingChatId;
    if (chatId == 0) return;

    final context = ProMaxApp.overlayContext;
    if (!_ready || context == null || api.state != SessionState.online) {
      if (_retriesLeft <= 0) {
        _pendingChatId = 0;
        return;
      }
      _retriesLeft--;
      _retry ??= Timer(_retryDelay, () {
        _retry = null;
        _flushPending();
      });
      return;
    }

    _pendingChatId = 0;
    if (activeChatId == chatId || _openingChatId == chatId) return;
    _openingChatId = chatId;
    unawaited(
      openChatById(context, chatId).whenComplete(() {
        if (_openingChatId == chatId) _openingChatId = 0;
      }),
    );
  }
}
