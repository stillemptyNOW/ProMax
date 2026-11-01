import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../../backend/modules/account/account_models.dart';
import '../../backend/modules/chat_preview.dart';
import '../../backend/modules/chats.dart';
import '../../backend/modules/messages.dart';
import '../config/promax_settings.dart';
import '../crypto/e2ee_service.dart';
import '../storage/app_database.dart';
import '../storage/ignored_senders.dart';
import '../storage/local_read_state.dart';
import '../storage/token_storage.dart';

enum MessagePushKind { created, edited, removed }

@immutable
class MessagePush {
  const MessagePush({
    required this.kind,
    required this.chatId,
    required this.message,
  });

  final MessagePushKind kind;
  final int chatId;
  final Map<dynamic, dynamic> message;

  String? get messageId => message['id']?.toString();

  int? get senderId {
    final sender = message['sender'];
    return sender is int ? sender : null;
  }
}

@immutable
class MessageDeletion {
  const MessageDeletion({required this.chatId, required this.messageIds});

  final int chatId;
  final List<String> messageIds;
}

@immutable
class NotificationFacts {
  const NotificationFacts({
    required this.accountId,
    this.privacy,
    this.chat,
    this.senderName,
    this.streamerMode = false,
    this.encrypted = false,
    this.readMark = 0,
    this.seenMark = 0,
    this.senderIgnored = false,
  });

  final int accountId;
  final PrivacyConfig? privacy;
  final CachedChat? chat;
  final String? senderName;
  final bool streamerMode;
  final bool encrypted;
  final int readMark;
  final int seenMark;
  final bool senderIgnored;

  static int effectiveReadMark({
    required int accountId,
    CachedChat? chat,
    LocalReadState local = const LocalReadState(),
  }) => math.max(chat?.participants[accountId] ?? 0, local.mark);

  static Future<NotificationFacts?> load(int chatId, {int? senderId}) async {
    final accountId = await TokenStorage.getActiveAccountId();
    if (accountId == null) return null;
    final rawConfig = await AppDatabase.getPrivacyConfig(accountId);
    final rows = await AppDatabase.loadChat(accountId, chatId);
    final chat = rows.isEmpty ? null : CachedChat.fromDbRow(rows.first);
    final antiRead = ProMaxSettings.antiRead.value;
    final local = antiRead
        ? await LocalReadState.load(accountId, chatId)
        : const LocalReadState();
    final readMark = effectiveReadMark(
      accountId: accountId,
      chat: chat,
      local: local,
    );
    await IgnoredSenders.instance.load();
    await E2eeService.instance.ensureLoaded(accountId);
    return NotificationFacts(
      accountId: accountId,
      privacy: rawConfig == null ? null : PrivacyConfig.fromJson(rawConfig),
      chat: chat,
      senderName: senderId == null ? null : ContactCache.get(senderId),
      streamerMode: ProMaxSettings.streamerMode.value,
      encrypted: E2eeService.instance.isOn(accountId, chatId),
      readMark: readMark,
      seenMark: antiRead ? readMark : 0,
      senderIgnored: IgnoredSenders.instance.hidesFromDialog(
        accountId: accountId,
        chatId: chatId,
        senderId: senderId,
        isDialog: chat?.type == 'DIALOG',
      ),
    );
  }
}

@immutable
class MessageNotification {
  const MessageNotification({
    required this.chatId,
    required this.accountId,
    required this.senderId,
    required this.senderName,
    required this.title,
    required this.text,
    required this.time,
    required this.isGroup,
    required this.textVisible,
    required this.sound,
    this.messageId,
    this.seenUpTo = 0,
  });

  final int chatId;
  final int accountId;
  final int senderId;
  final String senderName;
  final String title;
  final String text;
  final int time;
  final bool isGroup;
  final bool textVisible;
  final bool sound;
  final String? messageId;
  final int seenUpTo;

  Map<String, String> toFkmData() => {
    'mc': '$chatId',
    'c': '$accountId',
    'suid': '$senderId',
    'userName': senderName,
    'title': title,
    'msg': text,
    'ctime': '$time',
    'sound': '$sound',
    'msgid': ?messageId,
    if (seenUpTo > 0) 'seen': '$seenUpTo',
  };
}

enum DesktopAlert { none, banner, toast }

@immutable
class WindowPresence {
  const WindowPresence({
    required this.visible,
    required this.minimized,
    required this.focused,
  });

  final bool visible;
  final bool minimized;
  final bool focused;

  bool get attended => visible && !minimized && focused;
}

abstract final class NotificationPolicy {
  static const fallbackSender = 'MAX';
  static const hiddenPreview = 'Новое сообщение';

  static MessagePush? parseMessage(
    Object? payload, {
    required bool Function(int chatId) isHiddenChat,
  }) {
    if (payload is! Map) return null;
    final chatId = payload['chatId'];
    if (chatId is! int) return null;
    if (isHiddenChat(chatId)) return null;
    final msg = payload['message'];
    if (msg is! Map) return null;
    if (payload['postId'] != null || msg['postId'] != null) return null;
    final kind = switch (msg['status']?.toString()) {
      'REMOVED' => MessagePushKind.removed,
      'EDITED' => MessagePushKind.edited,
      _ => MessagePushKind.created,
    };
    return MessagePush(kind: kind, chatId: chatId, message: msg);
  }

  static MessageDeletion? parseDeletion(Object? payload) {
    if (payload is! Map) return null;
    final chat = payload['chat'];
    final chatId = (chat is Map && chat['id'] is int)
        ? chat['id'] as int
        : payload['chatId'];
    if (chatId is! int) return null;
    final ids = payload['messageIds'];
    if (ids is! List) return null;
    return MessageDeletion(
      chatId: chatId,
      messageIds: [
        for (final raw in ids)
          if (raw?.toString() case final String id when id.isNotEmpty) id,
      ],
    );
  }

  static bool isOwn(MessagePush push, int? accountId) {
    final senderId = push.senderId;
    return senderId != null && senderId == accountId;
  }

  static bool chatsEnabled(PrivacyConfig? privacy) =>
      privacy == null || privacy.chatsPushNotification == 'ON';

  static bool callsEnabled(PrivacyConfig? privacy) =>
      privacy == null || privacy.mCallPushNotification == 'ON';

  static bool soundEnabled(PrivacyConfig? privacy) =>
      privacy == null || privacy.chatsPushSound.isNotEmpty;

  static String previewText(Map<dynamic, dynamic> msg) {
    final text = msg['text']?.toString().trim();
    if (text != null && text.isNotEmpty) return text;
    final attach = attachPreviewLabel(msg['attaches']);
    if (attach != null && attach.isNotEmpty) return attach;
    return hiddenPreview;
  }

  static String? editedText(Map<dynamic, dynamic> msg, PrivacyConfig? privacy) {
    if (privacy != null) {
      if (privacy.chatsPushNotification != 'ON') return null;
      if (!privacy.pushDetails) return null;
    }
    final text = previewText(msg);
    return text == hiddenPreview ? null : text;
  }

  static MessageNotification? compose(
    MessagePush push,
    NotificationFacts facts, {
    int Function()? now,
  }) {
    final senderId = push.senderId;
    if (senderId == null || senderId == facts.accountId) return null;
    if (facts.senderIgnored) return null;
    final time = push.message['time'];
    if (time is int && time <= facts.readMark) return null;

    final privacy = facts.privacy;
    if (!chatsEnabled(privacy)) return null;
    final showPreview = privacy?.pushDetails ?? true;

    final chat = facts.chat;
    if (chat != null && chat.isMuted) return null;

    final senderName = facts.senderName ?? chat?.title ?? fallbackSender;
    final isGroup = chat != null && chat.isGroupChat;
    final title = (chat != null && chat.isGroupChat)
        ? (chat.title ?? senderName)
        : senderName;

    final textVisible = showPreview && !facts.streamerMode && !facts.encrypted;
    final text = textVisible ? previewText(push.message) : hiddenPreview;
    final msgId = push.message['id'];

    return MessageNotification(
      chatId: push.chatId,
      accountId: facts.accountId,
      senderId: senderId,
      senderName: senderName,
      title: title,
      text: text,
      time: time is int
          ? time
          : (now?.call() ?? DateTime.now().millisecondsSinceEpoch),
      isGroup: isGroup,
      textVisible: textVisible && text != hiddenPreview,
      sound: soundEnabled(privacy),
      messageId: msgId == null ? null : '$msgId',
      seenUpTo: facts.seenMark,
    );
  }

  static DesktopAlert desktopAlert({
    required WindowPresence presence,
    required int activeChatId,
    required int chatId,
  }) {
    if (!presence.attended) return DesktopAlert.toast;
    if (activeChatId == chatId) return DesktopAlert.none;
    return DesktopAlert.banner;
  }
}
