import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:open_filex/open_filex.dart';
import 'package:url_launcher/url_launcher.dart';

import '../security/mark_of_the_web.dart';

enum LocalFileOpenStatus { opened, noApp, failed }

class LocalFileOpenResult {
  final LocalFileOpenStatus status;
  final String? error;

  const LocalFileOpenResult(this.status, {this.error});

  bool get opened => status == LocalFileOpenStatus.opened;
}

bool get _isDesktop =>
    !kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux);

Future<LocalFileOpenResult> openLocalFile(String path) async {
  await MarkOfTheWeb.apply(path);
  try {
    if (_isDesktop) {
      final launched = await launchUrl(
        Uri.file(path, windows: Platform.isWindows),
      );
      return LocalFileOpenResult(
        launched ? LocalFileOpenStatus.opened : LocalFileOpenStatus.noApp,
      );
    }
    final opened = await OpenFilex.open(path);
    return switch (opened.type) {
      ResultType.done => const LocalFileOpenResult(LocalFileOpenStatus.opened),
      ResultType.noAppToOpen => LocalFileOpenResult(
        LocalFileOpenStatus.noApp,
        error: opened.message,
      ),
      _ => LocalFileOpenResult(
        LocalFileOpenStatus.failed,
        error: opened.message,
      ),
    };
  } catch (e) {
    return LocalFileOpenResult(LocalFileOpenStatus.failed, error: '$e');
  }
}
