import 'dart:io';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';

abstract final class DesktopIdentity {
  static const appName = 'ProMax';
  static const appUserModelId = 'io.github.stillemptynow.promax';
  static const toastActivatorGuid = '121322eb-66fd-4132-bba1-2b1a60dd8efc';

  static String? get bundledIconPath {
    try {
      final dir = File(Platform.resolvedExecutable).parent.path;
      final icon = File(
        '$dir${Platform.pathSeparator}data${Platform.pathSeparator}'
        'flutter_assets${Platform.pathSeparator}assets'
        '${Platform.pathSeparator}promax_icon.png',
      );
      return icon.existsSync() ? icon.path : null;
    } catch (_) {
      return null;
    }
  }

  static WindowsInitializationSettings get windowsNotificationSettings =>
      WindowsInitializationSettings(
        appName: appName,
        appUserModelId: appUserModelId,
        guid: toastActivatorGuid,
        iconPath: bundledIconPath,
      );

  static const LinuxInitializationSettings linuxNotificationSettings =
      LinuxInitializationSettings(defaultActionName: 'Открыть');
}
