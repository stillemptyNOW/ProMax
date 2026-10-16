import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:promax/core/utils/app_exit_hooks.dart';

void main() {
  test(
    'exit hooks all run, survive failures and respect the timeout',
    () async {
      final ran = <String>[];
      void first() => ran.add('first');
      Future<void> failing() async => throw StateError('synthetic failure');
      Future<void> slow() => Completer<void>().future;

      AppExitHooks.add(first);
      AppExitHooks.add(failing);
      AppExitHooks.add(slow);
      addTearDown(() {
        AppExitHooks.remove(first);
        AppExitHooks.remove(failing);
        AppExitHooks.remove(slow);
      });

      await AppExitHooks.run(timeout: const Duration(milliseconds: 50));
      expect(ran, ['first']);

      AppExitHooks.remove(first);
      await AppExitHooks.run(timeout: const Duration(milliseconds: 10));
      expect(ran, ['first']);
    },
  );
}
