import 'dart:async';

import 'package:flutter/foundation.dart';

import '../security/double_bottom.dart';
import '../../backend/api.dart';
import '../../backend/modules/account/account_models.dart';
import '../../backend/modules/messages.dart';
import '../../core/protocol/opcode_map.dart';
import '../../core/protocol/packet.dart';
import '../calls/call_kit.dart';
import '../../core/storage/app_database.dart';
import '../../core/storage/token_storage.dart';
import '../config/promax_settings.dart';
import '../utils/logger.dart';
import 'fkm_bridge.dart';
import 'notification_policy.dart';
import 'quiet_hours.dart';
import 'push_service.dart';

// #***! FKM, своё фоновое уведомление для флейвора без гугла
/// FKM — уведомления через собственное фоновое соединение, без FCM.
///
/// Пуш из сокета превращается в тот же набор полей, что присылает FCM, и
/// отрисовывается нативным `ProMaxNotifier` — общий код с пушевой версией.
class FkmController {
  FkmController._();
  static final FkmController instance = FkmController._();

  // #***! enabled, на него подписан переключатель в настройках
  final ValueNotifier<bool> enabled = ValueNotifier(false);

  Api? _api;
  StreamSubscription<Packet>? _pushSub;
  StreamSubscription<SessionState>? _stateSub;
  bool _started = false;

  bool get isSupported => FkmBridge.instance.isSupported;

  // #***! подписка на пуши сокета и сессию
  Future<void> init(Api api) async {
    if (_started || !isSupported) return;
    _started = true;
    _api = api;

    FkmBridge.instance.setDisabledCallback(_onDisabledFromNotification);
    enabled.value = await FkmBridge.instance.isEnabled();
    Api.keepAliveInBackground = enabled.value;

    _pushSub = api.pushStream
        .where(
          (packet) =>
              packet.opcode == Opcode.notifMessage ||
              packet.opcode == Opcode.notifMsgDelete,
        )
        .listen(_onPush);
    _stateSub = api.stateStream.listen(_onSessionState);

    if (enabled.value) {
      await initLocalNotificationActions();
      await FkmBridge.instance.setEnabled(true);
      await _pushConnectionState();
    }
  }

  // #***! включение и выключение сервиса
  /// Возвращает false, если пользователь не выдал разрешение на уведомления.
  Future<bool> setEnabled(bool value) async {
    if (!isSupported) return false;
    if (value && !await FkmBridge.instance.requestNotificationPermission()) {
      return false;
    }
    if (value) await initLocalNotificationActions();
    await FkmBridge.instance.setEnabled(value);
    enabled.value = value;
    Api.keepAliveInBackground = value;
    if (value) await _pushConnectionState();
    return true;
  }

  // #***! выключили FKM кнопкой в уведомлении
  void _onDisabledFromNotification() {
    enabled.value = false;
    Api.keepAliveInBackground = false;
  }

  void _onSessionState(SessionState state) {
    if (!enabled.value) return;
    unawaited(FkmBridge.instance.setConnected(state == SessionState.online));
  }

  // #***! говорим нативу есть ли связь, от этого текст постоянного уведомления
  Future<void> _pushConnectionState() =>
      FkmBridge.instance.setConnected(_api?.state == SessionState.online);

  // #***! входящий звонок, натив рисует полноэкранное
  /// Входящий звонок, когда приложение не на переднем плане.
  ///
  /// Отдаётся тому же нативному коду, что и FCM-пуш: CallStyle, полноэкранный
  /// интент, рингтон, приём и отклонение уже реализованы там.
  Future<void> showIncomingCall(Map<dynamic, dynamic> payload) async {
    if (!enabled.value) return;
    try {
      final data = await _buildCallNotification(payload);
      if (data == null) return;
      if (await CallKitBridge.instance.reportIncoming(data)) return;
      await FkmBridge.instance.showCall(_withFallbackSender(data));
    } catch (e) {
      logger.w('FKM: не удалось показать звонок: $e');
    }
  }

  Future<Map<String, String>?> _buildCallNotification(
    Map<dynamic, dynamic> payload,
  ) async {
    final vcp = payload['vcp'];
    final conversationId = payload['conversationId'];
    final callerId = payload['callerId'];
    if (vcp is! String || conversationId is! String || callerId is! int) {
      return null;
    }

    final accountId = await TokenStorage.getActiveAccountId();
    if (accountId == null) return null;

    final rawConfig = await AppDatabase.getPrivacyConfig(accountId);
    if (!NotificationPolicy.callsEnabled(
      rawConfig == null ? null : PrivacyConfig.fromJson(rawConfig),
    )) {
      return null;
    }

    final name = ContactCache.get(callerId);

    return {
      'type': 'InboundCall',
      'vcp': vcp,
      'conversationId': conversationId,
      'callerId': '$callerId',
      'suid': '$callerId',
      'userName': ?name,
      'title': ?name,
      'c': '$accountId',
      'iv': payload['type'] == 'VIDEO' ? 'true' : 'false',
    };
  }

  Map<String, String> _withFallbackSender(Map<String, String> data) => {
    'userName': NotificationPolicy.fallbackSender,
    'title': NotificationPolicy.fallbackSender,
    ...data,
  };

  // #***! роутер пушей, новое правка удаление
  Future<void> _onPush(Packet packet) async {
    if (!enabled.value) return;
    try {
      if (packet.opcode == Opcode.notifMsgDelete) {
        await _onDeletePush(packet);
      } else {
        await _onMessagePush(packet);
      }
    } catch (e) {
      logger.w('FKM: не удалось обновить уведомления: $e');
    }
  }

  // #***! новое сообщение в уведомление
  Future<void> _onMessagePush(Packet packet) async {
    final push = NotificationPolicy.parseMessage(
      packet.payload,
      isHiddenChat: DoubleBottom.hides,
    );
    if (push == null) return;
    final chatId = push.chatId;
    final msgId = push.messageId;
    switch (push.kind) {
      case MessagePushKind.removed:
        if (msgId != null) await _removeNotification(chatId, msgId);
        return;
      case MessagePushKind.edited:
        if (msgId != null) await _editNotification(chatId, msgId, push.message);
        return;
      case MessagePushKind.created:
        break;
    }

    final accountId = await TokenStorage.getActiveAccountId();
    if (NotificationPolicy.isOwn(push, accountId)) {
      await PushService.clearChatNotification(chatId);
      return;
    }
    if (QuietHours.instance.isQuiet(chatId)) return;

    final facts = await NotificationFacts.load(chatId, senderId: push.senderId);
    if (facts == null) return;
    final notification = NotificationPolicy.compose(push, facts);
    if (notification != null) {
      await FkmBridge.instance.showMessage(notification.toFkmData());
    }
  }

  // #***! сообщение удалили, гасим уведомление
  Future<void> _onDeletePush(Packet packet) async {
    final deletion = NotificationPolicy.parseDeletion(packet.payload);
    if (deletion == null) return;
    for (final id in deletion.messageIds) {
      await _removeNotification(deletion.chatId, id);
    }
  }

  /// Удалённое сообщение уезжает из шторки, а при включённом «показывать
  /// удалённые сообщения» остаётся в ней зачёркнутым.
  Future<void> _removeNotification(int chatId, String msgId) =>
      FkmBridge.instance.removeMessage({
        'mc': '$chatId',
        'msgid': msgId,
        'keep': ProMaxSettings.viewDeleted.value ? 'true' : 'false',
      });

  // #***! отредактировали, правим показанное
  Future<void> _editNotification(
    int chatId,
    String msgId,
    Map<dynamic, dynamic> msg,
  ) async {
    final accountId = await TokenStorage.getActiveAccountId();
    if (accountId == null) return;

    final rawConfig = await AppDatabase.getPrivacyConfig(accountId);
    final text = NotificationPolicy.editedText(
      msg,
      rawConfig == null ? null : PrivacyConfig.fromJson(rawConfig),
    );
    if (text == null) return;

    await FkmBridge.instance.editMessage({
      'mc': '$chatId',
      'msgid': msgId,
      'msg': text,
    });
  }

  void dispose() {
    _pushSub?.cancel();
    _stateSub?.cancel();
    _pushSub = null;
    _stateSub = null;
    _started = false;
  }
}
