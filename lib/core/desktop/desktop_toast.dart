import 'dart:convert';

import 'package:flutter/foundation.dart';

enum DesktopToastAction { open, reply, accept, decline }

@immutable
class DesktopToastIntent {
  const DesktopToastIntent({
    required this.action,
    this.chatId,
    this.accountId,
    this.messageId,
    this.conversationId,
  });

  final DesktopToastAction action;
  final int? chatId;
  final int? accountId;
  final int? messageId;
  final String? conversationId;

  bool get isCall => conversationId != null;

  static const _typeKey = 't';
  static const _actionKey = 'a';
  static const _chatType = 'chat';
  static const _callType = 'call';

  static String chatPayload(
    int chatId, {
    required int accountId,
    int? messageId,
    DesktopToastAction action = DesktopToastAction.open,
  }) => jsonEncode({
    _typeKey: _chatType,
    'chat': chatId,
    'acc': accountId,
    'mid': ?messageId,
    if (action != DesktopToastAction.open) _actionKey: action.name,
  });

  static String callPayload(
    String conversationId, {
    DesktopToastAction action = DesktopToastAction.open,
  }) => jsonEncode({
    _typeKey: _callType,
    'conv': conversationId,
    if (action != DesktopToastAction.open) _actionKey: action.name,
  });

  static DesktopToastIntent? parse({String? payload, String? actionId}) {
    if (payload == null || payload.isEmpty) return null;
    final Object? decoded;
    try {
      decoded = jsonDecode(payload);
    } on FormatException {
      return null;
    }
    if (decoded is! Map) return null;
    final explicit = decoded[_actionKey];
    final fromId = actionId == null || actionId == payload ? null : actionId;
    final action = _action(explicit is String ? explicit : fromId);
    if (action == null) return null;
    switch (decoded[_typeKey]) {
      case _chatType:
        final chatId = decoded['chat'];
        if (chatId is! int || chatId == 0) return null;
        final accountId = decoded['acc'];
        final messageId = decoded['mid'];
        return DesktopToastIntent(
          action: action,
          chatId: chatId,
          accountId: accountId is int ? accountId : null,
          messageId: messageId is int ? messageId : null,
        );
      case _callType:
        final conversationId = decoded['conv'];
        if (conversationId is! String || conversationId.isEmpty) return null;
        return DesktopToastIntent(
          action: action,
          conversationId: conversationId,
        );
    }
    return null;
  }

  static DesktopToastAction? _action(String? name) {
    if (name == null || name.isEmpty) return DesktopToastAction.open;
    for (final action in DesktopToastAction.values) {
      if (action.name == name) return action;
    }
    return null;
  }
}
