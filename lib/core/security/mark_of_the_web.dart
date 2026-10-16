import 'dart:io';

import 'package:flutter/foundation.dart';

abstract final class MarkOfTheWeb {
  static const String zoneIdentifier = '[ZoneTransfer]\r\nZoneId=3\r\n';

  static bool get supported => !kIsWeb && Platform.isWindows;

  static String streamPathOf(String path) => '$path:Zone.Identifier';

  static Future<void> apply(String path) async {
    if (!supported) return;
    try {
      await File(streamPathOf(path)).writeAsString(zoneIdentifier, flush: true);
    } catch (_) {}
  }
}
