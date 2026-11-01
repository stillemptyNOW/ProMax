import 'dart:async';
import 'dart:collection';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../../backend/api.dart';
import '../../backend/modules/account/account_models.dart';
import '../../backend/modules/messages.dart';
import '../../frontend/widgets/message_banner.dart';
import '../../main.dart';
import '../calls/call_controller.dart';
import '../protocol/opcode_map.dart';
import '../protocol/packet.dart';
import '../push/notification_bridge.dart';
import '../push/notification_policy.dart';
import '../push/push_service.dart';
import '../push/quiet_hours.dart';
import '../security/double_bottom.dart';
import '../storage/app_database.dart';
import '../storage/notified_messages.dart';
import '../storage/token_storage.dart';
import '../utils/logger.dart';
import 'desktop_identity.dart';
import 'desktop_toast.dart';
import 'desktop_window.dart';

class _ShownToast {
  const _ShownToast({
    required this.id,
    required this.title,
    required this.textVisible,
    required this.senderPrefix,
  });

  final int id;
  final String title;
  final bool textVisible;
  final String? senderPrefix;
}

class DesktopNotifier {
  DesktopNotifier._();

  static final DesktopNotifier instance = DesktopNotifier._();

  static const _maxTracked = 200;
  static const _replyInput = 'reply';
  static const _deletedText = 'Сообщение удалено';

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  final LinkedHashMap<String, _ShownToast> _shown = LinkedHashMap();

  StreamSubscription<Packet>? _pushSub;
  StreamSubscription<IncomingCall>? _callSub;
  StreamSubscription<void>? _callCanceledSub;
  bool _started = false;
  bool _ready = false;
  bool _toastsVisible = false;
  int _nextId = 1;
  IncomingCall? _callToast;

  bool get supported {
    if (kIsWeb) return false;
    try {
      return Platform.isWindows || Platform.isLinux;
    } catch (_) {
      return false;
    }
  }

  bool get _windows {
    try {
      return Platform.isWindows;
    } catch (_) {
      return false;
    }
  }

  Future<void> init(Api api) async {
    if (_started || !supported) return;
    _started = true;
    addLocalNotificationResponseHandler(_onResponse);
    _pushSub = api.pushStream
        .where(
          (packet) =>
              packet.opcode == Opcode.notifMessage ||
              packet.opcode == Opcode.notifMsgDelete,
        )
        .listen(_onPush);
    _callSub = CallController.instance.incomingCalls.listen(
      (call) => unawaited(_guard('звонок', () => _onIncomingCall(call))),
    );
    _callCanceledSub = CallController.instance.incomingCanceled.listen(
      (_) => unawaited(_guard('пропущенный звонок', _onCallGone)),
    );
    try {
      await initLocalNotificationActions().timeout(const Duration(seconds: 10));
      _ready = true;
    } catch (e) {
      logger.w('DesktopNotifier: уведомления недоступны: $e');
    }
  }

  Future<void> _guard(String what, Future<void> Function() action) async {
    try {
      await action();
    } catch (e) {
      logger.w('DesktopNotifier: $what: $e');
    }
  }

  Future<void> onWindowAttended() async {
    if (!_ready || !_toastsVisible) return;
    _toastsVisible = false;
    _shown.clear();
    _callToast = null;
    try {
      await _plugin.cancelAll();
    } catch (e) {
      logger.w('DesktopNotifier.cancelAll: $e');
    }
  }

  Future<void> _onPush(Packet packet) async {
    try {
      if (packet.opcode == Opcode.notifMsgDelete) {
        final deletion = NotificationPolicy.parseDeletion(packet.payload);
        if (deletion == null) return;
        for (final id in deletion.messageIds) {
          await _markRemoved(deletion.chatId, id);
        }
        return;
      }
      final push = NotificationPolicy.parseMessage(
        packet.payload,
        isHiddenChat: DoubleBottom.hides,
      );
      if (push == null) return;
      final msgId = push.messageId;
      switch (push.kind) {
        case MessagePushKind.removed:
          if (msgId != null) await _markRemoved(push.chatId, msgId);
        case MessagePushKind.edited:
          if (msgId != null) await _markEdited(push, msgId);
        case MessagePushKind.created:
          await _onNewMessage(push);
      }
    } catch (e) {
      logger.w('DesktopNotifier: не удалось показать уведомление: $e');
    }
  }

  Future<void> _onNewMessage(MessagePush push) async {
    final accountId = await TokenStorage.getActiveAccountId();
    if (NotificationPolicy.isOwn(push, accountId)) return;
    if (QuietHours.instance.isQuiet(push.chatId)) return;
    final facts = await NotificationFacts.load(
      push.chatId,
      senderId: push.senderId,
    );
    if (facts == null) return;
    final notification = NotificationPolicy.compose(push, facts);
    if (notification == null) return;
    final messageId = notification.messageId;
    if (ProMaxSettings.antiRead.value &&
        messageId != null &&
        !await NotifiedMessages.claim(
          notification.accountId,
          notification.chatId,
          messageId,
        )) {
      return;
    }

    final presence = await DesktopWindow.instance.presence();
    final alert = NotificationPolicy.desktopAlert(
      presence: presence,
      activeChatId: NotificationBridge.instance.activeChatId,
      chatId: push.chatId,
    );
    switch (alert) {
      case DesktopAlert.none:
        return;
      case DesktopAlert.banner:
        _showBanner(notification, facts);
      case DesktopAlert.toast:
        await _showToast(notification, facts);
        unawaited(DesktopWindow.instance.flash());
    }
  }

  void _showBanner(MessageNotification n, NotificationFacts facts) {
    final overlay = ProMaxApp.navigatorKey.currentState?.overlay;
    if (overlay == null) return;
    final chat = facts.chat;
    showMessageBanner(
      overlay,
      title: n.title,
      text: _body(n.text, _senderPrefix(n)),
      avatarUrl: n.isGroup ? chat?.iconUrl : ContactCache.getAvatar(n.senderId),
      userId: n.isGroup ? null : n.senderId,
      onTap: () => NotificationBridge.instance.openChat(n.chatId),
    );
    if (n.sound) unawaited(SystemSound.play(SystemSoundType.alert));
  }

  Future<void> _showToast(
    MessageNotification n,
    NotificationFacts facts,
  ) async {
    if (!_ready) return;
    final key = _key(n.chatId, n.messageId);
    final id = _nextId++;
    final prefix = _senderPrefix(n);
    final body = _body(n.text, prefix);
    final canReply = !facts.encrypted && n.textVisible;
    final payload = DesktopToastIntent.chatPayload(
      n.chatId,
      accountId: n.accountId,
      messageId: int.tryParse(n.messageId ?? ''),
    );
    await _plugin.show(
      id: id,
      title: _windows ? '{title}' : n.title,
      body: _windows ? '{body}' : body,
      payload: payload,
      notificationDetails: NotificationDetails(
        windows: WindowsNotificationDetails(
          audio: n.sound ? null : WindowsNotificationAudio.silent(),
          timestamp: DateTime.fromMillisecondsSinceEpoch(n.time),
          bindings: {'title': n.title, 'body': body},
          inputs: [
            if (canReply)
              const WindowsTextInput(
                id: _replyInput,
                placeHolderContent: 'Ответить…',
              ),
          ],
          actions: [
            if (canReply)
              WindowsAction(
                content: 'Отправить',
                arguments: DesktopToastIntent.chatPayload(
                  n.chatId,
                  accountId: n.accountId,
                  messageId: int.tryParse(n.messageId ?? ''),
                  action: DesktopToastAction.reply,
                ),
                inputId: _replyInput,
              ),
          ],
        ),
        linux: LinuxNotificationDetails(suppressSound: !n.sound),
      ),
    );
    _toastsVisible = true;
    if (key == null) return;
    _shown.remove(key);
    _shown[key] = _ShownToast(
      id: id,
      title: n.title,
      textVisible: n.textVisible,
      senderPrefix: prefix,
    );
    while (_shown.length > _maxTracked) {
      _shown.remove(_shown.keys.first);
    }
  }

  Future<void> _markEdited(MessagePush push, String msgId) async {
    final shown = _shown[_key(push.chatId, msgId)!];
    if (shown == null || !shown.textVisible || !_ready) return;
    final accountId = await TokenStorage.getActiveAccountId();
    if (accountId == null) return;
    final rawConfig = await AppDatabase.getPrivacyConfig(accountId);
    final text = NotificationPolicy.editedText(
      push.message,
      rawConfig == null ? null : PrivacyConfig.fromJson(rawConfig),
    );
    if (text == null) return;
    await _replace(shown, _body(text, shown.senderPrefix));
  }

  Future<void> _markRemoved(int chatId, String msgId) async {
    final key = _key(chatId, msgId)!;
    final shown = _shown.remove(key);
    if (shown == null || !_ready) return;
    if (!_windows) {
      await _plugin.cancel(id: shown.id);
      return;
    }
    await _replace(shown, _deletedText);
  }

  Future<void> _replace(_ShownToast shown, String body) async {
    final windows = _plugin
        .resolvePlatformSpecificImplementation<
          FlutterLocalNotificationsWindows
        >();
    if (windows == null) return;
    await windows.updateBindings(
      id: shown.id,
      bindings: {'title': shown.title, 'body': body},
    );
  }

  Future<void> _onIncomingCall(IncomingCall call) async {
    unawaited(DesktopWindow.instance.flash());
    if (!_ready) return;
    final presence = await DesktopWindow.instance.presence();
    if (presence.attended) return;
    if (!identical(CallController.instance.pendingIncoming, call)) return;
    final accountId = await TokenStorage.getActiveAccountId();
    if (accountId != null) {
      final raw = await AppDatabase.getPrivacyConfig(accountId);
      if (!NotificationPolicy.callsEnabled(
        raw == null ? null : PrivacyConfig.fromJson(raw),
      )) {
        return;
      }
    }
    final name =
        ContactCache.get(call.callerId) ??
        call.callerName ??
        NotificationPolicy.fallbackSender;
    final title = call.isVideo ? 'Входящий видеозвонок' : 'Входящий звонок';
    _callToast = call;
    _toastsVisible = true;
    await _plugin.show(
      id: _nextId++,
      title: _windows ? '{title}' : title,
      body: _windows ? '{body}' : name,
      payload: DesktopToastIntent.callPayload(call.conversationId),
      notificationDetails: NotificationDetails(
        windows: WindowsNotificationDetails(
          scenario: WindowsNotificationScenario.incomingCall,
          audio: WindowsNotificationAudio.silent(),
          bindings: {'title': title, 'body': name},
          actions: [
            WindowsAction(
              content: 'Принять',
              arguments: DesktopToastIntent.callPayload(
                call.conversationId,
                action: DesktopToastAction.accept,
              ),
              buttonStyle: WindowsButtonStyle.success,
            ),
            WindowsAction(
              content: 'Отклонить',
              arguments: DesktopToastIntent.callPayload(
                call.conversationId,
                action: DesktopToastAction.decline,
              ),
              buttonStyle: WindowsButtonStyle.critical,
            ),
          ],
        ),
        linux: LinuxNotificationDetails(
          suppressSound: true,
          actions: [
            LinuxNotificationAction(
              key: DesktopToastAction.accept.name,
              label: 'Принять',
            ),
            LinuxNotificationAction(
              key: DesktopToastAction.decline.name,
              label: 'Отклонить',
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _onCallGone() async {
    final call = _callToast;
    if (call == null || !_ready) return;
    _callToast = null;
    await _plugin.cancelAll();
    _shown.clear();
    final name = ContactCache.get(call.callerId) ?? call.callerName;
    await _plugin.show(
      id: _nextId++,
      title: 'Пропущенный звонок',
      body: name ?? NotificationPolicy.fallbackSender,
      payload: DesktopToastIntent.callPayload(call.conversationId),
      notificationDetails: const NotificationDetails(
        windows: WindowsNotificationDetails(),
        linux: LinuxNotificationDetails(),
      ),
    );
  }

  bool _onResponse(NotificationResponse response) {
    if (!_started) return false;
    final intent = DesktopToastIntent.parse(
      payload: response.payload,
      actionId: response.actionId,
    );
    if (intent == null) return false;
    unawaited(_guard('нажатие', () => _handle(intent, response)));
    return true;
  }

  Future<void> _handle(
    DesktopToastIntent intent,
    NotificationResponse response,
  ) async {
    switch (intent.action) {
      case DesktopToastAction.reply:
        final typed = response.data[_replyInput];
        final text = (typed is String ? typed : response.input ?? '').trim();
        if (text.isNotEmpty) await _reply(intent, text);
        return;
      case DesktopToastAction.decline:
        _callToast = null;
        final conversationId = intent.conversationId;
        if (conversationId != null) {
          CallController.instance.decideIncoming(conversationId, accept: false);
        }
        return;
      case DesktopToastAction.accept:
        _callToast = null;
        await DesktopWindow.instance.reveal();
        final conversationId = intent.conversationId;
        if (conversationId != null) {
          CallController.instance.decideIncoming(conversationId, accept: true);
        }
        return;
      case DesktopToastAction.open:
        await DesktopWindow.instance.reveal();
        final chatId = intent.chatId;
        if (chatId != null) NotificationBridge.instance.openChat(chatId);
    }
  }

  Future<void> _reply(DesktopToastIntent intent, String text) async {
    final chatId = intent.chatId;
    if (chatId == null) return;
    final accountId = await TokenStorage.getActiveAccountId();
    if (accountId == null || accountId != intent.accountId) return;
    if (await AppDatabase.loadE2eeSession(accountId, chatId) != null) return;
    try {
      await messagesModule.sendMessage(
        accountId,
        chatId,
        text,
        replyToMessageId: intent.messageId,
      );
    } catch (e) {
      logger.w('DesktopNotifier: ответ не отправлен: $e');
      if (!_ready) return;
      await _plugin.show(
        id: _nextId++,
        title: DesktopIdentity.appName,
        body: 'Не удалось отправить ответ',
        notificationDetails: const NotificationDetails(
          windows: WindowsNotificationDetails(),
          linux: LinuxNotificationDetails(),
        ),
      );
    }
  }

  String? _senderPrefix(MessageNotification n) =>
      n.isGroup && n.senderName != n.title ? n.senderName : null;

  String _body(String text, String? prefix) =>
      prefix == null ? text : '$prefix: $text';

  String? _key(int chatId, String? msgId) =>
      msgId == null ? null : '$chatId:$msgId';

  void dispose() {
    _pushSub?.cancel();
    _callSub?.cancel();
    _callCanceledSub?.cancel();
    _pushSub = null;
    _callSub = null;
    _callCanceledSub = null;
    _started = false;
  }
}
