import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../storage/app_instance.dart';
import '../utils/logger.dart';

abstract final class WebViewSandbox {
  static Future<WebViewEnvironment?>? _environment;

  static bool get _usesEnvironment => !kIsWeb && Platform.isWindows;

  static Future<WebViewEnvironment?> environment() {
    if (!_usesEnvironment) return Future.value();
    return _environment ??= _create();
  }

  static Future<WebViewEnvironment?> _create() async {
    try {
      final base = await getApplicationSupportDirectory();
      final folder = Directory(
        p.join(base.path, 'webview2${AppInstance.suffix}'),
      );
      await folder.create(recursive: true);
      return await WebViewEnvironment.create(
        settings: WebViewEnvironmentSettings(userDataFolder: folder.path),
      );
    } catch (e) {
      logger.w('[webview] отдельная папка WebView2 недоступна: $e');
      _environment = null;
      return null;
    }
  }
}
