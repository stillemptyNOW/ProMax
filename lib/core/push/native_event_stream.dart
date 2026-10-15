import 'dart:async';

import 'package:flutter/services.dart';

import '../utils/logger.dart';
import 'fkm_bridge.dart';

class NativeEventStream {
  NativeEventStream(this._channel, this._label);

  final EventChannel _channel;
  final String _label;

  StreamSubscription<dynamic>? _events;
  StreamSubscription<void>? _reattach;

  void listen(void Function(dynamic event) onEvent) {
    if (_reattach != null) return;
    void subscribe() {
      unawaited(_events?.cancel());
      _events = _channel.receiveBroadcastStream().listen(
        onEvent,
        onError: (Object e) => logger.w('$_label: events stream error: $e'),
      );
    }

    subscribe();
    _reattach = FkmBridge.instance.attached.listen((_) => subscribe());
  }
}
