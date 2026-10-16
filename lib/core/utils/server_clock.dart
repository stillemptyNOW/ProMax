import 'package:flutter/foundation.dart';

class ServerClock {
  ServerClock._();

  static int _offset = 0;

  static int get offset => _offset;

  static void sync(int serverTime, {int? localNow}) {
    _offset = serverTime - (localNow ?? DateTime.now().millisecondsSinceEpoch);
  }

  static int now() => DateTime.now().millisecondsSinceEpoch + _offset;

  @visibleForTesting
  static void resetForTest() => _offset = 0;
}
