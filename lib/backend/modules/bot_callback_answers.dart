import 'dart:async';

import '../../core/protocol/opcode_map.dart';
import '../../core/protocol/packet.dart';
import '../api.dart';

class BotCallbackAnswer {
  const BotCallbackAnswer({
    required this.text,
    this.callbackId,
    this.messageId,
  });

  final String text;
  final String? callbackId;
  final String? messageId;

  static const _textKeys = ['notification', 'text', 'message', 'title'];

  static BotCallbackAnswer? fromPayload(Object? payload) {
    if (payload is! Map) return null;
    final answer = payload['answer'] is Map ? payload['answer'] as Map : null;
    String? text;
    for (final source in [?answer, payload]) {
      for (final key in _textKeys) {
        final value = source[key];
        if (value is String && value.trim().isNotEmpty) {
          text = value.trim();
          break;
        }
      }
      if (text != null) break;
    }
    if (text == null) return null;
    final message = payload['message'];
    final messageId =
        payload['messageId'] ?? (message is Map ? message['id'] : null);
    return BotCallbackAnswer(
      text: text,
      callbackId: (payload['callbackId'] ?? answer?['callbackId'])?.toString(),
      messageId: messageId?.toString(),
    );
  }
}

typedef BotAnswerAnchor = bool Function(String text);

class BotCallbackAnswers {
  BotCallbackAnswers({Duration recentWindow = const Duration(seconds: 20)})
    : _recentWindow = recentWindow;

  static final BotCallbackAnswers instance = BotCallbackAnswers();

  static const Duration anchorLifetime = Duration(seconds: 30);

  final Duration _recentWindow;
  final Map<String, BotAnswerAnchor> _anchors = {};
  final Map<String, ({String text, DateTime at})> _shown = {};
  final StreamController<String> _unclaimed = StreamController.broadcast();
  StreamSubscription<Packet>? _sub;

  Stream<String> get unclaimed => _unclaimed.stream;

  void attach(Api api) {
    _sub?.cancel();
    _sub = api.pushStream
        .where((packet) => packet.opcode == Opcode.notifCallbackAnswer)
        .listen((packet) => deliver(packet.payload));
  }

  static String keyOf(String messageId, String callbackId) =>
      '$messageId:$callbackId';

  void Function() anchor(
    String messageId,
    String callbackId,
    BotAnswerAnchor show,
  ) {
    final key = keyOf(messageId, callbackId);
    _anchors[key] = show;
    return () {
      if (identical(_anchors[key], show)) _anchors.remove(key);
    };
  }

  void noteShown(String messageId, String callbackId, String text) =>
      _noteShown(keyOf(messageId, callbackId), text);

  void deliver(Object? payload) {
    final answer = BotCallbackAnswer.fromPayload(payload);
    if (answer == null) return;
    final key = _matchingKey(answer);
    if (key != null) {
      final shown = _shown[key];
      if (shown != null &&
          shown.text == answer.text &&
          DateTime.now().difference(shown.at) < _recentWindow) {
        return;
      }
      if (_anchors[key]?.call(answer.text) ?? false) {
        _noteShown(key, answer.text);
        return;
      }
    }
    _unclaimed.add(answer.text);
  }

  void _noteShown(String key, String text) {
    final now = DateTime.now();
    _shown.removeWhere((_, entry) => now.difference(entry.at) >= _recentWindow);
    _shown[key] = (text: text, at: now);
  }

  String? _matchingKey(BotCallbackAnswer answer) {
    final callbackId = answer.callbackId;
    final messageId = answer.messageId;
    if (callbackId != null && messageId != null) {
      return keyOf(messageId, callbackId);
    }
    final suffix = callbackId == null ? null : ':$callbackId';
    final prefix = messageId == null ? null : '$messageId:';
    for (final key in [..._anchors.keys, ..._shown.keys]) {
      if (suffix != null && key.endsWith(suffix)) return key;
      if (prefix != null && key.startsWith(prefix)) return key;
    }
    return null;
  }
}
