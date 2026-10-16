import 'dart:async';

import '../../core/config/promax_settings.dart';
import '../../core/storage/chat_activity_store.dart';

bool get chatActivityBroadcastAllowed =>
    !ProMaxSettings.noTyping.value && !ProMaxSettings.ghostMode.value;

class ChatActivitySender {
  ChatActivitySender(
    this._send, {
    this.interval = const Duration(seconds: 4),
    bool Function()? allowed,
    int Function()? now,
  }) : _allowed = allowed ?? (() => chatActivityBroadcastAllowed),
       _now = now ?? _wallClock;

  final void Function(ChatActivity activity) _send;
  final Duration interval;
  final bool Function() _allowed;
  final int Function() _now;

  ChatActivity? _lastSent;
  int _lastSentAt = 0;
  ChatActivity? _held;
  Timer? _holdTimer;

  static int _wallClock() => DateTime.now().millisecondsSinceEpoch;

  ChatActivity? get held => _held;

  void pulse(ChatActivity activity) {
    if (_held != null) return;
    _emit(activity, throttled: true);
  }

  void hold(ChatActivity activity) {
    if (_held == activity) return;
    _holdTimer?.cancel();
    _held = activity;
    _emit(activity, throttled: false);
    _holdTimer = Timer.periodic(interval, (_) {
      final current = _held;
      if (current != null) _emit(current, throttled: false);
    });
  }

  void release(ChatActivity activity) {
    if (_held != activity) return;
    _holdTimer?.cancel();
    _holdTimer = null;
    _held = null;
    reset();
  }

  void reset() {
    _lastSent = null;
    _lastSentAt = 0;
  }

  void dispose() {
    _holdTimer?.cancel();
    _holdTimer = null;
    _held = null;
  }

  void _emit(ChatActivity activity, {required bool throttled}) {
    if (!_allowed()) return;
    final now = _now();
    if (throttled &&
        _lastSent == activity &&
        now - _lastSentAt < interval.inMilliseconds) {
      return;
    }
    _lastSent = activity;
    _lastSentAt = now;
    _send(activity);
  }
}
