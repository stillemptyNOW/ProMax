import 'dart:async';

import 'logger.dart';

abstract final class AppExitHooks {
  static final List<FutureOr<void> Function()> _hooks = [];

  static void add(FutureOr<void> Function() hook) => _hooks.add(hook);

  static void remove(FutureOr<void> Function() hook) => _hooks.remove(hook);

  static Future<void> run({
    Duration timeout = const Duration(seconds: 2),
  }) async {
    final pending = [
      for (final hook in List.of(_hooks))
        Future.sync(
          hook,
        ).catchError((Object e) => logger.w('AppExitHooks: $e')),
    ];
    try {
      await Future.wait(pending).timeout(timeout);
    } on TimeoutException {
      logger.w('AppExitHooks: не дождались завершения за $timeout');
    }
  }
}
