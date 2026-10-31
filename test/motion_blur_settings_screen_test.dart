import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promax/core/plugins/motion_blur/motion_blur_plugin.dart';
import 'package:promax/frontend/screens/profile/motion_blur_settings_screen.dart';
import 'package:promax/frontend/screens/profile/native_plugin_entries.dart';
import 'package:promax/frontend/widgets/motion_blur/motion_blur_box.dart';
import 'package:promax/l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

Widget _host(Widget child) => MaterialApp(
  locale: const Locale('ru'),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(body: child),
);

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    MotionBlurPlugin.instance.debugOverride();
  });

  tearDown(() => MotionBlurPlugin.instance.debugOverride());

  testWidgets('plugin card toggles the built-in and opens its settings', (
    tester,
  ) async {
    final entry = nativePluginEntries.single;
    await tester.pumpWidget(_host(NativePluginCard(entry: entry)));
    expect(find.text('Motion Blur'), findsOneWidget);
    expect(
      find.text('Встроенный плагин ProMax', findRichText: true),
      findsNothing,
    );
    final toggle = find.byType(Switch);
    expect(tester.widget<Switch>(toggle).value, isFalse);

    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(MotionBlurPlugin.instance.enabled.value, isTrue);
    final prefs = await SharedPreferences.getInstance();
    expect(
      prefs.getString(MotionBlurPlugin.prefKey),
      contains('"enabled":true'),
    );

    await tester.tap(find.text('Настроить'));
    await tester.pumpAndSettle();
    expect(find.byType(MotionBlurSettingsScreen), findsOneWidget);
  });

  testWidgets('settings screen edits the targets and shows a preview', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 4000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_host(const MotionBlurSettingsScreen()));
    await tester.pumpAndSettle();
    expect(find.byType(MotionBlurPreview), findsOneWidget);
    await tester.tap(find.text('Проиграть переход'));
    var blurred = false;
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      blurred |= tester.allRenderObjects.whereType<RenderMotionBlur>().any(
        (host) => host.isBlurring,
      );
    }
    expect(blurred, isTrue);
    await tester.pumpAndSettle();

    final scrolling = find.text('Прокрутка');
    await tester.tap(scrolling);
    await tester.pumpAndSettle();
    expect(
      MotionBlurPlugin.instance.settings.value.targets.map((t) => t.name),
      isNot(contains('scrolling')),
    );
  });
}
