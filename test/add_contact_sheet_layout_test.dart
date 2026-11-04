import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promax/frontend/screens/contacts/add_contact_sheet.dart';
import 'package:promax/l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('contact form fits a short screen above the keyboard', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 360);
    tester.view.viewInsets = const FakeViewPadding(bottom: 220);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showAddContactSheet(context),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    final form = find.byType(SingleChildScrollView);
    expect(form, findsOneWidget);
    final scrollable = find.descendant(
      of: form,
      matching: find.byType(Scrollable),
    );
    await tester.scrollUntilVisible(
      find.byType(TextField).last,
      80,
      scrollable: scrollable.first,
    );
    expect(tester.takeException(), isNull);
    expect(
      tester.getRect(find.byType(TextField).last).bottom,
      lessThanOrEqualTo(140),
    );
  });
}
