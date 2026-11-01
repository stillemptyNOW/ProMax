import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../../core/config/promax_settings.dart';
import '../../core/protocol/opcode_map.dart';
import '../../core/protocol/packet.dart';
import '../../core/push/push_service.dart';
import '../../core/cache/info_cache.dart';
import '../../core/cache/message_session_cache.dart';
import 'shared_content.dart';
import '../../core/crypto/e2ee_service.dart';
import '../../core/crypto/message_decryption_cache.dart';
import '../../core/media/deleted_media_keeper.dart';
import '../../core/storage/app_database.dart';
import '../../core/storage/ignored_senders.dart';
import '../../core/storage/local_read_state.dart';
import '../../core/storage/read_receipt.dart';
import '../../core/storage/chat_activity_store.dart';
import '../../core/storage/chat_members_store.dart';
import '../../core/security/double_bottom.dart';
import '../../core/storage/token_storage.dart';
import '../../core/utils/logger.dart';
import '../../core/utils/server_clock.dart';
import '../../core/utils/text_format.dart';
import '../../models/attachment.dart' show ForwardedMessageAttachment;
import '../../models/chat_call.dart';
import '../../models/chat_preview_media.dart';
import '../../models/contact_info.dart';
import '../api.dart';
import 'account/privacy_module.dart';
import 'chat_deletion_plan.dart';
import 'chat_parsing.dart';
import 'chat_preview.dart';
import 'contacts.dart' show ContactsModule;
import 'deletion_policy.dart';
import 'folders.dart';
import 'messages.dart'
    show ContactCache, CachedMessage, HistoryPage, MessagesModule;
import 'pending_deletions.dart';
import 'read_mark_queue.dart';
import 'read_receipts.dart';
import 'server_outcome.dart';

// #***! участники картой id -> время прочтения, в базе строкой
Map<int, int> parseParticipants(dynamic raw) {
  try {
    final decoded = raw is String ? jsonDecode(raw) : raw;
    if (decoded is Map) {
      return decoded.map(
        (k, v) => MapEntry(
          k is int ? k : int.parse(k.toString()),
          v is int ? v : int.tryParse(v.toString()) ?? 0,
        ),
      );
    }
  } catch (e) {
    logger.e('Failed to parse participants: $e');
  }
  return {};
}

// #***! время в старших битах id, младшие 16 это счётчик внутри миллисекунды
/// Server message ids carry their timestamp in the high bits: the low 16 bits
/// are an intra-millisecond sequence number.
int messageIdToTime(int messageId) => messageId >> 16;

// #***! упомянули нас или нет, от этого значок в списке
bool messageMentionsUser(Map<dynamic, dynamic> message, int userId) {
  final elements = message['elements'];
  if (elements is! List) return false;
  for (final element in elements.whereType<Map>()) {
    if (element['type']?.toString() != 'USER_MENTION') continue;
    if (element['entityId'] == userId) return true;
  }
  return false;
}

// #***! чат как он лежит в базе плюс развёрнутое последнее сообщение
class CachedChat {
  final int id;
  final int accountId;
  final String type;
  final String? title;
  final String? iconUrl;
  final int? lastMsgId;
  final int? lastMsgTime;
  final String? lastMsgText;
  final String? lastMsgTextOneLine;
  final String? lastMsgElements;
  final String? lastMsgPreview;
  final int? lastMsgSenderId;
  final String? lastMsgStatus;
  final int unreadCount;
  final int lastEventTime;
  final int cachedAt;
  final int? favIndex;
  final int dontDisturbUntil;
  final bool isOnline;
  final int seenTime;
  final Map<int, int> participants;
  final Set<String> options;
  final int? owner;
  final Set<int> admins;
  final int? pinnedMsgId;
  final String? pinnedMsgText;
  final int? pinnedMsgTime;
  final bool pinnedMsgIsPreview;
  final int? lastMentionMsgId;
  final String? activeCallData;
  final String? publicLink;

  CachedChat({
    required this.id,
    required this.accountId,
    required this.type,
    this.title,
    this.iconUrl,
    this.lastMsgId,
    this.lastMsgTime,
    this.lastMsgText,
    this.lastMsgElements,
    this.lastMsgPreview,
    this.lastMsgSenderId,
    this.lastMsgStatus,
    required this.unreadCount,
    required this.lastEventTime,
    required this.cachedAt,
    this.favIndex,
    required this.dontDisturbUntil,
    required this.isOnline,
    required this.seenTime,
    required this.participants,
    this.options = const {},
    this.owner,
    this.admins = const {},
    this.pinnedMsgId,
    this.pinnedMsgText,
    this.pinnedMsgTime,
    this.pinnedMsgIsPreview = false,
    this.lastMentionMsgId,
    this.activeCallData,
    this.publicLink,
  }) : lastMsgTextOneLine = lastMsgText != null && lastMsgText.contains('\n')
           ? lastMsgText.replaceAll('\n', ' ')
           : lastMsgText;

  // #***! дальше готовые ответы для юишки чтоб она сырое не разбирала
  bool get isOfficial => options.contains('OFFICIAL');

  late final ChatPreviewMedia? lastMsgMedia = ChatPreviewMedia.decode(
    lastMsgPreview,
  );

  late final ChatCall? activeCall = ChatCall.decode(activeCallData);

  // #***! форматирование последнего сообщения строкой джейсона
  List<FormatRange> get lastMsgFormatRanges {
    final raw = lastMsgElements;
    if (raw == null || raw.isEmpty) return const [];
    try {
      return parseFormatElements(jsonDecode(raw));
    } catch (_) {
      return const [];
    }
  }

  // #***! прочитано если у кого то отметка не старше нашего сообщения
  bool get lastMsgReadByOthers {
    final t = lastMsgTime;
    if (t == null) return false;
    for (final entry in participants.entries) {
      if (entry.key != accountId && entry.value >= t) return true;
    }
    return false;
  }

  // #***! владелец тоже админ
  bool iAmAdmin(int myId) => owner == myId || admins.contains(myId);

  bool get hasPinnedMessage => pinnedMsgId != null;

  bool get isGroupChat => type == 'CHAT' || type == 'GROUP';

  // #***! закрепляет админ или все если настроено
  bool canPinMessages(int myId) {
    if (!isGroupChat) return false;
    return iAmAdmin(myId) || options.contains('ALL_CAN_PIN_MESSAGE');
  }

  bool get forwardDisabled => options.contains('DISABLE_FORWARD');

  bool get copyDisabled => options.contains('MESSAGE_COPY_NOT_ALLOWED');

  bool get confirmBeforeSend => options.contains('CONFIRM_BEFORE_SEND');

  bool get commentsEnabled => options.contains('COMMENTS');

  // #***! 0 звук есть, минус навсегда, иначе время до которого молчим
  bool get isMuted {
    if (dontDisturbUntil == ChatsModule.muteOff) return false;
    if (dontDisturbUntil < 0) return true;
    return dontDisturbUntil > DateTime.now().millisecondsSinceEpoch;
  }

  // #***! сообщение удалили а истории нет, рисуем плашку
  bool get isLastMsgDeleted => lastMsgText == ChatsModule.lastMsgPlaceholder;

  // #***! упоминание новее нашей отметки значит непрочитанное
  bool get hasUnreadMention {
    final mentionId = lastMentionMsgId;
    if (mentionId == null || mentionId <= 0) return false;
    return messageIdToTime(mentionId) > (participants[accountId] ?? 0);
  }

  factory CachedChat.fromDbRow(Map<String, dynamic> row) => CachedChat(
    id: row['id'] as int,
    accountId: row['account_id'] as int,
    type: row['type'] as String,
    title: row['title'] as String?,
    iconUrl: row['icon_url'] as String?,
    lastMsgId: row['last_msg_id'] as int?,
    lastMsgTime: row['last_msg_time'] as int?,
    lastMsgText: row['last_msg_text'] as String?,
    lastMsgElements: row['last_msg_elements'] as String?,
    lastMsgPreview: row['last_msg_preview'] as String?,
    lastMsgSenderId: row['last_msg_sender'] as int?,
    lastMsgStatus: row['last_msg_status'] as String?,
    unreadCount: row['unread_count'] as int,
    lastEventTime: row['last_event_time'] as int,
    cachedAt: row['cached_at'] as int,
    favIndex: row['fav_index'] as int?,
    dontDisturbUntil: row['dont_disturb_until'] as int,
    isOnline: (row['is_online'] as int) == 1,
    seenTime: row['seen_time'] as int,
    participants: parseParticipants(row['participants']),
    options: _decodeOptions(row['options']),
    owner: row['owner'] as int?,
    admins: _decodeAdmins(row['admins']),
    pinnedMsgId: row['pinned_msg_id'] as int?,
    pinnedMsgText: row['pinned_msg_text'] as String?,
    pinnedMsgTime: row['pinned_msg_time'] as int?,
    pinnedMsgIsPreview: (row['pinned_msg_is_preview'] as int? ?? 0) == 1,
    lastMentionMsgId: row['last_mention_msg_id'] as int?,
    activeCallData: row['active_call'] as String?,
    publicLink: row['public_link'] as String?,
  );

  // #***! options и admins в базе строками
  static Set<String> _decodeOptions(dynamic raw) {
    if (raw is! String || raw.isEmpty) return const {};
    return raw.split(',').where((s) => s.isNotEmpty).toSet();
  }

  static Set<int> _decodeAdmins(dynamic raw) {
    if (raw is! String || raw.isEmpty) return const {};
    return raw
        .split(',')
        .map((s) => int.tryParse(s.trim()))
        .whereType<int>()
        .toSet();
  }

  // #***! обратно в строку таблицы
  Map<String, dynamic> toDbRow() => {
    'id': id,
    'account_id': accountId,
    'type': type,
    'title': title,
    'icon_url': iconUrl,
    'last_msg_id': lastMsgId,
    'last_msg_time': lastMsgTime,
    'last_msg_text': lastMsgText,
    'last_msg_elements': lastMsgElements,
    'last_msg_preview': lastMsgPreview,
    'last_msg_sender': lastMsgSenderId,
    'last_msg_status': lastMsgStatus,
    'unread_count': unreadCount,
    'last_event_time': lastEventTime,
    'cached_at': cachedAt,
    'fav_index': favIndex,
    'dont_disturb_until': dontDisturbUntil,
    'is_online': isOnline ? 1 : 0,
    'seen_time': seenTime,
    'participants': jsonEncode(
      participants.map((k, v) => MapEntry(k.toString(), v)),
    ),
    'options': options.isEmpty ? null : options.join(','),
    'owner': owner,
    'admins': admins.isEmpty ? null : admins.join(','),
    'pinned_msg_id': pinnedMsgId,
    'pinned_msg_text': pinnedMsgText,
    'pinned_msg_time': pinnedMsgTime,
    'pinned_msg_is_preview': pinnedMsgIsPreview ? 1 : 0,
    'last_mention_msg_id': lastMentionMsgId,
    'active_call': activeCallData,
    'public_link': publicLink,
  };

  // #***! _keep отличает не передали от передали null, иначе поле не сбросить
  static const Object _keep = Object();

  CachedChat copyWith({
    String? type,
    Object? title = _keep,
    Object? iconUrl = _keep,
    Object? lastMsgId = _keep,
    Object? lastMsgTime = _keep,
    Object? lastMsgText = _keep,
    Object? lastMsgElements = _keep,
    Object? lastMsgPreview = _keep,
    Object? lastMsgSenderId = _keep,
    Object? lastMsgStatus = _keep,
    int? unreadCount,
    int? lastEventTime,
    int? cachedAt,
    Object? favIndex = _keep,
    int? dontDisturbUntil,
    bool? isOnline,
    int? seenTime,
    Map<int, int>? participants,
    Set<String>? options,
    Object? owner = _keep,
    Set<int>? admins,
    Object? pinnedMsgId = _keep,
    Object? pinnedMsgText = _keep,
    Object? pinnedMsgTime = _keep,
    bool? pinnedMsgIsPreview,
    Object? lastMentionMsgId = _keep,
    Object? activeCallData = _keep,
    Object? publicLink = _keep,
  }) {
    return CachedChat(
      id: id,
      accountId: accountId,
      type: type ?? this.type,
      title: identical(title, _keep) ? this.title : title as String?,
      iconUrl: identical(iconUrl, _keep) ? this.iconUrl : iconUrl as String?,
      lastMsgId: identical(lastMsgId, _keep)
          ? this.lastMsgId
          : lastMsgId as int?,
      lastMsgTime: identical(lastMsgTime, _keep)
          ? this.lastMsgTime
          : lastMsgTime as int?,
      lastMsgText: identical(lastMsgText, _keep)
          ? this.lastMsgText
          : lastMsgText as String?,
      lastMsgElements: identical(lastMsgElements, _keep)
          ? this.lastMsgElements
          : lastMsgElements as String?,
      lastMsgPreview: identical(lastMsgPreview, _keep)
          ? this.lastMsgPreview
          : lastMsgPreview as String?,
      lastMsgSenderId: identical(lastMsgSenderId, _keep)
          ? this.lastMsgSenderId
          : lastMsgSenderId as int?,
      lastMsgStatus: identical(lastMsgStatus, _keep)
          ? this.lastMsgStatus
          : lastMsgStatus as String?,
      unreadCount: unreadCount ?? this.unreadCount,
      lastEventTime: lastEventTime ?? this.lastEventTime,
      cachedAt: cachedAt ?? this.cachedAt,
      favIndex: identical(favIndex, _keep) ? this.favIndex : favIndex as int?,
      dontDisturbUntil: dontDisturbUntil ?? this.dontDisturbUntil,
      isOnline: isOnline ?? this.isOnline,
      seenTime: seenTime ?? this.seenTime,
      participants: participants ?? this.participants,
      options: options ?? this.options,
      owner: identical(owner, _keep) ? this.owner : owner as int?,
      admins: admins ?? this.admins,
      pinnedMsgId: identical(pinnedMsgId, _keep)
          ? this.pinnedMsgId
          : pinnedMsgId as int?,
      pinnedMsgText: identical(pinnedMsgText, _keep)
          ? this.pinnedMsgText
          : pinnedMsgText as String?,
      pinnedMsgTime: identical(pinnedMsgTime, _keep)
          ? this.pinnedMsgTime
          : pinnedMsgTime as int?,
      pinnedMsgIsPreview: pinnedMsgIsPreview ?? this.pinnedMsgIsPreview,
      lastMentionMsgId: identical(lastMentionMsgId, _keep)
          ? this.lastMentionMsgId
          : lastMentionMsgId as int?,
      activeCallData: identical(activeCallData, _keep)
          ? this.activeCallData
          : activeCallData as String?,
      publicLink: identical(publicLink, _keep)
          ? this.publicLink
          : publicLink as String?,
    );
  }
}

// #***! найденный чат в поиске
class ChatSearchHit {
  final int id;
  final String type;
  final String? title;
  final String? avatarUrl;
  final String? subtitle;

  const ChatSearchHit({
    required this.id,
    required this.type,
    this.title,
    this.avatarUrl,
    this.subtitle,
  });
}

// #***! участник для экрана списка
class ChatMemberEntry {
  final int id;
  final String? name;
  final String? fullName;
  final String? avatarUrl;
  final int? seenTime;
  final int presenceStatus;
  final bool blocked;
  final bool isContact;

  const ChatMemberEntry({
    required this.id,
    this.name,
    this.fullName,
    this.avatarUrl,
    this.seenTime,
    required this.presenceStatus,
    this.blocked = false,
    this.isContact = false,
  });

  bool get isOnline => presenceStatus == 1;
}

class ChatMembersPage {
  final List<ChatMemberEntry> members;
  final int marker;

  const ChatMembersPage({required this.members, required this.marker});
}

// #***! найденное сообщение в поиске
class MessageSearchHit {
  final int chatId;
  final String? messageId;
  final String? text;
  final int time;
  final int senderId;

  const MessageSearchHit({
    required this.chatId,
    this.messageId,
    this.text,
    required this.time,
    required this.senderId,
  });
}

sealed class MessageEvent {
  // #***! события чата для открытого экрана
  final int chatId;
  const MessageEvent(this.chatId);
}

class MessageAddedEvent extends MessageEvent {
  final CachedMessage message;
  const MessageAddedEvent(super.chatId, this.message);
}

class MessageEditedEvent extends MessageEvent {
  final CachedMessage message;
  const MessageEditedEvent(super.chatId, this.message);
}

class MessageRemovedEvent extends MessageEvent {
  final String messageId;
  const MessageRemovedEvent(super.chatId, this.messageId);
}

class MessageMarkedDeletedEvent extends MessageEvent {
  final String messageId;
  const MessageMarkedDeletedEvent(super.chatId, this.messageId);
}

class MessageReactionsChangedEvent extends MessageEvent {
  final String messageId;
  final Map<String, dynamic>? reactionInfo;
  const MessageReactionsChangedEvent(
    super.chatId,
    this.messageId,
    this.reactionInfo,
  );
}

class MessageSentEvent extends MessageEvent {
  final String tempId;
  final CachedMessage message;
  const MessageSentEvent(super.chatId, this.tempId, this.message);
}

// #***! битмаска прав админа канала, складывается через |
abstract class ChatPermission {
  static const int addRemoveMember = 2;
  static const int addAdmin = 4;
  static const int changeChatInfo = 8;
  static const int pinMessage = 16;
  static const int postMessage = 256;
  static const int editMessage = 512;
  static const int deleteMessage = 1024;
}

// #***! главный модуль чатов, кэш пуши и все операции
class ChatsModule {
  // #***! 0 звук есть, -1 выключен навсегда
  static const int muteOff = 0;
  static const int muteForever = -1;

  // #***! маркер что последнее сообщение удалили
  /// Sentinel в `lastMsgText` когда последнее сообщение в чате удалено,
  /// а кеша истории нет — UI должен отрисовать курсивную плашку.
  static const String lastMsgPlaceholder = '__promax_lastmsg_placeholder__';

  ChatsModule._();

  // #***! события для открытого чата
  final _messageEventsController = StreamController<MessageEvent>.broadcast();
  Stream<MessageEvent> get messageEvents => _messageEventsController.stream;

  final _departedChatsController = StreamController<int>.broadcast();
  Stream<int> get departedChats => _departedChatsController.stream;

  int? _paginatedAccountId;

  Future<void> _extendHistoryCoverage(
    int accountId,
    int chatId,
    Map<String, dynamic> chatRowBefore,
    int time,
  ) async {
    final previousLast = CachedChat.fromDbRow(chatRowBefore).lastMsgTime;
    if (previousLast == null || previousLast <= 0) return;
    try {
      await AppDatabase.extendMessageRange(
        accountId,
        chatId,
        previousLastTime: previousLast,
        time: time,
      );
    } catch (e) {
      logger.w('extendMessageRange error: $e');
    }
  }

  Future<void> storeSentMessages(
    int accountId,
    int chatId,
    List<CachedMessage> messages,
  ) async {
    if (messages.isEmpty) return;
    final rows = await AppDatabase.loadChat(accountId, chatId);
    await AppDatabase.saveMessages([
      for (final message in messages) message.toDbRow(),
    ]);
    if (rows.isEmpty) return;
    final newest = messages.map((m) => m.time).reduce((a, b) => a > b ? a : b);
    await _extendHistoryCoverage(accountId, chatId, rows.first, newest);
  }

  void emitMessageSent(int chatId, String tempId, CachedMessage message) {
    _messageEventsController.add(MessageSentEvent(chatId, tempId, message));
  }

  // #***! отметка прочтения и обнуление счётчика
  Future<void> markRead(
    Api api,
    int accountId,
    int chatId,
    String messageId,
    int mark,
  ) async {
    unawaited(PushService.clearChatNotification(chatId));
    final rows = await AppDatabase.loadChat(accountId, chatId);
    if (rows.isEmpty) return;
    final row = Map<String, dynamic>.from(rows.first);
    if ((row['unread_count'] as int? ?? 0) == 0) return;

    final msgIdNum = int.tryParse(messageId);
    if (msgIdNum != null && _sendsReadMarks(accountId, chatId)) {
      await ReadMarkQueue.instance.submit(
        api,
        ReadMark(
          accountId: accountId,
          chatId: chatId,
          messageId: msgIdNum,
          mark: mark,
        ),
      );
    }

    final fresh = await AppDatabase.loadChat(accountId, chatId);
    if (fresh.isEmpty) return;
    final cached = CachedChat.fromDbRow(fresh.first);
    final currentMark = cached.participants[accountId] ?? 0;
    final participants = Map<int, int>.from(cached.participants)
      ..[accountId] = mark > currentMark ? mark : currentMark;
    final updated = cached.copyWith(unreadCount: 0, participants: participants);
    if (ProMaxSettings.antiRead.value) {
      await LocalReadState.recordView(
        accountId,
        chatId,
        mark,
        serverMark: currentMark,
        displayedUnread: cached.unreadCount,
      );
    }
    await _commitChatContent([(fresh.first, updated.toDbRow())]);
  }

  bool _sendsReadMarks(int accountId, int chatId) =>
      !ProMaxSettings.antiRead.value &&
      IgnoredSenders.instance.ignoredPeer(accountId, chatId) == null;

  Future<void> _applyLocalReadState(
    Map<String, dynamic> row, {
    bool updateServerMark = false,
  }) async {
    if (!ProMaxSettings.antiRead.value) return;
    final accountId = row['account_id'] as int;
    final chatId = row['id'] as int;
    final local = await LocalReadState.load(accountId, chatId);
    if (!local.isActive) return;
    final participants = parseParticipants(row['participants']);
    var next = local.withServer(
      serverUnread: (row['unread_count'] as int?) ?? 0,
      serverMark: updateServerMark ? participants[accountId] ?? 0 : null,
    );
    if (!next.isActive) {
      await next.save(accountId, chatId);
      return;
    }
    if (next.seen == null) {
      next = next.withSeen(
        await AppDatabase.countLocallyReadMessages(
          accountId,
          chatId,
          next.serverMark,
          next.mark,
        ),
      );
    }
    if (next != local) await next.save(accountId, chatId);
    row['unread_count'] = next.unreadFor((row['last_msg_time'] as int?) ?? 0);
    participants[accountId] = next.mark;
    row['participants'] = jsonEncode(
      participants.map((key, value) => MapEntry('$key', value)),
    );
  }

  // #***! прочитано до сообщения, при скролле по непрочитанным
  Future<void> markReadUpTo(
    Api api,
    int accountId,
    int chatId,
    String messageId,
    int mark, {
    required int remaining,
  }) async {
    final msgIdNum = int.tryParse(messageId);
    if (msgIdNum != null && _sendsReadMarks(accountId, chatId)) {
      await ReadMarkQueue.instance.submit(
        api,
        ReadMark(
          accountId: accountId,
          chatId: chatId,
          messageId: msgIdNum,
          mark: mark,
        ),
      );
    }

    final rows = await AppDatabase.loadChat(accountId, chatId);
    if (rows.isEmpty) return;
    final cached = CachedChat.fromDbRow(rows.first);
    final next = remaining < 0 ? 0 : remaining;
    final currentMark = cached.participants[accountId] ?? 0;
    final nextMark = mark > currentMark ? mark : currentMark;
    if (cached.unreadCount == next && nextMark == currentMark) {
      if (next == 0) unawaited(PushService.clearChatNotification(chatId));
      return;
    }
    final participants = Map<int, int>.from(cached.participants)
      ..[accountId] = nextMark;
    final updated = cached.copyWith(
      unreadCount: next,
      participants: participants,
    );
    if (ProMaxSettings.antiRead.value) {
      await LocalReadState.recordView(
        accountId,
        chatId,
        nextMark,
        serverMark: currentMark,
        displayedUnread: cached.unreadCount,
        remaining: next,
      );
    }
    await _commitChatContent([(rows.first, updated.toDbRow())]);
    if (next == 0) {
      unawaited(PushService.clearChatNotification(chatId));
    } else if (ProMaxSettings.antiRead.value) {
      unawaited(PushService.pruneChatNotification(chatId, nextMark));
    }
  }

  // #***! пометить непрочитанным руками
  Future<int?> markUnread(Api api, int accountId, int chatId, int mark) async {
    int? unread;
    try {
      final resp = await api.sendRequest(Opcode.chatMark, {
        'type': 'SET_AS_UNREAD',
        'chatId': chatId,
        'mark': mark,
      });
      final payload = resp.payload;
      if (payload is Map) unread = payload['unread'] as int?;
    } catch (_) {
      return null;
    }
    if (unread == null) return null;

    await const LocalReadState().save(accountId, chatId);
    await _updateChat(accountId, chatId, (chat) {
      final participants = Map<int, int>.from(chat.participants)
        ..[accountId] = mark - 1;
      return chat.copyWith(unreadCount: unread, participants: participants);
    });
    return unread;
  }

  // #***! своё сообщение сразу в строку чата, пуш не ждём
  Future<void> applyOutgoing(
    int accountId,
    int chatId, {
    required String messageId,
    required int time,
    required String text,
    required String status,
    List<Map<String, dynamic>>? elements,
    String? preview,
    int? replacesTime,
  }) async {
    if (status == 'sent') await _listPreviewChat(accountId, chatId);
    final thisId = int.tryParse(messageId);
    await _updateChat(accountId, chatId, (chat) {
      final existingTime = chat.lastMsgTime ?? 0;
      final confirmsPreview =
          replacesTime != null &&
          chat.lastMsgId == null &&
          chat.lastMsgTime == replacesTime;
      if (time < existingTime && chat.lastMsgId != thisId && !confirmsPreview) {
        return null;
      }
      return chat.copyWith(
        lastMsgId: thisId,
        lastMsgText: text,
        lastMsgElements: (elements != null && elements.isNotEmpty)
            ? jsonEncode(elements)
            : null,
        lastMsgPreview: preview,
        lastMsgTime: time,
        lastEventTime: time,
        lastMsgSenderId: accountId,
        lastMsgStatus: status,
      );
    });
  }

  // #***! своё медиа в строку чата на всех стадиях: часики пока грузится,
  // галочка когда сервер принял, крестик если не ушло
  Future<void> applyOutgoingMessage(
    CachedMessage message, {
    required String status,
    int? replacesTime,
  }) {
    final payload = {
      ...message.previewPayload,
      if (message.e2ee != CachedMessage.e2eeNone) 'text': null,
    };
    return applyOutgoing(
      message.accountId,
      message.chatId,
      messageId: message.id,
      time: message.time,
      text: messagePreviewText(payload) ?? '',
      preview: messagePreviewMedia(payload),
      status: status,
      replacesTime: replacesTime,
    );
  }

  // #***! chatsChanged на любое изменение, список чатов подписан
  final ValueNotifier<int> chatsChanged = ValueNotifier(0);
  void _bump() => chatsChanged.value = chatsChanged.value + 1;

  // #***! кэш чатов в памяти, обновляется точечно вместо перечитывания всего списка из базы
  final Map<int, CachedChat> _chatsById = {};
  final Map<int, int> _inListById = {};
  final Map<int, ValueNotifier<CachedChat>> _chatNotifiers = {};
  final Set<int> _loadedAccounts = {};
  final Set<int> _readyAccounts = {};

  // #***! бампается только когда реально меняется порядок/состав списка
  final ValueNotifier<int> chatOrderRevision = ValueNotifier(0);

  ValueListenable<CachedChat> chatListenable(CachedChat listed) {
    final existing = _chatNotifiers[listed.id];
    if (existing != null) return existing;
    final chat = _chatsById[listed.id];
    final notifier = ValueNotifier<CachedChat>(chat ?? listed);
    if (chat != null) _chatNotifiers[listed.id] = notifier;
    return notifier;
  }

  bool canAccessForwardSource(ForwardedMessageAttachment forwarded) {
    if (!forwarded.isFromPrivateChat) return true;
    final chatId = forwarded.originalChatId;
    return chatId != null && _inListById[chatId] == ChatListState.visible;
  }

  Future<bool> canOpenForwardSource(
    Api api,
    int accountId,
    ForwardedMessageAttachment forwarded,
  ) async {
    if (canAccessForwardSource(forwarded)) return true;
    final chatId = forwarded.originalChatId;
    if (chatId == null) return false;
    final rows = await AppDatabase.loadChat(accountId, chatId);
    if (rows.isNotEmpty && rows.first['in_list'] == ChatListState.visible) {
      return true;
    }
    final Map<String, dynamic>? info;
    try {
      info = await getChatInfo(api, chatId);
    } on PacketError {
      return false;
    } catch (_) {
      return true;
    }
    if (info == null) return false;
    if (!parseParticipants(info['participants']).containsKey(accountId)) {
      return false;
    }
    await cacheServerChat(info, accountId);
    return true;
  }

  void _announceRemovalChange() {
    chatOrderRevision.value++;
    _bump();
  }

  bool _isAwaitingRemoval(int chatId) =>
      PendingDeletions.instance.isChatHeld(chatId, accounts: _loadedAccounts);

  // #***! снимок текущего кэша, без похода в базу
  List<CachedChat> chatsSnapshot({bool includeHidden = false}) {
    final list = _chatsById.entries
        .where((e) => !_isAwaitingRemoval(e.key))
        .where((e) => includeHidden || _inListById[e.key] == 1)
        .where((e) => !DoubleBottom.hides(e.key))
        .map((e) => e.value)
        .toList();
    list.sort((a, b) => b.lastEventTime.compareTo(a.lastEventTime));
    return list;
  }

  bool get chatsLoaded => _readyAccounts.isNotEmpty;

  // #***! разовая подгрузка кэша чатов аккаунта из базы
  Future<void> ensureLoaded(int accountId) async {
    if (!_loadedAccounts.add(accountId)) return;
    if (_repairedSenders.add(accountId)) {
      await AppDatabase.repairLastMessageSenders(accountId);
    }
    final rows = await AppDatabase.loadChats(accountId, includeHidden: true);
    for (final row in rows) {
      final chat = CachedChat.fromDbRow(row);
      _chatsById[chat.id] = chat;
      _inListById[chat.id] = row['in_list'] as int? ?? 1;
      _chatNotifiers[chat.id]?.value = chat;
    }
    _readyAccounts.add(accountId);
    _bump();
  }

  // #***! центральная точка обновления кэша, вызывается вместо голого _bump()
  void _applyChatToMemory(CachedChat updated, {int inList = 1}) {
    _bump();
    if (inList == 0) {
      _removeChatFromMemory(updated.id);
      return;
    }
    final old = _chatsById[updated.id];
    _chatsById[updated.id] = updated;
    _inListById[updated.id] = inList;
    final notifier = _chatNotifiers[updated.id];
    if (notifier != null) {
      notifier.value = updated;
    } else {
      _chatNotifiers[updated.id] = ValueNotifier(updated);
    }
    if (old == null || reshapesChatList(old, updated)) {
      chatOrderRevision.value++;
    }
  }

  @visibleForTesting
  static bool reshapesChatList(CachedChat old, CachedChat updated) =>
      old.favIndex != updated.favIndex ||
      old.lastEventTime != updated.lastEventTime ||
      (old.unreadCount > 0) != (updated.unreadCount > 0) ||
      old.isMuted != updated.isMuted ||
      old.owner != updated.owner ||
      !setEquals(old.admins, updated.admins);

  void _removeChatFromMemory(int chatId) {
    final had = _chatsById.remove(chatId) != null;
    _inListById.remove(chatId);
    _chatNotifiers.remove(chatId)?.dispose();
    if (had) chatOrderRevision.value++;
  }

  // #***! события меняющие состав участников
  static const Set<String> _membershipEvents = {
    'add',
    'joinByLink',
    'leave',
    'remove',
  };

  // #***! счётчик правим локально, свои действия сервер уже учёл
  void _applyMembershipControl(
    int accountId,
    int chatId,
    CachedMessage message,
  ) {
    final control = message.controlAttachment;
    final event = control?.event;
    if (control == null || event == null) return;
    if (!_membershipEvents.contains(event)) return;

    if (message.senderId != accountId) {
      final affected = control.userIds?.length ?? 1;
      ChatMembersStore.instance.adjust(chatId, switch (event) {
        'add' => affected,
        'joinByLink' => 1,
        'leave' => -1,
        'remove' => -affected,
        _ => 0,
      });
    }
    _refreshChatInfo(chatId);
  }

  // #***! перечитываем карточку чтоб права не устарели
  void _refreshChatInfo(int chatId) {
    ChatInfoFetch.invalidate(chatId);
    unawaited(ChatInfoFetch.get(chatId));
  }

  // #***! шаблон прочитать поменять сохранить оповестить
  Future<bool> _updateChat(
    int accountId,
    int chatId,
    CachedChat? Function(CachedChat chat) mutate,
  ) async {
    final rows = await AppDatabase.loadChat(accountId, chatId);
    if (rows.isEmpty) return false;
    final updated = mutate(CachedChat.fromDbRow(rows.first));
    if (updated == null) return false;
    await _commitChatContent([(rows.first, updated.toDbRow())]);
    return true;
  }

  static const Set<String> _chatIdentityColumns = {
    'id',
    'account_id',
    'in_list',
  };

  Future<void> _commitChatContent(
    List<(Map<String, dynamic> before, Map<String, dynamic> after)> changes,
  ) async {
    final updates =
        <({int accountId, int chatId, Map<String, Object?> values})>[];
    for (final (before, after) in changes) {
      final values = <String, Object?>{
        for (final entry in after.entries)
          if (!_chatIdentityColumns.contains(entry.key) &&
              before[entry.key] != entry.value)
            entry.key: entry.value,
      };
      if (values.isEmpty) continue;
      updates.add((
        accountId: after['account_id'] as int,
        chatId: after['id'] as int,
        values: values,
      ));
    }
    if (updates.isEmpty) return;
    await AppDatabase.updateChatColumns(updates);
    for (final update in updates) {
      _applyChatChanges(update.chatId, update.values);
    }
  }

  void _applyChatChanges(int chatId, Map<String, Object?> values) {
    final current = _chatsById[chatId];
    if (current == null) {
      _bump();
      return;
    }
    _applyChatToMemory(
      CachedChat.fromDbRow({...current.toDbRow(), ...values}),
      inList: _inListById[chatId] ?? ChatListState.visible,
    );
  }

  Future<void> _listPreviewChat(int accountId, int chatId) async {
    if (_inListById.containsKey(chatId)) return;
    final rows = await AppDatabase.loadChat(accountId, chatId);
    if (rows.isEmpty) {
      final info = await ChatInfoFetch.get(chatId, forceRefresh: true);
      if (info != null) await cacheServerChat(info.raw, accountId);
      return;
    }
    if (rows.first['in_list'] != ChatListState.notInList) return;
    await AppDatabase.setChatListState(
      accountId,
      chatId,
      ChatListState.visible,
    );
    _applyChatToMemory(
      CachedChat.fromDbRow(rows.first),
      inList: ChatListState.visible,
    );
  }

  // #***! сырой payload в базе строкой
  static Map<String, dynamic>? _decodePayload(dynamic raw) {
    if (raw is String && raw.isNotEmpty) {
      try {
        return Map<String, dynamic>.from(jsonDecode(raw) as Map);
      } catch (_) {}
    }
    return null;
  }

  StreamSubscription<Packet>? _globalPushSub;
  Api? _pushApi;
  StreamSubscription<SessionState>? _globalStateSub;
  Future<void> _pushQueue = Future.value();
  final ReadBaselines _readBaselines = ReadBaselines();

  final Set<int> _historyFetched = {};

  bool wasHistoryFetched(int chatId) => _historyFetched.contains(chatId);
  void markHistoryFetched(int chatId) => _historyFetched.add(chatId);

  void beginReadSession(int serverTime) => _readBaselines.begin(serverTime);

  void _confirmReadMarks(int accountId, Map<dynamic, dynamic> chat) {
    final chatId = chat['id'];
    final raw = chat['participants'];
    if (chatId is! int || raw is! Map) return;
    _readBaselines.confirmAll(accountId, chatId, parseParticipants(raw));
  }

  // #***! подписка на пуши и состояние сессии
  void attachGlobalPushHandlers(Api api) {
    _globalPushSub?.cancel();
    _globalStateSub?.cancel();
    _pushApi = api;
    _globalPushSub = api.pushStream.listen(_enqueueGlobalPush);
    _globalStateSub = api.stateStream.listen(_handleSessionState);
    PendingDeletions.instance.chatHolds
      ..removeListener(_announceRemovalChange)
      ..addListener(_announceRemovalChange);
  }

  void dispose() {
    _globalPushSub?.cancel();
    _globalStateSub?.cancel();
    PendingDeletions.instance.chatHolds.removeListener(_announceRemovalChange);
    _globalPushSub = null;
    _globalStateSub = null;
    _contactFlushTimer?.cancel();
    _contactFlushTimer = null;
    _messageEventsController.close();
    chatsChanged.dispose();
    chatOrderRevision.dispose();
    for (final notifier in _chatNotifiers.values) {
      notifier.dispose();
    }
    _chatNotifiers.clear();
  }

  // #***! при обрыве чистим кэши, пока нас не было всё устарело
  void _handleSessionState(SessionState state) {
    if (state == SessionState.disconnected) {
      ContactInfoFetch.clear();
      PresenceFetch.clear();
      ChatInfoFetch.clear();
      _historyFetched.clear();
      _readBaselines.end();
    }
  }

  // #***! сменили аккаунт, всё локальное чужое
  void resetForAccountSwitch() {
    E2eeService.instance.lock();
    DeletionPolicy.instance.forget();
    _historyFetched.clear();
    _readBaselines.end();
    ContactInfoFetch.clear();
    PresenceFetch.clear();
    ChatInfoFetch.clear();
    SharedContentModule.clearMediaIndex();
    _chatsById.clear();
    _inListById.clear();
    for (final notifier in _chatNotifiers.values) {
      notifier.dispose();
    }
    _chatNotifiers.clear();
    _loadedAccounts.clear();
    _readyAccounts.clear();
    _bump();
  }

  @visibleForTesting
  Future<void> get pushesHandled => _pushQueue;

  // #***! пуши строго по одному, иначе гонки при записи в базу
  void _enqueueGlobalPush(Packet packet) {
    final receivedAt = ServerClock.now();
    _pushQueue = _pushQueue
        .then((_) => _handleGlobalPush(packet, receivedAt))
        .catchError((Object e) {
          logger.w('Ошибка обработки пуша: $e');
        });
  }

  // #***! роутер пушей по опкодам
  Future<void> _handleGlobalPush(Packet packet, int receivedAt) async {
    switch (packet.opcode) {
      case Opcode.notifMessage:
        await _handleNotifMessage(packet);
      case Opcode.notifMark:
        await _handleNotifMark(packet, receivedAt);
      case Opcode.notifMsgReactionsChanged:
        await _handleNotifMsgReactionsChanged(packet);
      case Opcode.notifMsgDelete:
        await _handleNotifMsgDelete(packet);
      case Opcode.notifMsgDeleteRange:
        await _handleNotifMsgDeleteRange(packet);
      case Opcode.notifPresence:
        _handlePresence(packet);
      case Opcode.notifChat:
        await _handleNotifChat(packet);
      case Opcode.notifContact:
        await _handleNotifContact(packet);
      case Opcode.notifConfig:
        await _handleNotifConfig(packet);
      case Opcode.notifMsgYouReacted:
        await _handleNotifMsgYouReacted(packet);
    }
  }

  Future<void> _handleNotifContact(Packet packet) async {
    final payload = packet.payload;
    if (payload is! Map) return;
    final accountId = await TokenStorage.getActiveAccountId();
    if (accountId == null) return;
    await ContactsModule.applyContactPush(payload, accountId);
    _bump();
  }

  Future<void> _handleNotifConfig(Packet packet) async {
    final payload = packet.payload;
    if (payload is! Map) return;
    final accountId = await TokenStorage.getActiveAccountId();
    if (accountId == null) return;
    await PrivacyModule.applyConfigPush(accountId, payload);
    final config = payload['config'];
    final server = config is Map ? config['server'] : payload['server'];
    if (server is Map && server.isNotEmpty) {
      await DeletionPolicy.instance.applyServerConfig(
        accountId,
        server,
        complete: false,
      );
      logger.i('NOTIF_CONFIG: ${DeletionPolicy.instance.describe()}');
    }
  }

  Future<void> _handleNotifMsgYouReacted(Packet packet) async {
    final payload = packet.payload;
    if (payload is! Map) return;
    final chatId = payload['chatId'];
    final messageId = payload['messageId']?.toString();
    if (chatId is! int || messageId == null || messageId.isEmpty) return;
    final accountId = await TokenStorage.getActiveAccountId();
    if (accountId == null) return;
    final existing = await AppDatabase.loadMessage(
      accountId,
      chatId,
      messageId,
    );
    if (existing == null) return;
    final payloadMap =
        _decodePayload(existing['payload']) ?? <String, dynamic>{};
    final previous = payloadMap['reactionInfo'];
    final reactionInfo = previous is Map
        ? Map<String, dynamic>.from(previous)
        : <String, dynamic>{};
    final pushedInfo = payload['reactionInfo'];
    if (pushedInfo is Map) {
      reactionInfo.addAll(Map<String, dynamic>.from(pushedInfo));
    }
    final counters = payload['counters'];
    final totalCount = payload['totalCount'];
    if (counters is List) reactionInfo['counters'] = counters;
    if (totalCount is int) reactionInfo['totalCount'] = totalCount;
    final reaction = ownReactionOf(payload);
    if (reaction != null) {
      reactionInfo['yourReaction'] = reaction;
    } else if (_declaresOwnReaction(payload)) {
      reactionInfo.remove('yourReaction');
    }
    final hasCounters =
        reactionInfo['counters'] is List &&
        (reactionInfo['counters'] as List).isNotEmpty;
    if (hasCounters || reactionInfo['yourReaction'] != null) {
      payloadMap['reactionInfo'] = reactionInfo;
    } else {
      payloadMap.remove('reactionInfo');
    }
    final newRow = Map<String, dynamic>.from(existing);
    newRow['payload'] = jsonEncode(payloadMap);
    await AppDatabase.saveMessages([newRow]);
    _messageEventsController.add(
      MessageReactionsChangedEvent(
        chatId,
        messageId,
        payloadMap['reactionInfo'] as Map<String, dynamic>?,
      ),
    );
  }

  static bool _declaresOwnReaction(Map<dynamic, dynamic> payload) {
    final info = payload['reactionInfo'];
    return payload.containsKey('yourReaction') ||
        payload.containsKey('reaction') ||
        (info is Map && info.containsKey('yourReaction'));
  }

  @visibleForTesting
  static String? ownReactionOf(Map<dynamic, dynamic> payload) {
    final info = payload['reactionInfo'];
    for (final raw in [
      payload['yourReaction'],
      payload['reaction'],
      if (info is Map) info['yourReaction'],
    ]) {
      final value = raw is Map ? raw['reaction'] ?? raw['id'] : raw;
      if (value is String && value.isNotEmpty) return value;
    }
    return null;
  }

  Future<void> _handleNotifChat(Packet packet) async {
    final payload = packet.payload;
    if (payload is! Map) return;
    final chat = payload['chat'];
    if (chat is! Map) return;
    final chatId = chat['id'];
    if (chatId is! int) return;
    final accountId = await TokenStorage.getActiveAccountId();
    if (accountId == null) return;
    final rows = await AppDatabase.loadChat(accountId, chatId);
    if (_isCompleteChatPayload(chat) && rows.isNotEmpty) {
      await cacheServerChat(chat.cast<dynamic, dynamic>(), accountId);
      return;
    }
    if (chat['status'] is String && rows.isNotEmpty) {
      await _applyPartialStatus(accountId, chat, rows.first);
    }
    final activeCallData = ChatCall.fromServer(
      chat['videoConversation'],
    )?.encode();
    await _updateChat(
      accountId,
      chatId,
      (cached) => cached.activeCallData == activeCallData
          ? null
          : cached.copyWith(activeCallData: activeCallData),
    );
  }

  Future<void> _applyPartialStatus(
    int accountId,
    Map<dynamic, dynamic> chat,
    Map<String, dynamic> row,
  ) async {
    final chatId = row['id'] as int;
    final previous = row['in_list'] as int?;
    final listState = chatListStateForStatus(
      chat['status'],
      previous: previous,
    );
    if (listState == previous || previous == ChatListState.notInList) return;
    final cached = CachedChat.fromDbRow(row);
    if (previous == ChatListState.visible &&
        _isRemovedDialog(chat, knownType: cached.type)) {
      await _purgeRemovedDialog(accountId, chatId);
    }
    await AppDatabase.setChatListState(accountId, chatId, listState);
    await _notifyChatFromDb(accountId, chatId);
  }

  static bool _isRemovedDialog(
    Map<dynamic, dynamic> chat, {
    String? knownType,
  }) {
    if (chat['status'] != 'REMOVED') return false;
    final type = chat['type'];
    return (type is String ? type : knownType) == 'DIALOG';
  }

  Future<void> _purgeRemovedDialog(int accountId, int chatId) async {
    final ids = await AppDatabase.loadServerMessageIdsBetween(
      accountId,
      chatId,
      fromTime: 0,
      toTime: _endOfTime,
    );
    await _applyServerDeletion(accountId, chatId, ids);
    _historyFetched.remove(chatId);
    _departedChatsController.add(chatId);
  }

  static const int _endOfTime = 8640000000000000;

  static bool _isCompleteChatPayload(Map<dynamic, dynamic> chat) =>
      chat['type'] is String &&
      chat['status'] is String &&
      chat['lastEventTime'] is int &&
      chat['participants'] is Map &&
      (chat['status'] != 'ACTIVE' || chat['newMessages'] is int);

  // #***! присутствие собеседника
  void _handlePresence(Packet packet) {
    final payload = packet.payload;
    if (payload is! Map) return;
    final userId = payload['userId'];
    if (userId is! int) return;
    final presence = payload['presence'];
    if (presence is! Map) return;
    PresenceFetch.apply(userId, Map<String, dynamic>.from(presence));
  }

  // #***! сообщение удалили на сервере
  Future<void> _handleNotifMsgDelete(Packet packet) async {
    final payload = packet.payload;
    if (payload is! Map) return;
    final accountId = await TokenStorage.getActiveAccountId();
    if (accountId == null) return;

    final chatMap = payload['chat'];
    final chatId = await _chatIdOfDeletePush(payload, accountId);
    if (chatId == null) return;

    final ids = payload['messageIds'];
    logger.i(
      'NOTIF_MSG_DELETE чат $chatId, сообщений '
      '${ids is List ? ids.length : 0}',
    );
    if (ids is List) {
      await _applyServerDeletion(accountId, chatId, [
        for (final raw in ids)
          if (raw != null && raw.toString().isNotEmpty) raw.toString(),
      ]);
    }
    if (chatMap is Map) {
      await _notifyChatFromDb(accountId, chatId);
    } else {
      await reconcileLastMessage(accountId, chatId);
    }
  }

  Future<void> _handleNotifMsgDeleteRange(Packet packet) async {
    final payload = packet.payload;
    if (payload is! Map) return;
    final accountId = await TokenStorage.getActiveAccountId();
    if (accountId == null) return;

    final chatId = await _chatIdOfDeletePush(payload, accountId);
    final startTime = payload['startTime'];
    final endTime = payload['endTime'];
    if (chatId == null || endTime is! int) return;
    final from = startTime is int ? startTime : 0;
    if (endTime < from) return;

    final ids = await AppDatabase.loadServerMessageIdsBetween(
      accountId,
      chatId,
      fromTime: from,
      toTime: endTime,
    );
    await _applyServerDeletion(accountId, chatId, ids);
    await reconcileLastMessage(accountId, chatId);
  }

  Future<int?> _chatIdOfDeletePush(
    Map<dynamic, dynamic> payload,
    int accountId,
  ) async {
    final chatMap = payload['chat'];
    if (chatMap is Map && chatMap['id'] is int) {
      await cacheServerChat(chatMap.cast<dynamic, dynamic>(), accountId);
      return chatMap['id'] as int;
    }
    final chatId = payload['chatId'];
    return chatId is int ? chatId : null;
  }

  Future<void> _applyServerDeletion(
    int accountId,
    int chatId,
    List<String> messageIds,
  ) async {
    if (messageIds.isEmpty) return;
    final keepDeleted = ProMaxSettings.viewDeleted.value;
    if (keepDeleted) {
      await AppDatabase.markMessagesDeleted(accountId, chatId, messageIds);
      MessageSessionCache.markDeleted(accountId, chatId, messageIds);
      unawaited(keepDeletedMedia(accountId, chatId, messageIds));
    } else {
      await AppDatabase.deleteMessages(accountId, chatId, messageIds);
      MessageSessionCache.removeMessages(accountId, chatId, messageIds);
    }
    for (final id in messageIds) {
      _messageEventsController.add(
        keepDeleted
            ? MessageMarkedDeletedEvent(chatId, id)
            : MessageRemovedEvent(chatId, id),
      );
    }
  }

  int? _takeTypingTime(int chatId, Map msg) {
    if (!ProMaxSettings.showTypingTime.value) return null;
    final status = msg['status'];
    if (status == 'EDITED' || status == 'REMOVED') return null;
    final senderId = msg['sender'];
    final text = msg['text'];
    if (senderId is! int || text is! String || text.isEmpty) return null;
    return ChatActivityStore.instance.takeTypingTime(chatId, senderId);
  }

  // #***! новое сообщение, комментарии отсеиваем у них свой модуль
  Future<void> _handleNotifMessage(Packet packet) async {
    final payload = packet.payload;
    if (payload is! Map) return;
    final chatId = payload['chatId'];
    if (chatId is! int) return;
    final msg = payload['message'];
    if (msg is! Map) return;

    final msgLink = msg['link'];
    final linkPostId = (msgLink is Map) ? msgLink['postId'] : null;
    final payloadPostId = payload['postId'];
    final isCommentPush =
        payloadPostId is String ||
        (linkPostId is String) ||
        (msg['postId'] is String);
    if (isCommentPush) return;

    final typingMs = _takeTypingTime(chatId, msg);

    final accountId = await TokenStorage.getActiveAccountId();
    if (accountId == null) return;

    final senderId = msg['sender'] as int?;
    final msgIdStr = msg['id']?.toString();
    final msgIdInt = (msg['id'] is int)
        ? msg['id'] as int
        : int.tryParse(msgIdStr ?? '');
    final msgTime = msg['time'] as int?;
    final msgText = msg['text'] as String?;
    final status = msg['status'] as String?;
    final unread = payload['unread'] as int?;

    await IgnoredSenders.instance.load();
    if (IgnoredSenders.instance.hidesFromDialog(
      accountId: accountId,
      chatId: chatId,
      senderId: senderId,
    )) {
      if (status != 'REMOVED' && msgIdStr != null) {
        _discardIgnored(chatId, [msgIdStr]);
      }
      return;
    }

    var rows = await AppDatabase.loadChat(accountId, chatId);
    // #***! чата нет в базе, нас только что добавили, тянем карточку
    if (rows.isEmpty) {
      try {
        final chatInfo = await ChatInfoFetch.get(chatId, forceRefresh: true);
        if (chatInfo != null) {
          await cacheServerChat(chatInfo.raw, accountId);
        }
      } catch (e) {
        logger.w(
          'notifMessage: fetch info for unknown chat $chatId failed: $e',
        );
        return;
      }
      rows = await AppDatabase.loadChat(accountId, chatId);
      if (rows.isEmpty) return;
    }

    if (senderId == accountId && status != 'REMOVED' && status != 'EDITED') {
      await _listPreviewChat(accountId, chatId);
    }

    if (status == 'REMOVED' && msgIdStr != null) {
      await _applyServerDeletion(accountId, chatId, [msgIdStr]);
      final cachedChat = CachedChat.fromDbRow(rows.first);
      if (cachedChat.lastMsgId == msgIdInt) {
        await _reconcileLastMessage(
          accountId,
          chatId,
          rows.first,
          unread: unread,
        );
      } else if (unread != null) {
        final newRow = Map<String, dynamic>.from(rows.first);
        newRow['unread_count'] = unread;
        await _applyLocalReadState(newRow);
        await _commitChatContent([(rows.first, newRow)]);
      }
      final freshRows = await AppDatabase.loadChat(accountId, chatId);
      if (freshRows.isNotEmpty) {
        _applyChatToMemory(
          CachedChat.fromDbRow(freshRows.first),
          inList: freshRows.first['in_list'] as int? ?? 1,
        );
      }
      return;
    }

    final existing = msgIdStr == null
        ? null
        : await AppDatabase.loadMessage(accountId, chatId, msgIdStr);
    if (status == 'EDITED' && existing != null) {
      final mergedPayload =
          _decodePayload(existing['payload']) ?? Map<String, dynamic>.from(msg);
      for (final entry in msg.entries) {
        if (entry.key == 'reactionInfo') continue;
        mergedPayload[entry.key.toString()] = entry.value;
      }
      final newRow = Map<String, dynamic>.from(existing);
      if (ProMaxSettings.viewRedacted.value) {
        final oldText = existing['text']?.toString();
        if ((oldText ?? '') != (msgText ?? '') &&
            oldText != null &&
            oldText.isNotEmpty) {
          final history = CachedMessage.appendEditHistory(
            CachedMessage.parseEditHistory(existing['edit_history']),
            oldText,
            DateTime.now().millisecondsSinceEpoch,
          );
          newRow['edit_history'] = jsonEncode(history);
        }
      }
      final wasEncrypted =
          (existing['e2ee'] as int? ?? CachedMessage.e2eeNone) !=
          CachedMessage.e2eeNone;
      newRow['text'] = msgText;
      newRow['status'] = status;
      newRow['payload'] = jsonEncode(mergedPayload);
      newRow['text_sealed'] = null;
      newRow['e2ee'] = CachedMessage.e2eeNone;
      final inspected = await E2eeService.instance.inspect(
        CachedMessage.fromDbRow(newRow),
      );
      // #***! правка без расшифровки не от собеседника, применять нельзя
      if (wasEncrypted && inspected.e2ee != CachedMessage.e2eeText) {
        logger.w('notifMessage: отклонена правка $msgIdStr без расшифровки');
        return;
      }
      newRow['text_sealed'] = inspected.sealedText;
      newRow['e2ee'] = inspected.e2ee;
      await AppDatabase.saveMessages([newRow]);
      _messageEventsController.add(
        MessageEditedEvent(chatId, CachedMessage.fromDbRow(newRow)),
      );
    } else if (msgIdStr != null &&
        existing == null &&
        !(senderId == accountId &&
            await _adoptSentEcho(accountId, chatId, msg))) {
      final cached = await E2eeService.instance.inspect(
        CachedMessage.fromPushPayload(
          accountId,
          chatId,
          msg,
        ).copyWith(typingMs: typingMs),
        commit: (decrypted) => AppDatabase.saveMessages([decrypted.toDbRow()]),
      );
      await AppDatabase.saveMessages([cached.toDbRow()]);
      await _extendHistoryCoverage(accountId, chatId, rows.first, cached.time);
      _applyMembershipControl(accountId, chatId, cached);
      _messageEventsController.add(MessageAddedEvent(chatId, cached));
    }

    final cached = CachedChat.fromDbRow(rows.first);
    final isStaleLast =
        status != 'REMOVED' &&
        msgIdInt != null &&
        cached.lastMsgId == msgIdInt &&
        status != 'EDITED';
    if (isStaleLast) {
      return;
    }

    final newRow = Map<String, dynamic>.from(rows.first);
    if (status != 'REMOVED') {
      if (msgIdInt != null) newRow['last_msg_id'] = msgIdInt;
      if (msgTime != null) {
        newRow['last_msg_time'] = msgTime;
        if (status != 'EDITED') {
          newRow['last_event_time'] = msgTime;
        }
      }
      newRow['last_msg_text'] = messagePreviewText(msg);
      newRow['last_msg_elements'] = messagePreviewElements(msg);
      newRow['last_msg_preview'] = messagePreviewMedia(msg);
      if (senderId != null) newRow['last_msg_sender'] = senderId;
      newRow['last_msg_status'] = 'sent';
    }
    if (unread != null) {
      newRow['unread_count'] = unread;
      await _applyLocalReadState(newRow);
    }

    if (msgIdInt != null &&
        status != 'REMOVED' &&
        senderId != accountId &&
        messageMentionsUser(msg, accountId)) {
      newRow['last_mention_msg_id'] = msgIdInt;
    }

    final pinned = _extractPinnedMessage(msg);
    if (pinned != null) {
      newRow['pinned_msg_id'] = pinned.id;
      newRow['pinned_msg_text'] = pinned.text;
      newRow['pinned_msg_time'] = pinned.time;
      newRow['pinned_msg_is_preview'] = pinned.isPreview ? 1 : 0;
    }

    await _commitChatContent([(rows.first, newRow)]);
  }

  void _discardIgnored(int chatId, List<String> messageIds) {
    final api = _pushApi;
    if (api == null) return;
    MessagesModule(api).discardIgnored(chatId, messageIds);
  }

  void _hideIgnoredDialog(Map<String, dynamic> row, CachedChat? existing) {
    final accountId = row['account_id'] as int;
    final chatId = row['id'] as int;
    final peer = IgnoredSenders.instance.ignoredPeer(accountId, chatId);
    if (peer == null) return;
    row['unread_count'] = 0;
    if (row['last_msg_sender'] != peer) return;
    final lastId = row['last_msg_id'];
    if (lastId is int) _discardIgnored(chatId, ['$lastId']);
    final previous = existing?.toDbRow();
    final keep = previous != null && previous['last_msg_sender'] != peer;
    for (final key in _lastMessageColumns) {
      row[key] = keep ? previous[key] : null;
    }
    if (!keep) row['last_msg_text'] = lastMsgPlaceholder;
    if (previous != null) row['last_event_time'] = previous['last_event_time'];
  }

  static const _lastMessageColumns = [
    'last_msg_id',
    'last_msg_time',
    'last_msg_text',
    'last_msg_elements',
    'last_msg_preview',
    'last_msg_sender',
    'last_msg_status',
  ];

  Future<bool> _adoptSentEcho(int accountId, int chatId, Map msg) async {
    final cid = MessagesModule.clientIdOf({'cid': msg['cid']});
    if (cid == null) return false;
    final unsent = await AppDatabase.loadUnsentOwnMessages(accountId, chatId);
    for (final row in unsent) {
      final temp = CachedMessage.fromDbRow(row);
      if (MessagesModule.clientIdOf(temp.payload) != cid) continue;
      final sent = CachedMessage.fromPushPayload(
        accountId,
        chatId,
        msg,
      ).copyWith(status: 'sent', sealedText: temp.sealedText, e2ee: temp.e2ee);
      await AppDatabase.saveMessages([sent.toDbRow()]);
      await AppDatabase.deleteMessage(accountId, chatId, temp.id);
      MessageDecryptionCache.instance.adopt(temp.id, sent.id);
      MessageSessionCache.replace(accountId, chatId, temp.id, (_) => sent);
      emitMessageSent(chatId, temp.id, sent);
      return true;
    }
    return false;
  }

  ({int? id, String? text, int? time, bool isPreview})? _extractPinnedMessage(
    Map msg,
  ) {
    final attaches = msg['attaches'];
    if (attaches is! List) return null;
    for (final a in attaches.whereType<Map>()) {
      if ((a['_type'] as String?) != 'CONTROL') continue;
      final event = a['event']?.toString();
      if (event != 'pin' && event != 'unpin') continue;
      final pinned = a['pinnedMessage'];
      if (event == 'unpin' || pinned is! Map) {
        return (id: null, text: null, time: null, isPreview: false);
      }
      final rawId = pinned['id'];
      final id = rawId is int ? rawId : int.tryParse(rawId?.toString() ?? '');
      if (id == null) return null;
      final preview = pinnedMessagePreview(pinned.cast<dynamic, dynamic>());
      return (
        id: id,
        text: preview.text,
        time: pinned['time'] as int?,
        isPreview: preview.isPreview,
      );
    }
    return null;
  }

  // #***! пересобираем последнее сообщение из истории, пусто ставим маркер
  Future<void> _reconcileLastMessage(
    int accountId,
    int chatId,
    Map<String, dynamic> chatRow, {
    int? unread,
  }) async {
    final latest = await AppDatabase.loadMessages(
      accountId,
      chatId,
      limit: 1,
      onlyVisible: true,
    );
    final newRow = Map<String, dynamic>.from(chatRow);
    if (latest.isNotEmpty) {
      final m = latest.first;
      final rawText = m['text']?.toString();
      String? previewText = rawText;
      String? elementsJson;
      String? previewMedia;
      final payload = _decodePayload(m['payload']);
      if (payload != null) previewMedia = messagePreviewMedia(payload);
      if (rawText == null || rawText.isEmpty) {
        if (payload != null) previewText = messagePreviewText(payload);
      } else {
        if (payload != null) elementsJson = messagePreviewElements(payload);
      }
      newRow['last_msg_id'] = int.tryParse(m['id']?.toString() ?? '');
      newRow['last_msg_text'] = previewText ?? m['text'];
      newRow['last_msg_elements'] = elementsJson;
      newRow['last_msg_preview'] = previewMedia;
      newRow['last_msg_time'] = m['time'];
      newRow['last_msg_sender'] = m['sender_id'];
      newRow['last_msg_status'] = m['status'];
    } else {
      newRow['last_msg_id'] = null;
      newRow['last_msg_text'] = lastMsgPlaceholder;
      newRow['last_msg_elements'] = null;
      newRow['last_msg_preview'] = null;
      newRow['last_msg_sender'] = null;
      newRow['last_msg_status'] = null;
    }
    if (unread != null) {
      newRow['unread_count'] = unread;
      await _applyLocalReadState(newRow);
    }
    await _commitChatContent([(chatRow, newRow)]);
  }

  // #***! после истории меняем маркер на настоящее сообщение
  /// Вызывается после успешного фетча истории чата —
  /// если в превью был placeholder, заменяем его на актуальное
  /// последнее сообщение из кеша.
  Future<void> reconcileLastMessageIfPlaceholder(
    int accountId,
    int chatId,
  ) async {
    final rows = await AppDatabase.loadChat(accountId, chatId);
    if (rows.isEmpty) return;
    final chat = CachedChat.fromDbRow(rows.first);
    if (!chat.isLastMsgDeleted) return;
    await _reconcileLastMessage(accountId, chatId, rows.first);
    await _notifyChatFromDb(accountId, chatId);
  }

  Future<void> reconcileLastMessage(int accountId, int chatId) async {
    final rows = await AppDatabase.loadChat(accountId, chatId);
    if (rows.isEmpty) return;
    await _reconcileLastMessage(accountId, chatId, rows.first);
    await _notifyChatFromDb(accountId, chatId);
  }

  // #***! перечитать чат из базы и обновить точечный кэш
  Future<void> _notifyChatFromDb(int accountId, int chatId) async {
    final rows = await AppDatabase.loadChat(accountId, chatId);
    if (rows.isEmpty) return;
    _applyChatToMemory(
      CachedChat.fromDbRow(rows.first),
      inList: rows.first['in_list'] as int? ?? 1,
    );
  }

  // #***! сверяем что удалили на сервере
  Future<List<String>> reconcileDeletedFromFetch(
    int accountId,
    int chatId,
    HistoryPage page,
  ) async {
    final window = page.window;
    if (window == null) return const [];
    final local = await AppDatabase.loadServerMessageIdsBetween(
      accountId,
      chatId,
      fromTime: window.start,
      toTime: window.end,
    );
    final vanished = [
      for (final id in local)
        if (!page.serverIds.contains(id)) id,
    ];
    if (vanished.isEmpty) return const [];
    await _applyServerDeletion(accountId, chatId, vanished);
    await reconcileLastMessage(accountId, chatId);
    return vanished;
  }

  // #***! пуш про реакции
  Future<void> _handleNotifMsgReactionsChanged(Packet packet) async {
    final payload = packet.payload;
    if (payload is! Map) return;
    final chatId = payload['chatId'];
    if (chatId is! int) return;
    final messageId = payload['messageId']?.toString();
    if (messageId == null || messageId.isEmpty) return;

    final accountId = await TokenStorage.getActiveAccountId();
    if (accountId == null) return;

    final existing = await AppDatabase.loadMessage(
      accountId,
      chatId,
      messageId,
    );
    if (existing == null) return;

    final payloadMap =
        _decodePayload(existing['payload']) ?? <String, dynamic>{};

    final counters = payload['counters'];
    final totalCount = payload['totalCount'];
    final reactionInfo = <String, dynamic>{};
    final prev = payloadMap['reactionInfo'];
    if (prev is Map && prev['yourReaction'] != null) {
      reactionInfo['yourReaction'] = prev['yourReaction'];
    }
    if (counters is List) reactionInfo['counters'] = counters;
    if (totalCount is int) reactionInfo['totalCount'] = totalCount;
    if (reactionInfo['counters'] == null ||
        (counters is List && counters.isEmpty)) {
      payloadMap.remove('reactionInfo');
    } else {
      payloadMap['reactionInfo'] = reactionInfo;
    }

    final newRow = Map<String, dynamic>.from(existing);
    newRow['payload'] = jsonEncode(payloadMap);
    await AppDatabase.saveMessages([newRow]);
    final emitted = payloadMap['reactionInfo'] as Map<String, dynamic>?;
    _messageEventsController.add(
      MessageReactionsChangedEvent(chatId, messageId, emitted),
    );
  }

  // #***! пуш про прочтение с другого устройства
  Future<void> _handleNotifMark(Packet packet, int receivedAt) async {
    final payload = packet.payload;
    if (payload is! Map) return;
    final chatId = payload['chatId'];
    if (chatId is! int) return;
    final userId = payload['userId'];
    if (userId is! int) return;
    final mark = payload['mark'];
    if (mark is! int) return;
    if (payload['setAsUnread'] == true) return;

    final accountId = await TokenStorage.getActiveAccountId();
    if (accountId == null) return;

    final rows = await AppDatabase.loadChat(accountId, chatId);
    if (rows.isEmpty) return;
    final cached = CachedChat.fromDbRow(rows.first);
    final ownRead = userId == accountId;
    final previousMark = cached.participants[userId];
    final storedMark = !ownRead && previousMark != null
        ? math.max(previousMark, mark)
        : mark;
    if (!ownRead) {
      await _recordPeerRead(
        accountId,
        chatId,
        userId,
        cached,
        storedMark,
        receivedAt,
      );
    }
    final serverUnread = payload['unread'];
    final lastTime = cached.lastMsgTime;
    final unread = !ownRead
        ? cached.unreadCount
        : serverUnread is int
        ? serverUnread
        : lastTime != null && mark >= lastTime
        ? 0
        : cached.unreadCount;
    if (previousMark == storedMark && unread == cached.unreadCount) {
      return;
    }
    final updated = cached.copyWith(
      unreadCount: unread,
      participants: Map<int, int>.from(cached.participants)
        ..[userId] = storedMark,
    );
    final row = updated.toDbRow();
    if (ownRead) {
      await _applyLocalReadState(row, updateServerMark: true);
    }
    await _commitChatContent([(rows.first, row)]);
    if (ownRead && row['unread_count'] == 0) {
      unawaited(PushService.clearChatNotification(chatId));
    }
  }

  Future<void> _recordPeerRead(
    int accountId,
    int chatId,
    int userId,
    CachedChat cached,
    int mark,
    int receivedAt,
  ) async {
    final receipts = ReadReceipts.instance;
    await receipts.preload(accountId, chatId);
    final base = _readBaselines.baseFor(
      accountId,
      chatId,
      userId,
      knownMarks: [
        ?cached.participants[userId],
        ?receipts.latestMark(accountId, chatId, userId),
      ],
    );
    _readBaselines.confirm(accountId, chatId, userId, mark);
    if (base == null || mark <= base) return;
    await receipts.record(
      accountId,
      chatId,
      ReadReceipt(
        userId: userId,
        prevMark: base,
        mark: mark,
        readAt: receivedAt,
      ),
    );
  }

  // #***! обновления контактов копим 250 мс, их прилетают сотни
  final Set<int> _pendingContactUpdates = {};
  Timer? _contactFlushTimer;
  Future<void>? _contactFlushFuture;
  static const _contactFlushDelay = Duration(milliseconds: 250);

  void applyContactUpdate(int contactId) {
    _pendingContactUpdates.add(contactId);
    if (_contactFlushTimer != null) return;
    if (_contactFlushFuture != null) return;
    _contactFlushTimer = Timer(_contactFlushDelay, _kickFlush);
  }

  void _kickFlush() {
    _contactFlushTimer = null;
    if (_contactFlushFuture != null) return;
    _contactFlushFuture = _flushContactUpdates().whenComplete(() {
      _contactFlushFuture = null;
      if (_pendingContactUpdates.isNotEmpty) {
        _contactFlushTimer ??= Timer(_contactFlushDelay, _kickFlush);
      }
    });
  }

  Future<void> _flushContactUpdates() async {
    if (_pendingContactUpdates.isEmpty) return;
    final ids = _pendingContactUpdates.toList();
    _pendingContactUpdates.clear();

    final accountId = await TokenStorage.getActiveAccountId();
    if (accountId == null) return;

    final dialogRows = await AppDatabase.loadDialogChats(accountId);
    final byParticipant =
        <int, List<({Map<String, dynamic> row, CachedChat cached})>>{};
    for (final row in dialogRows) {
      final cached = CachedChat.fromDbRow(row);
      for (final pid in cached.participants.keys) {
        if (pid == accountId) continue;
        byParticipant.putIfAbsent(pid, () => []).add((
          row: row,
          cached: cached,
        ));
      }
    }

    final updates = <(Map<String, dynamic>, Map<String, dynamic>)>[];
    for (final contactId in ids) {
      final name = ContactCache.get(contactId);
      if (name == null) continue;
      final avatar = ContactCache.getAvatar(contactId);
      final options = ContactCache.getOptions(contactId) ?? const <String>{};
      final affected = byParticipant[contactId];
      if (affected == null) continue;
      for (final entry in affected) {
        final row = entry.row;
        final cached = entry.cached;
        final sameTitle = cached.title == name;
        final sameAvatar = (cached.iconUrl ?? '') == (avatar ?? '');
        final sameOptions =
            cached.options.length == options.length &&
            cached.options.containsAll(options);
        if (sameTitle && sameAvatar && sameOptions) continue;
        final newRow = Map<String, dynamic>.from(row);
        newRow['title'] = name;
        newRow['icon_url'] = avatar;
        newRow['options'] = options.isEmpty ? null : options.join(',');
        updates.add((row, newRow));
      }
    }
    await _commitChatContent(updates);
  }

  // #***! карточка с сервера в кэш
  Future<CachedChat?> cacheServerChat(
    Map<dynamic, dynamic> chat,
    int accountId, {
    Map<int, CachedChat>? preloadedExisting,
    Map<int, int>? preloadedListState,
    bool inList = true,
  }) async {
    final cachedAt = DateTime.now().millisecondsSinceEpoch;
    final id = chat['id'];
    ChatMembersStore.instance.applyChatPayload(chat);
    _confirmReadMarks(accountId, chat);
    Map<int, CachedChat> existing = const {};
    int? previousListState;
    if (preloadedExisting != null) {
      existing = preloadedExisting;
      if (id is int) previousListState = preloadedListState?[id];
    } else if (id is int) {
      final rows = await AppDatabase.loadChat(accountId, id);
      if (rows.isNotEmpty) {
        final existingRow = rows.first;
        previousListState = existingRow['in_list'] as int?;
        existing = {id: CachedChat.fromDbRow(existingRow)};
      }
    }
    final parsed = parseChatRow(
      chat,
      accountId,
      accountId,
      const {},
      const {},
      const {},
      existing,
      cachedAt,
    );
    if (parsed == null) {
      logger.w('cacheServerChat: parse returned null for chat=${chat['id']}');
      return null;
    }
    final ex = existing[parsed.id];
    final listState = !inList
        ? ChatListState.notInList
        : chatListStateForStatus(chat['status'], previous: previousListState);
    if (previousListState == ChatListState.visible &&
        _isRemovedDialog(chat, knownType: ex?.type)) {
      await _purgeRemovedDialog(accountId, parsed.id);
    }
    final membershipUnchanged =
        previousListState == null || previousListState == listState;
    if (ex != null && sameChatContent(ex, parsed) && membershipUnchanged) {
      return parsed;
    }
    final row = parsed.toDbRow();
    await _applyLocalReadState(row, updateServerMark: true);
    await IgnoredSenders.instance.load();
    _hideIgnoredDialog(row, ex);
    row['in_list'] = listState;
    await AppDatabase.saveChats([row]);
    final adjusted = CachedChat.fromDbRow(row);
    _applyChatToMemory(adjusted, inList: listState);
    return adjusted;
  }

  // #***! чаты из ответа login
  /// Парсит и кэширует чаты из payload opcode 19.
  ///
  /// Для диалогов разрезолвит имя и аватар из списка [contacts] того же
  /// ответа. На warm start контакты не приходят — используется существующий
  /// кэш.
  Future<void> syncFromLoginPayload(
    Map<dynamic, dynamic> data,
    int accountId,
    int currentUserId,
  ) async {
    try {
      final chats = data['chats'];
      if (chats is! List || chats.isEmpty) return;

      final contactsMap = buildContactsMap(data['contacts']);
      // Config contains mute setup and fav indexes: config -> chats -> id
      final configMap = data['config'] is Map ? data['config'] as Map : {};
      final chatsConfig = configMap['chats'] is Map
          ? configMap['chats'] as Map
          : {};

      // Presence for online statuses
      final presenceMap = data['presence'] is Map
          ? data['presence'] as Map
          : {};
      PresenceFetch.primeAll(presenceMap);

      await _persistChatMaps(
        chats,
        accountId,
        currentUserId,
        contactsMap: contactsMap,
        chatsConfig: chatsConfig,
        presenceMap: presenceMap,
      );
    } catch (e) {
      logger.e("Ошибка при синке: $e");
    }
  }

  // #***! пишем пачку с проверкой изменилось ли что
  Future<int> _persistChatMaps(
    List<dynamic> chats,
    int accountId,
    int currentUserId, {
    Map<int, Map<dynamic, dynamic>> contactsMap = const {},
    Map<dynamic, dynamic> chatsConfig = const {},
    Map<dynamic, dynamic> presenceMap = const {},
  }) async {
    final cachedAt = DateTime.now().millisecondsSinceEpoch;
    await IgnoredSenders.instance.load();
    final existingRows = await AppDatabase.loadChats(
      accountId,
      includeHidden: true,
    );
    final existing = {
      for (final row in existingRows)
        row['id'] as int: CachedChat.fromDbRow(row),
    };
    final existingListState = {
      for (final row in existingRows) row['id'] as int: row['in_list'] as int,
    };

    final rows = <Map<String, dynamic>>[];
    final removedDialogs = <int>[];
    for (final c in chats.whereType<Map>()) {
      final map = c.cast<dynamic, dynamic>();
      ChatMembersStore.instance.applyChatPayload(map);
      _confirmReadMarks(accountId, map);
      final parsed = parseChatRow(
        map,
        accountId,
        currentUserId,
        contactsMap,
        chatsConfig,
        presenceMap,
        existing,
        cachedAt,
      );
      if (parsed == null) continue;
      final row = parsed.toDbRow();
      await _applyLocalReadState(row, updateServerMark: true);
      _hideIgnoredDialog(row, existing[parsed.id]);
      row['in_list'] = chatListStateForStatus(
        map['status'],
        previous: existingListState[parsed.id],
      );
      if (existingListState[parsed.id] == ChatListState.visible &&
          _isRemovedDialog(map, knownType: existing[parsed.id]?.type)) {
        removedDialogs.add(parsed.id);
      }
      rows.add(row);
    }

    for (final chatId in removedDialogs) {
      await _purgeRemovedDialog(accountId, chatId);
    }
    if (rows.isNotEmpty) {
      await AppDatabase.saveChats(rows);
      for (final row in rows) {
        _applyChatToMemory(
          CachedChat.fromDbRow(row),
          inList: row['in_list'] as int? ?? 1,
        );
      }
    }
    return rows.length;
  }

  // #***! остальные страницы в фоне после входа
  Future<void> paginateChats(
    Api api,
    int accountId,
    int currentUserId,
    Map<dynamic, dynamic> loginData,
  ) async {
    if (_paginatedAccountId == accountId) return;
    _paginatedAccountId = accountId;
    try {
      var marker = loginData['chatMarker'];
      if (marker is! int || marker <= 0) return;

      const count = 50;
      var page = 0;
      while (page < 200) {
        page++;
        final resp = await api.sendRequestMap(Opcode.chatsList, {
          'marker': marker,
          'count': count,
        });
        if (resp == null) break;
        final chats = resp['chats'];
        if (chats is! List || chats.isEmpty) break;

        await _persistChatMaps(chats, accountId, currentUserId);

        final next = resp['marker'];
        if (next is! int || next == marker || chats.length < count) break;
        marker = next;
      }
      await applyFavorites(accountId);
    } catch (e) {
      _paginatedAccountId = null;
      logger.w('Пагинация чатов: $e');
    }
  }

  // #***! дальше чтение из базы, основной путь для юишки
  final Set<int> _repairedSenders = {};

  Future<List<CachedChat>> getChats(
    int accountId, {
    bool includeHidden = false,
  }) async {
    try {
      if (_repairedSenders.add(accountId)) {
        await AppDatabase.repairLastMessageSenders(accountId);
      }
      final rows = await AppDatabase.loadChats(
        accountId,
        includeHidden: includeHidden,
      );
      final chats = rows
          .map(CachedChat.fromDbRow)
          .where((chat) => !DoubleBottom.hides(chat.id))
          .toList();
      return chats;
    } catch (e) {
      logger.e("Ошибка при получении чатов: $e");
      return [];
    }
  }

  Future<List<CachedChat>> getChat(int accountId, int chatId) async {
    try {
      final rows = await AppDatabase.loadChat(accountId, chatId);

      return rows.map(CachedChat.fromDbRow).toList();
    } catch (e) {
      logger.e("Ошибка при получении чата: $e");

      return [];
    }
  }

  Future<void> clearCache(int accountId) =>
      AppDatabase.clearChatsCache(accountId);

  // #***! полная карточка с сервера
  Future<Map<String, dynamic>?> getChatInfo(Api api, int chatId) async {
    final packet = await api.sendRequest(Opcode.chatInfo, {
      'chatIds': [chatId],
    });
    if (packet.isError) return null;
    final payload = packet.payload as Map?;
    final chats = payload?['chats'] as List?;
    if (chats == null || chats.isEmpty) return null;
    final info = Map<String, dynamic>.from(chats.first as Map);
    ChatMembersStore.instance.applyChatPayload(info);
    return info;
  }

  // #***! кто докуда дочитал
  Future<Map<int, int>> getReadMarks(Api api, int accountId, int chatId) async {
    try {
      final info = await getChatInfo(api, chatId);
      final fresh = parseParticipants(info?['participants']);
      if (fresh.isNotEmpty) return fresh;
    } catch (e) {
      logger.w('Не удалось получить отметки прочтения для $chatId: $e');
    }
    final rows = await getChat(accountId, chatId);
    return rows.isEmpty ? const {} : rows.first.participants;
  }

  // #***! поиск чата по id юзера
  Future<dynamic> searchById(Api api, int userId) async {
    final packet = await api.sendRequest(Opcode.publicSearch, {
      'query': userId.toString(),
      'from': 0,
      'count': 10,
    });
    return packet.payload;
  }

  // #***! поиск по сообщениям
  Future<List<MessageSearchHit>> searchMessages(
    Api api,
    String query, {
    int count = 50,
  }) async {
    final term = query.trim();
    if (term.isEmpty) return const [];
    try {
      final packet = await api.sendRequest(Opcode.chatSearch, {
        'count': count,
        'query': term,
      });
      if (packet.isError) return const [];
      return parseMessageResult(packet.payload);
    } catch (e) {
      logger.w('searchMessages failed: $e');
      return const [];
    }
  }

  // #***! поиск публичных чатов и каналов
  Future<List<ChatSearchHit>> searchPublic(
    Api api,
    String query, {
    int count = 20,
  }) async {
    final term = query.trim();
    if (term.isEmpty) return const [];
    try {
      final packet = await api.sendRequest(Opcode.publicSearch, {
        'type': 'ALL',
        'count': count,
        'query': term,
      });
      if (packet.isError) return const [];
      return parseSearchResult(packet.payload);
    } catch (e) {
      logger.w('searchPublic failed: $e');
      return const [];
    }
  }

  // #***! подписка на канал
  Future<void> subscribeChat(
    Api api,
    int chatId, {
    bool subscribe = true,
  }) async {
    try {
      await api.sendRequest(Opcode.chatSubscribe, {
        'chatId': chatId,
        'subscribe': subscribe,
      }, silent: true);
    } catch (e) {
      logger.w('subscribeChat failed: $e');
    }
  }

  // #***! вступление по ссылке
  Future<({CachedChat chat, int? subscribersCount})> joinChannel(
    Api api,
    String link,
    int accountId,
  ) async {
    final packet = await api.sendRequest(Opcode.chatJoin, {
      'link': link,
    }, silent: true);
    if (!packet.isOk) {
      throw PacketError(messageFromErrorPayload(packet.payload));
    }
    final payload = packet.payload;
    final chatMap = payload is Map ? payload['chat'] : null;
    if (chatMap is! Map) {
      throw const PacketError('Не удалось подписаться');
    }
    final cached = await cacheServerChat(chatMap, accountId);
    if (cached == null) {
      throw const PacketError('Не удалось подписаться');
    }
    final count = chatMap['participantsCount'];
    if (count is! int) ChatMembersStore.instance.adjust(cached.id, 1);
    _refreshChatInfo(cached.id);
    return (chat: cached, subscribersCount: count is int ? count : null);
  }

  // #***! проверить что чат в кэше, иначе дозапросить
  Future<bool> ensureChatCached(Api api, int accountId, int chatId) async {
    final rows = await AppDatabase.loadChat(accountId, chatId);
    if (rows.isNotEmpty) return true;
    try {
      final info = await getChatInfo(api, chatId);
      if (info == null) return false;
      await cacheServerChat(info, accountId, inList: false);
      return true;
    } catch (e) {
      logger.w('ensureChatCached failed for $chatId: $e');
      return false;
    }
  }

  // #***! создание группы
  Future<CachedChat?> createGroupChat(
    Api api, {
    required String title,
    required List<int> userIds,
    bool notify = true,
  }) => _createChat(
    api,
    chatType: 'CHAT',
    title: title,
    userIds: userIds,
    notify: notify,
  );

  // #***! создание канала
  Future<CachedChat?> createChannel(
    Api api, {
    required String title,
    List<int> userIds = const [],
    bool notify = true,
  }) => _createChat(
    api,
    chatType: 'CHANNEL',
    title: title,
    userIds: userIds,
    notify: notify,
  );

  // #***! общее создание, отличается набором опций
  Future<CachedChat?> _createChat(
    Api api, {
    required String chatType,
    required String title,
    required List<int> userIds,
    required bool notify,
  }) async {
    final payload = {
      'message': {
        'cid': DateTime.now().millisecondsSinceEpoch,
        'attaches': [
          {
            '_type': 'CONTROL',
            'event': 'new',
            'chatType': chatType,
            'title': title,
            'userIds': userIds,
          },
        ],
      },
      'notify': notify,
    };
    final packet = await api.sendRequest(Opcode.msgSend, payload);
    if (!packet.isOk) {
      logger.w(
        '_createChat($chatType): server error payload=${packet.payload}',
      );
      return null;
    }
    final data = packet.payload;
    if (data is! Map) {
      logger.w('_createChat($chatType): payload is not a Map: $data');
      return null;
    }
    final chat = data['chat'];
    if (chat is! Map) {
      logger.w('_createChat($chatType): response has no chat field: $data');
      return null;
    }
    final accountId = await TokenStorage.getActiveAccountId();
    if (accountId == null) {
      logger.w('_createChat($chatType): no active account id');
      return null;
    }
    return cacheServerChat(chat, accountId);
  }

  // #***! url под аватарку чата
  Future<String?> requestChatPhotoUploadUrl(Api api) async {
    final packet = await api.sendRequest(Opcode.photoUpload, {'count': 1});
    if (!packet.isOk) return null;
    final data = packet.payload;
    if (data is! Map) return null;
    return data['url'] as String?;
  }

  Future<bool> setChatPhoto(
    Api api, {
    required int chatId,
    required String photoToken,
  }) async {
    return api.sendRequestOk(Opcode.chatUpdate, {
      'chatId': chatId,
      'photoToken': photoToken,
    });
  }

  // #***! настройки чата, кто что может
  Future<bool> setChatOptions(
    Api api, {
    required int chatId,
    required Map<String, dynamic> options,
  }) async {
    return api.sendRequestOk(Opcode.chatUpdate, {
      'chatId': chatId,
      'options': options,
    });
  }

  Future<bool> setChatTitle(
    Api api, {
    required int chatId,
    required String title,
  }) async {
    final packet = await api.sendRequest(Opcode.chatUpdate, {
      'chatId': chatId,
      'theme': title,
    });
    if (!packet.isOk) return false;
    final accountId = await TokenStorage.getActiveAccountId();
    if (accountId == null) return true;
    await _updateChat(accountId, chatId, (chat) => chat.copyWith(title: title));
    return true;
  }

  // #***! закрепление сообщения
  Future<String?> setPinnedMessage(
    Api api, {
    required int chatId,
    required int? messageId,
    bool notify = true,
  }) async {
    try {
      final packet = await api.sendRequest(Opcode.chatUpdate, {
        'chatId': chatId,
        'notifyPin': notify,
        'pinMessageId': messageId ?? 0,
      });
      if (!packet.isOk) {
        return messageFromErrorPayload(packet.payload);
      }
      final data = packet.payload;
      final chat = data is Map ? data['chat'] : null;
      if (chat is Map) {
        final accountId = await TokenStorage.getActiveAccountId();
        if (accountId != null) {
          await cacheServerChat(chat.cast<dynamic, dynamic>(), accountId);
        }
      }
      return null;
    } on PacketError catch (e) {
      logger.w('setPinnedMessage $chatId: ${e.message}');
      return e.message;
    } catch (e) {
      logger.w('setPinnedMessage $chatId: $e');
      return 'Не удалось изменить закрепление';
    }
  }

  // #***! переключение закрепа по текущему состоянию
  Future<String?> togglePin(
    Api api, {
    required List<int> chatIds,
    required bool pin,
  }) async {
    if (chatIds.isEmpty) return null;
    try {
      final accountId = await TokenStorage.getActiveAccountId();
      if (accountId == null) return 'Нет активного аккаунта';
      final folders = await FoldersModule.loadFolders(accountId);
      final allFolder = folders.firstWhere(
        FoldersModule.isAllChatsFolder,
        orElse: () => folders.isEmpty
            ? throw StateError('Папка "Все" не найдена')
            : folders.first,
      );

      final favorites = List<int>.from(allFolder.favorites);
      if (pin) {
        for (final id in chatIds) {
          if (!favorites.contains(id)) favorites.add(id);
        }
      } else {
        favorites.removeWhere((id) => chatIds.contains(id));
      }

      await FoldersModule.setFolderFavorites(
        api,
        accountId,
        allFolder,
        favorites,
      );

      final existingRows = await AppDatabase.loadChatsByIds(accountId, chatIds);
      final updates = <(Map<String, dynamic>, Map<String, dynamic>)>[];
      for (final row in existingRows) {
        final id = row['id'] as int;
        final isFav = favorites.contains(id);
        final currentFav = row['fav_index'] as int?;
        final newFav = isFav
            ? ((currentFav ?? 0) > 0 ? currentFav : favorites.indexOf(id) + 1)
            : 0;
        if (currentFav == newFav) continue;
        final newRow = Map<String, dynamic>.from(row);
        newRow['fav_index'] = newFav;
        updates.add((row, newRow));
      }
      await _commitChatContent(updates);
      return null;
    } on PacketError catch (e) {
      logger.w('togglePin: ${e.message}');
      return e.message;
    } catch (e) {
      logger.w('togglePin: $e');
      return 'Не удалось изменить закрепление';
    }
  }

  // #***! избранное берётся из папок, переносим в favIndex
  Future<void> applyFavorites(int accountId) async {
    try {
      final folders = await FoldersModule.loadFolders(accountId);
      if (folders.isEmpty) return;
      final allFolder = folders.firstWhere(
        FoldersModule.isAllChatsFolder,
        orElse: () => folders.first,
      );
      final favorites = allFolder.favorites;
      final favIndexById = <int, int>{};
      for (var i = 0; i < favorites.length; i++) {
        favIndexById[favorites[i]] = i + 1;
      }

      final rows = await AppDatabase.loadChats(accountId, includeHidden: true);
      final updates = <(Map<String, dynamic>, Map<String, dynamic>)>[];
      for (final row in rows) {
        final id = row['id'] as int;
        final current = (row['fav_index'] as int?) ?? 0;
        final next = favIndexById[id] ?? 0;
        if (current == next) continue;
        final newRow = Map<String, dynamic>.from(row);
        newRow['fav_index'] = next;
        updates.add((row, newRow));
      }
      await _commitChatContent(updates);
    } catch (e) {
      logger.w('applyFavorites: $e');
    }
  }

  // #***! мьют до времени или навсегда
  Future<String?> setChatMute(
    Api api, {
    required int chatId,
    required int dontDisturbUntil,
  }) async {
    try {
      await api.sendRequest(Opcode.config, {
        'settings': {
          'chats': {
            chatId: {'dontDisturbUntil': dontDisturbUntil},
          },
        },
      });
      final accountId = await TokenStorage.getActiveAccountId();
      if (accountId != null) {
        await _updateChat(
          accountId,
          chatId,
          (chat) => chat.copyWith(dontDisturbUntil: dontDisturbUntil),
        );
      }
      return null;
    } on PacketError catch (e) {
      logger.w('setChatMute $chatId: ${e.message}');
      return e.message;
    } catch (e) {
      logger.w('setChatMute $chatId: $e');
      return 'Не удалось изменить уведомления';
    }
  }

  static int knownEventTime(CachedChat? chat, {int seen = 0}) =>
      [seen, chat?.lastEventTime ?? 0, chat?.lastMsgTime ?? 0].reduce(math.max);

  static int _eventTimeOfInfo(Map<String, dynamic>? info) {
    final lastMessage = info?['lastMessage'];
    return [
      _asTime(info?['lastEventTime']),
      if (lastMessage is Map) _asTime(lastMessage['time']),
    ].reduce(math.max);
  }

  static int _asTime(Object? raw) => raw is num ? raw.toInt() : 0;

  Future<int?> chatEventTime(
    Api api,
    int chatId, {
    int seen = 0,
    int? accountId,
  }) async {
    final known = knownEventTime(
      await _cachedChat(accountId, chatId),
      seen: seen,
    );
    if (known > 0) return known;
    final fetched = _eventTimeOfInfo(await getChatInfo(api, chatId));
    if (fetched > 0) return fetched;
    logger.w('Чат $chatId: время последнего события неизвестно и в CHAT_INFO');
    return null;
  }

  Future<({int? time, ServerOutcome? failure})> _requestEventTime(
    Api api,
    int chatId, {
    required int seen,
    required int? accountId,
  }) async {
    try {
      final time = await chatEventTime(
        api,
        chatId,
        seen: seen,
        accountId: accountId,
      );
      return (time: time, failure: null);
    } catch (e) {
      return (time: null, failure: outcomeOfError(e));
    }
  }

  void _logRefusal(String action, int chatId, ServerOutcome outcome) {
    switch (outcome) {
      case ServerDone():
        return;
      case ServerRejected(:final message):
        logger.w('$action $chatId отклонено: $message');
      case ServerUnreachable(:final reason):
        logger.w('$action $chatId не дошло: $reason');
    }
  }

  Future<CachedChat?> _cachedChat(int? accountId, int chatId) async {
    final cached = _chatsById[chatId];
    if (cached != null) return cached;
    if (accountId == null) return null;
    final rows = await AppDatabase.loadChat(accountId, chatId);
    return rows.isEmpty ? null : CachedChat.fromDbRow(rows.first);
  }

  Future<({ChatDeletionPlan? plan, int eventTime, ServerOutcome? failure})>
  _planForAll(
    Api api, {
    required int chatId,
    required int myId,
    required int? accountId,
    required String action,
  }) async {
    String? type;
    int? owner;
    Iterable<int> participants;
    Set<String> options;
    int eventTime;
    final cached = await _cachedChat(accountId, chatId);
    if (cached != null) {
      eventTime = knownEventTime(cached);
      type = cached.type;
      owner = cached.owner;
      participants = cached.participants.keys;
      options = cached.options;
    } else {
      final Map<String, dynamic>? info;
      try {
        info = await getChatInfo(api, chatId);
      } catch (e) {
        return (plan: null, eventTime: 0, failure: outcomeOfError(e));
      }
      eventTime = _eventTimeOfInfo(info);
      final rawType = info?['type'];
      final rawOwner = info?['owner'];
      type = rawType is String ? rawType : null;
      owner = rawOwner is int ? rawOwner : null;
      participants = parseParticipants(info?['participants']).keys;
      options = const {};
    }
    final peerIsBot =
        type == 'DIALOG' &&
        knownBot(
          dialogPeerId(chatId: chatId, myId: myId, participants: participants),
          chatOptions: options,
        );
    final policy = DeletionPolicy.instance;
    final deleteForAll = policy.accountId == accountId
        ? policy.deleteForAll
        : null;
    final plan = ChatDeletionPlan.of(
      forAll: true,
      chatId: chatId,
      chatType: type,
      owner: owner,
      myId: myId,
      peerIsBot: peerIsBot,
      deleteForAll: deleteForAll,
    );
    if (plan == null) {
      logger.w('$action $chatId: тип чата неизвестен, для всех не отправляем');
    } else if (!plan.forAll) {
      logger.w(
        '$action $chatId: $type, владелец $owner, бот $peerIsBot, '
        'delete-for-all=$deleteForAll — сервер MAX не даёт сделать это для '
        'всех, отправляю только для себя, как официальный клиент',
      );
    } else if (type == 'DIALOG' && deleteForAll == null) {
      logger.i(
        '$action $chatId: delete-for-all ещё не известен, отправляю для всех, '
        'решит сервер',
      );
    }
    return (plan: plan, eventTime: eventTime, failure: null);
  }

  // #***! удаление чата
  Future<ChatDeletionResult> deleteChat(
    Api api, {
    required int chatId,
    required bool forAll,
    int seenEventTime = 0,
    int? accountId,
  }) async {
    final epoch = api.sessionEpoch;
    final owner = accountId ?? await TokenStorage.getActiveAccountId();
    Future<bool> sameSession() async {
      final active = await TokenStorage.getActiveAccountId();
      return api.sessionEpoch == epoch && (owner == null || active == owner);
    }

    const sessionChanged = ServerUnreachable('сессия сменилась');
    if (!await sameSession()) return const ChatDeletionResult(sessionChanged);

    var plan = ChatDeletionPlan.forMe;
    var seen = seenEventTime;
    if (forAll && chatId != 0) {
      final resolved = await _planForAll(
        api,
        chatId: chatId,
        myId: owner ?? 0,
        accountId: owner,
        action: 'deleteChat',
      );
      final failure = resolved.failure;
      if (failure != null) {
        _logRefusal('deleteChat', chatId, failure);
        return ChatDeletionResult(failure);
      }
      final chosen = resolved.plan;
      if (chosen == null) {
        return ChatDeletionResult.refused(ChatDeletionRefusal.typeUnknown);
      }
      plan = chosen;
      seen = math.max(seen, resolved.eventTime);
    }

    final eventTime = await _requestEventTime(
      api,
      chatId,
      seen: seen,
      accountId: owner,
    );
    final timeFailure = eventTime.failure;
    if (timeFailure != null) {
      _logRefusal('deleteChat', chatId, timeFailure);
      return ChatDeletionResult(timeFailure);
    }
    final lastEventTime = eventTime.time;
    if (lastEventTime == null) {
      return ChatDeletionResult.refused(ChatDeletionRefusal.eventTimeUnknown);
    }
    if (!await sameSession()) return const ChatDeletionResult(sessionChanged);

    final outcome = await runServerAction(() async {
      final response = await api.sendRequest(
        Opcode.chatDelete,
        plan.payload(chatId: chatId, lastEventTime: lastEventTime),
      );
      logger.i(
        'CHAT_DELETE чат $chatId, forAll=${plan.forAll}, '
        'lastEventTime=$lastEventTime → ${describeReply(response)}',
      );
      return response;
    });
    _logRefusal('deleteChat', chatId, outcome);
    final result = ChatDeletionResult(outcome, forAll: plan.forAll);
    if (!result.ok) return result;
    if (owner != null) {
      await AppDatabase.deleteChat(chatId, owner);
      MessageSessionCache.remove(owner, chatId);
      _historyFetched.remove(chatId);
      _bump();
      _removeChatFromMemory(chatId);
    }
    _departedChatsController.add(chatId);
    return result;
  }

  // #***! очистка истории
  Future<ServerOutcome> clearHistory(
    Api api, {
    required int chatId,
    bool forAll = false,
    int seenEventTime = 0,
  }) async {
    final accountId = await TokenStorage.getActiveAccountId();
    var sendForAll = false;
    var seen = seenEventTime;
    if (forAll && chatId != 0) {
      final resolved = await _planForAll(
        api,
        chatId: chatId,
        myId: accountId ?? 0,
        accountId: accountId,
        action: 'clearHistory',
      );
      final failure = resolved.failure;
      if (failure != null) {
        _logRefusal('clearHistory', chatId, failure);
        return failure;
      }
      final plan = resolved.plan;
      if (plan == null) return ChatDeletionRefusal.typeUnknown.outcome;
      sendForAll = plan.forAll;
      seen = math.max(seen, resolved.eventTime);
    }

    final eventTime = await _requestEventTime(
      api,
      chatId,
      seen: seen,
      accountId: accountId,
    );
    final timeFailure = eventTime.failure;
    if (timeFailure != null) {
      _logRefusal('clearHistory', chatId, timeFailure);
      return timeFailure;
    }
    final lastEventTime = eventTime.time;
    if (lastEventTime == null) {
      return ChatDeletionRefusal.eventTimeUnknown.outcome;
    }

    final outcome = await runServerAction(() async {
      final response = await api.sendRequest(Opcode.chatClear, {
        'chatId': chatId,
        'lastEventTime': lastEventTime,
        'forAll': sendForAll,
      });
      logger.i(
        'CHAT_CLEAR чат $chatId, forAll=$sendForAll, '
        'lastEventTime=$lastEventTime → ${describeReply(response)}',
      );
      return response;
    });
    _logRefusal('clearHistory', chatId, outcome);
    if (outcome is! ServerDone) return outcome;
    if (accountId != null) {
      await AppDatabase.clearMessages(accountId, chatId);
      MessageSessionCache.remove(accountId, chatId);
      _historyFetched.remove(chatId);
      await reconcileLastMessage(accountId, chatId);
    }
    return outcome;
  }

  // #***! выход из чата
  Future<ServerOutcome> leaveChat(
    Api api, {
    required int chatId,
    int? accountId,
  }) async {
    final owner = accountId ?? await TokenStorage.getActiveAccountId();
    final outcome = await runServerAction(
      () => api.sendRequest(Opcode.chatLeave, {'chatId': chatId}),
    );
    _logRefusal('leaveChat', chatId, outcome);
    if (outcome is! ServerDone) return outcome;
    if (owner != null) {
      await AppDatabase.deleteChat(chatId, owner);
      MessageSessionCache.remove(owner, chatId);
      _bump();
      _removeChatFromMemory(chatId);
      unawaited(_verifyLeftChat(api, owner, chatId));
    }
    _departedChatsController.add(chatId);
    return outcome;
  }

  // #***! сервер иногда роняет chatLeave тихо — перепроверяем через паузу и
  // при необходимости повторяем, вместо того чтобы доверять первому ack
  Future<void> _verifyLeftChat(Api api, int accountId, int chatId) async {
    await Future<void>.delayed(const Duration(seconds: 5));
    Map<String, dynamic>? info;
    try {
      info = await getChatInfo(api, chatId);
    } catch (_) {
      return;
    }
    if (info == null) return;
    final stillMember = parseParticipants(
      info['participants'],
    ).containsKey(accountId);
    if (!stillMember) return;
    try {
      await api.sendRequest(Opcode.chatLeave, {'chatId': chatId});
    } catch (_) {}
  }

  // #***! добавление участников
  Future<bool> addMembers(
    Api api, {
    required int chatId,
    required List<int> userIds,
    bool showHistory = true,
  }) async {
    if (userIds.isEmpty) return false;
    try {
      final packet = await api.sendRequest(Opcode.chatMembersUpdate, {
        'chatId': chatId,
        'userIds': userIds,
        'showHistory': showHistory,
        'operation': 'add',
      });
      if (!packet.isOk) {
        logger.w(
          'addMembers $chatId: ${messageFromErrorPayload(packet.payload)}',
        );
        return false;
      }
      final data = packet.payload;
      final chat = data is Map ? data['chat'] : null;
      if (chat is Map) {
        final accountId = await TokenStorage.getActiveAccountId();
        if (accountId != null) {
          await cacheServerChat(chat.cast<dynamic, dynamic>(), accountId);
        }
      }
      if (chat is! Map || chat['participantsCount'] is! int) {
        ChatMembersStore.instance.adjust(chatId, userIds.length);
      }
      _refreshChatInfo(chatId);
      return true;
    } on PacketError catch (e) {
      logger.w('addMembers $chatId: ${e.message}');
      return false;
    } catch (e) {
      logger.w('addMembers $chatId: $e');
      return false;
    }
  }

  // #***! страница участников
  Future<ChatMembersPage?> getChatMembers(
    Api api,
    int chatId, {
    int marker = 0,
    int count = 50,
  }) async {
    try {
      final packet = await api.sendRequest(Opcode.chatMembers, {
        'type': 'MEMBER',
        'marker': marker,
        'chatId': chatId,
        'count': count,
      });
      if (!packet.isOk) return null;
      final payload = packet.payload;
      if (payload is! Map) return null;
      return _parseMembersPage(payload, marker);
    } on PacketError catch (e) {
      logger.w('getChatMembers $chatId: ${e.message}');
      return null;
    } catch (e) {
      logger.w('getChatMembers $chatId: $e');
      return null;
    }
  }

  // #***! разбор страницы участников, общий для members и join-request
  ChatMembersPage _parseMembersPage(Map payload, int fallbackMarker) {
    final entries = <ChatMemberEntry>[];
    final presenceById = <int, Map<String, dynamic>>{};
    final rawMembers = payload['members'];
    if (rawMembers is List) {
      for (final m in rawMembers.whereType<Map>()) {
        final contact = m['contact'];
        if (contact is! Map) continue;
        final id = contact['id'];
        if (id is! int) continue;

        final info = ContactInfo.fromMap(Map<String, dynamic>.from(contact));
        final name = info.displayName;
        if (name != null && name.isNotEmpty) ContactCache.put(id, name);
        final avatar = info.avatarUrl;
        if (avatar != null && avatar.isNotEmpty) {
          ContactCache.putAvatar(id, avatar);
        }
        final phone = contact['phone'];
        if (phone is int && phone > 0) ContactCache.putPhone(id, phone);
        ContactInfoFetch.putContact(id, contact.cast<dynamic, dynamic>());

        final presence = m['presence'];
        var status = 0;
        int? seen;
        if (presence is Map) {
          final p = Map<String, dynamic>.from(presence);
          presenceById[id] = p;
          status = (p['status'] as int?) ?? 0;
          final s = p['seen'];
          seen = s is int ? s : null;
        }

        entries.add(
          ChatMemberEntry(
            id: id,
            name: name,
            fullName: info.fullName,
            avatarUrl: avatar,
            seenTime: seen,
            presenceStatus: status,
            blocked: info.isDeleted,
            isContact: info.isSavedContact,
          ),
        );
      }
    }
    if (presenceById.isNotEmpty) PresenceFetch.primeAll(presenceById);

    final next = payload['marker'];
    return ChatMembersPage(
      members: entries,
      marker: next is int ? next : fallbackMarker,
    );
  }

  // #***! входящие заявки на вступление (закрытые группы и каналы)
  Future<ChatMembersPage?> getJoinRequests(
    Api api,
    int chatId, {
    int count = 100,
  }) async {
    try {
      final packet = await api.sendRequest(Opcode.chatMembers, {
        'type': 'JOIN_REQUEST',
        'chatId': chatId,
        'count': count,
      });
      if (!packet.isOk) return null;
      final payload = packet.payload;
      if (payload is! Map) return null;
      return _parseMembersPage(payload, 0);
    } on PacketError catch (e) {
      logger.w('getJoinRequests $chatId: ${e.message}');
      return null;
    } catch (e) {
      logger.w('getJoinRequests $chatId: $e');
      return null;
    }
  }

  // #***! одобрить заявки, showHistory открывает историю до вступления
  Future<bool> approveJoinRequests(
    Api api, {
    required int chatId,
    required List<int> userIds,
    bool showHistory = true,
  }) async {
    if (userIds.isEmpty) return false;
    try {
      final ok = await api.sendRequestOk(Opcode.chatMembersUpdate, {
        'chatId': chatId,
        'userIds': userIds,
        'type': 'JOIN_REQUEST',
        'showHistory': showHistory,
        'operation': 'add',
      });
      if (ok) _refreshChatInfo(chatId);
      return ok;
    } catch (e) {
      logger.w('approveJoinRequests $chatId: $e');
      return false;
    }
  }

  // #***! отклонить заявки
  Future<bool> declineJoinRequests(
    Api api, {
    required int chatId,
    required List<int> userIds,
  }) async {
    if (userIds.isEmpty) return false;
    try {
      return await api.sendRequestOk(Opcode.chatMembersUpdate, {
        'chatId': chatId,
        'userIds': userIds,
        'type': 'JOIN_REQUEST',
        'operation': 'remove',
      });
    } catch (e) {
      logger.w('declineJoinRequests $chatId: $e');
      return false;
    }
  }

  // #***! назначить админом с набором прав из ChatPermission (битмаска)
  Future<bool> addAdmin(
    Api api, {
    required int chatId,
    required int userId,
    required int permissions,
  }) async {
    try {
      final ok = await api.sendRequestOk(Opcode.chatMembersUpdate, {
        'chatId': chatId,
        'userIds': [userId],
        'type': 'ADMIN',
        'operation': 'add',
        'permissions': permissions,
      });
      if (ok) _refreshChatInfo(chatId);
      return ok;
    } catch (e) {
      logger.w('addAdmin $chatId: $e');
      return false;
    }
  }

  // #***! инфо об организации / бизнес-профиле.
  // opcode сверен (ORG_INFO=256), но форма payload НЕ подтверждена: её нет
  // ни в pymax, ни в открытых строках dex. chatId — предположение, проверить
  // дампом трафика перед завязкой UI на это.
  Future<Map<dynamic, dynamic>?> fetchOrgInfo(Api api, int chatId) async {
    return api.sendRequestMap(Opcode.orgInfo, {'chatId': chatId});
  }

  // #***! принудительно обновить конкретные чаты
  Future<List<CachedChat>> refreshChats(Api api, List<int> chatIds) async {
    if (chatIds.isEmpty) return const [];
    try {
      final packet = await api.sendRequest(Opcode.chatInfo, {
        'chatIds': chatIds,
      });
      final payload = packet.payload;
      if (payload is! Map) return const [];
      final list = payload['chats'];
      if (list is! List) return const [];
      final accountId = await TokenStorage.getActiveAccountId();
      if (accountId == null) return const [];
      final existingRows = await AppDatabase.loadChatsByIds(accountId, chatIds);
      final preloadedExisting = {
        for (final row in existingRows)
          row['id'] as int: CachedChat.fromDbRow(row),
      };
      final preloadedListState = {
        for (final row in existingRows) row['id'] as int: row['in_list'] as int,
      };
      final out = <CachedChat>[];
      for (final c in list) {
        if (c is Map) {
          final cached = await cacheServerChat(
            c,
            accountId,
            preloadedExisting: preloadedExisting,
            preloadedListState: preloadedListState,
          );
          if (cached != null) out.add(cached);
        }
      }
      return out;
    } on PacketError catch (e) {
      logger.w('refreshChats: ${e.message}');
      return const [];
    } catch (e) {
      logger.w('refreshChats: $e');
      return const [];
    }
  }
}

// #***! синглтон, вся юишка работает с одним
final chats = ChatsModule._();
