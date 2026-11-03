import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:promax/core/config/app_design.dart';
import 'package:promax/core/security/app_lock.dart';
import 'package:promax/frontend/widgets/redesign_welcome_layer.dart';
import 'package:promax/l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  void package(int build) => PackageInfo.setMockInitialValues(
    appName: 'Synthetic',
    packageName: 'test.synthetic',
    version: '0.0.0',
    buildNumber: '$build',
    buildSignature: '',
  );

  Widget host({bool reducedMotion = false}) => MaterialApp(
    locale: const Locale('ru'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: MediaQuery(
      data: MediaQueryData(disableAnimations: reducedMotion),
      child: const Stack(
        fit: StackFit.expand,
        children: [Text('Synthetic app content'), RedesignWelcomeLayer()],
      ),
    ),
  );

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AppDesign.classic.value = false;
    AppLock.instance.locked.value = false;
    package(121);
  });
  tearDown(() {
    AppDesign.classic.value = false;
    AppLock.instance.locked.value = false;
  });

  testWidgets('plaintext welcome lasts fifteen seconds and never repeats', (
    tester,
  ) async {
    await tester.pumpWidget(host());
    await tester.pump();
    expect(find.text('Добро пожаловать в редизайн'), findsOneWidget);
    await tester.pump(const Duration(seconds: 14));
    expect(find.text('Добро пожаловать в редизайн'), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Добро пожаловать в редизайн'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(host());
    await tester.pump();
    expect(find.text('Добро пожаловать в редизайн'), findsNothing);
  });

  testWidgets('classic design and earlier builds skip the welcome', (
    tester,
  ) async {
    AppDesign.classic.value = true;
    await tester.pumpWidget(host());
    await tester.pump();
    expect(find.text('Добро пожаловать в редизайн'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    AppDesign.classic.value = false;
    package(120);
    await tester.pumpWidget(host());
    await tester.pump();
    expect(find.text('Добро пожаловать в редизайн'), findsNothing);
  });

  testWidgets('reduce motion keeps the welcome static and dismisses it', (
    tester,
  ) async {
    await tester.pumpWidget(host(reducedMotion: true));
    await tester.pump();
    expect(find.text('Добро пожаловать в редизайн'), findsOneWidget);
    expect(find.byType(AnimatedOpacity), findsNothing);
    await tester.pump(const Duration(seconds: 15));
    expect(find.text('Добро пожаловать в редизайн'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('locked startup waits until unlock before showing the welcome', (
    tester,
  ) async {
    AppLock.instance.locked.value = true;
    await tester.pumpWidget(host());
    await tester.pump(const Duration(seconds: 20));
    expect(find.text('Добро пожаловать в редизайн'), findsNothing);
    AppLock.instance.locked.value = false;
    await tester.pump();
    await tester.pump();
    expect(find.text('Добро пожаловать в редизайн'), findsOneWidget);
    await tester.pump(const Duration(seconds: 15));
    expect(find.text('Добро пожаловать в редизайн'), findsNothing);
  });
}
