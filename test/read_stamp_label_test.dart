import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promax/core/config/promax_settings.dart';
import 'package:promax/frontend/screens/chats/chat/view/read_stamp_label.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> _pumpLabel(
  WidgetTester tester,
  Listenable listenable,
  String? Function() text,
) {
  return tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 40, child: Text('пузырь')),
            ReadStampLabel(listenable: listenable, text: text),
          ],
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('the label slides in when the stamp becomes known', (
    tester,
  ) async {
    final revision = ValueNotifier(0);
    addTearDown(revision.dispose);
    String? stamp;
    await _pumpLabel(tester, revision, () => stamp);
    expect(find.textContaining('Прочитано'), findsNothing);

    stamp = 'Прочитано сегодня в 14:32';
    revision.value++;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));
    final opacity = tester.widget<FadeTransition>(
      find
          .ancestor(
            of: find.text('Прочитано сегодня в 14:32'),
            matching: find.byType(FadeTransition),
          )
          .first,
    );
    expect(opacity.opacity.value, inExclusiveRange(0.0, 1.0));

    await tester.pumpAndSettle();
    expect(find.text('Прочитано сегодня в 14:32'), findsOneWidget);
  });

  testWidgets('the label collapses when the stamp moves away', (tester) async {
    final revision = ValueNotifier(0);
    addTearDown(revision.dispose);
    String? stamp = 'Прочитано вчера в 09:15';
    await _pumpLabel(tester, revision, () => stamp);
    await tester.pumpAndSettle();
    final shown = tester.getSize(find.byType(ReadStampLabel)).height;
    expect(shown, greaterThan(0));

    stamp = null;
    revision.value++;
    await tester.pumpAndSettle();
    expect(find.text('Прочитано вчера в 09:15'), findsNothing);
    expect(tester.getSize(find.byType(ReadStampLabel)).height, 0);
  });

  testWidgets('a long stamp wraps under large text instead of overflowing', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    const stamp = 'Прочитано 12 окт 2025 в 14:32';
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(
            size: Size(360, 640),
            textScaler: TextScaler.linear(2),
          ),
          child: Scaffold(
            body: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ReadStampLabel(
                  listenable: const AlwaysStoppedAnimation(0),
                  text: () => stamp,
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text(stamp), findsOneWidget);
    expect(tester.getRect(find.text(stamp)).right, lessThanOrEqualTo(360));
  });

  test('the in-bubble read time is on by default and persists', () async {
    SharedPreferences.setMockInitialValues({});
    await ProMaxSettings.load();
    expect(ProMaxSettings.showReadStamp.value, isTrue);

    await ProMaxSettings.setShowReadStamp(false);
    ProMaxSettings.showReadStamp.value = true;
    await ProMaxSettings.load();
    expect(ProMaxSettings.showReadStamp.value, isFalse);
  });
}
