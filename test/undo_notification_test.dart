import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promax/frontend/widgets/undo_notification.dart';
import 'package:promax/l10n/app_localizations.dart';

void main() {
  late int committed;
  late int undone;

  setUp(() {
    committed = 0;
    undone = 0;
  });

  Widget host({bool tickers = true}) => MaterialApp(
    locale: const Locale('ru'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    builder: (context, child) => TickerMode(enabled: tickers, child: child!),
    home: Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: TextButton(
            onPressed: () => showUndoNotification(
              context,
              'Сообщение удалено',
              onCommit: () => committed++,
              onUndo: () => undone++,
            ),
            child: const Text('show'),
          ),
        ),
      ),
    ),
  );

  testWidgets('expires on the clock even when frames are paused', (
    tester,
  ) async {
    await tester.pumpWidget(host(tickers: false));
    await tester.tap(find.text('show'));
    await tester.pump(const Duration(seconds: 4));
    expect(committed, 0);

    await tester.pump(const Duration(seconds: 2));
    expect(committed, 1);
    expect(undone, 0);
    await tester.pumpAndSettle();
  });

  testWidgets('hiding the app commits right away', (tester) async {
    await tester.pumpWidget(host());
    await tester.tap(find.text('show'));
    await tester.pump(const Duration(milliseconds: 300));

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    await tester.pump();
    expect(committed, 1);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(committed, 1);
  });

  testWidgets('a pending commit can be flushed from outside', (tester) async {
    await tester.pumpWidget(host());
    await tester.tap(find.text('show'));
    await tester.pump(const Duration(milliseconds: 300));

    PendingUndo.commitPending();
    await tester.pumpAndSettle();
    expect(committed, 1);
    expect(find.text('Сообщение удалено'), findsNothing);
  });

  testWidgets('tearing the overlay down commits instead of dropping', (
    tester,
  ) async {
    await tester.pumpWidget(host());
    await tester.tap(find.text('show'));
    await tester.pump(const Duration(milliseconds: 300));

    await tester.pumpWidget(const SizedBox());
    expect(committed, 1);
    expect(undone, 0);
  });
}
