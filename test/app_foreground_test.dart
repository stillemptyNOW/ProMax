import 'dart:ui' show AppLifecycleState;

import 'package:flutter_test/flutter_test.dart';
import 'package:promax/core/utils/app_foreground.dart';

void main() {
  group('AppForeground.visibleIn', () {
    test('движок без окна (фоновый запуск FKM) считается фоном', () {
      expect(AppForeground.visibleIn(AppLifecycleState.detached), isFalse);
    });

    test('свёрнутое и скрытое приложение — фон', () {
      expect(AppForeground.visibleIn(AppLifecycleState.paused), isFalse);
      expect(AppForeground.visibleIn(AppLifecycleState.hidden), isFalse);
    });

    test('видимое приложение — передний план', () {
      expect(AppForeground.visibleIn(AppLifecycleState.resumed), isTrue);
      expect(AppForeground.visibleIn(AppLifecycleState.inactive), isTrue);
    });

    test('пока платформа не прислала состояние, приложение видимо', () {
      expect(AppForeground.visibleIn(null), isTrue);
    });
  });

  group('AppForeground.interactiveIn', () {
    test(
      'входящий звонок показывается в интерфейсе только у активного окна',
      () {
        expect(AppForeground.interactiveIn(AppLifecycleState.resumed), isTrue);
        expect(AppForeground.interactiveIn(null), isTrue);
      },
    );

    test('без активного окна звонок уходит в уведомление', () {
      for (final state in [
        AppLifecycleState.inactive,
        AppLifecycleState.hidden,
        AppLifecycleState.paused,
        AppLifecycleState.detached,
      ]) {
        expect(AppForeground.interactiveIn(state), isFalse, reason: '$state');
      }
    });
  });
}
