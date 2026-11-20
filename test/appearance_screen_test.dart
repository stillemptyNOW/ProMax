import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promax/core/config/app_bubble_shape.dart';
import 'package:promax/frontend/screens/profile/appearance_screen.dart';
import 'package:promax/l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('appearance message controls update the shared bubble setting', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({});
    await AppBubbleShape.load();
    addTearDown(AppBubbleShape.load);
    await tester.pumpWidget(_appearanceApp);

    final messageBubble = find
        .ancestor(
          of: find.text('Hi!'),
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is Container && widget.decoration is BoxDecoration,
          ),
        )
        .first;
    final original = tester.widget<Container>(messageBubble).decoration;
    final messages = find.widgetWithText(ChoiceChip, 'Chats');
    expect(messages, findsOneWidget);
    await tester.ensureVisible(messages);
    await tester.tap(messages);
    await tester.pumpAndSettle();

    final desktop = find.widgetWithText(ChoiceChip, 'TG Desktop');
    await tester.ensureVisible(desktop);
    await tester.tap(desktop);
    await tester.pumpAndSettle();
    expect(AppBubbleShape.current.value, BubbleStyle.desktop);
    expect(tester.widget<ChoiceChip>(desktop).selected, isTrue);

    expect(tester.widget<Container>(messageBubble).decoration, isNot(original));
    expect(tester.takeException(), isNull);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(AppBubbleShape.prefKey), 'desktop');
  });

  testWidgets('appearance accepts a valid hex accent after validation', (
    tester,
  ) async {
    await tester.pumpWidget(_appearanceApp);

    final openEditor = find.widgetWithText(OutlinedButton, 'Custom color');
    await tester.ensureVisible(openEditor);
    await tester.tap(openEditor);
    await tester.pumpAndSettle();

    final hex = find.byType(TextField);
    await tester.ensureVisible(hex);
    await tester.enterText(hex, '#OO77AA');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(find.text('Enter a color in #RRGGBB format'), findsOneWidget);

    await tester.enterText(hex, '0077aa');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(
      find.widgetWithText(OutlinedButton, 'Custom color · #0077AA'),
      findsOneWidget,
    );
    expect(find.text('Enter a color in #RRGGBB format'), findsNothing);
  });
}

const _appearanceApp = MaterialApp(
  locale: Locale('en'),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: AppearanceScreen(),
);
