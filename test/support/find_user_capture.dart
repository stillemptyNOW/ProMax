import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promax/core/config/promax_glass.dart';
import 'package:promax/frontend/screens/contacts/find_user_sheet.dart';
import 'package:promax/frontend/theme/promax_theme.dart';
import 'package:promax/l10n/app_localizations.dart';

void main() {
  testWidgets('capture the phone lookup sheet with synthetic input', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    for (final entry in {
      'Inter': 'assets/fonts/Inter.ttf',
      'packages/material_symbols_icons/MaterialSymbolsOutlined':
          'packages/material_symbols_icons/lib/fonts/MaterialSymbolsOutlined.ttf',
    }.entries) {
      await (FontLoader(
        entry.key,
      )..addFont(rootBundle.load(entry.value))).load();
    }
    final capture = GlobalKey();
    final scheme = proMaxDarkScheme(
      ColorScheme.fromSeed(
        seedColor: const Color(0xffb6a0ff),
        brightness: Brightness.dark,
      ),
      amoled: false,
    );
    await tester.pumpWidget(
      RepaintBoundary(
        key: capture,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          locale: const Locale('ru'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: buildProMaxTheme(
            scheme: scheme,
            fontId: 'inter',
            glass: ProMaxGlassTheme.current(),
          ),
          home: Scaffold(
            appBar: AppBar(title: const Text('Контакты')),
            body: Builder(
              builder: (context) => Center(
                child: FilledButton(
                  onPressed: () => showFindUserSheet(
                    context,
                    title: 'Найти контакт',
                    actionLabel: 'Найти',
                  ),
                  child: const Text('Открыть'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Открыть'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '0000000000');
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.runAsync(() async {
      final image =
          await (capture.currentContext!.findRenderObject()!
                  as RenderRepaintBoundary)
              .toImage(pixelRatio: 2);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      final output = Directory(r'D:\ProMax-build-temp\contact-preview');
      await output.create(recursive: true);
      await File(
        '${output.path}/phone-search.png',
      ).writeAsBytes(data!.buffer.asUint8List());
      image.dispose();
    });
  });
}
