import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../utils/logger.dart';

class NetworkWatch {
  NetworkWatch({
    Stream<Object?>? events,
    this.debounce = const Duration(milliseconds: 600),
  }) : _events = events;

  static const EventChannel _channel = EventChannel(
    'io.github.stillemptynow.promax/network_events',
  );

  static bool get supported => !kIsWeb && Platform.isAndroid;

  final Stream<Object?>? _events;
  final Duration debounce;
  StreamSubscription<Object?>? _sub;
  Timer? _pending;

  void start(void Function() onNetworkAvailable) {
    stop();
    final events =
        _events ?? (supported ? _channel.receiveBroadcastStream() : null);
    if (events == null) return;
    _sub = events.listen((event) {
      if (event != 'available') return;
      _pending?.cancel();
      _pending = Timer(debounce, onNetworkAvailable);
    }, onError: (Object error) => logger.w('NetworkWatch: $error'));
  }

  void stop() {
    _pending?.cancel();
    _pending = null;
    _sub?.cancel();
    _sub = null;
  }
}
