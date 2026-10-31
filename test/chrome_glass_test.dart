import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promax/core/config/app_chrome_glass.dart';
import 'package:promax/core/config/app_native_glass.dart';
import 'package:promax/core/config/app_visual_style.dart';
import 'package:promax/frontend/widgets/chrome_glass.dart';
import 'package:promax/frontend/widgets/confirm_dialog.dart';
import 'package:promax/frontend/widgets/custom_notification.dart';
import 'package:promax/frontend/widgets/liquid_glass.dart';
import 'package:promax/frontend/widgets/native_glass_view.dart';
import 'package:promax/frontend/widgets/segmented_pill_toggle.dart';
import 'package:promax/l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _shaderKey = ValueKey<String>('shader');

Widget _app(Widget home) => MaterialApp(
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(body: Center(child: home)),
);

const _surface = SizedBox(
  width: 120,
  height: 40,
  child: LiquidGlassSurface(
    borderRadius: BorderRadius.all(Radius.circular(20)),
    child: Text('glass'),
  ),
);

Finder get _nativeView => find.byType(NativeGlassView, skipOffstage: false);

bool _nativeShown(WidgetTester tester) {
  if (_nativeView.evaluate().isEmpty) return false;
  return !tester
      .widget<Offstage>(
        find.ancestor(of: _nativeView, matching: find.byType(Offstage)).first,
      )
      .offstage;
}

bool _shaderShown() =>
    find.byKey(_shaderKey, skipOffstage: false).evaluate().isNotEmpty;

void _mockPlatformViews(WidgetTester tester) {
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.platform_views,
    (call) async => null,
  );
  addTearDown(
    () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform_views,
      null,
    ),
  );
}

void _onIos26(WidgetTester tester) {
  _mockPlatformViews(tester);
  NativeGlass.debugOverride(supported: true, enabled: true);
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    NativeGlass.debugReset();
    AppVisualStyle.current.value = VisualStyle.liquidGlass;
  });

  tearDown(() {
    NativeGlass.debugReset();
    AppVisualStyle.current.value = VisualStyle.liquidGlass;
  });

  group('ChromeGlass policy', () {
    bool liquid(VisualStyle style, {bool native = false, bool shader = true}) =>
        ChromeGlass.resolve(
          style: style,
          nativeActive: native,
          shaderSupported: shader,
        );

    test('the iOS 26 switch makes chrome glass in every non-flat style', () {
      expect(liquid(VisualStyle.liquidGlass, native: true), isTrue);
      expect(liquid(VisualStyle.glossy, native: true), isTrue);
      expect(liquid(VisualStyle.glossy, native: true, shader: false), isTrue);
    });

    test('Material You stays flat even with the switch on', () {
      expect(liquid(VisualStyle.materialYou, native: true), isFalse);
      expect(liquid(VisualStyle.materialYou), isFalse);
    });

    test('without the switch the visual style decides, as before', () {
      expect(liquid(VisualStyle.liquidGlass), isTrue);
      expect(liquid(VisualStyle.glossy), isFalse);
      expect(liquid(VisualStyle.liquidGlass, shader: false), isFalse);
    });

    test('follows the live settings', () {
      AppVisualStyle.current.value = VisualStyle.glossy;
      expect(ChromeGlass.isLiquid, isFalse);
      NativeGlass.debugOverride(supported: true);
      expect(ChromeGlass.isLiquid, isTrue);
      NativeGlass.debugOverride(enabled: false);
      expect(ChromeGlass.isLiquid, isFalse);
    });
  });

  group('LiquidGlassSurface hosting', () {
    testWidgets('keeps the Flutter glass until the system view exists', (
      tester,
    ) async {
      _onIos26(tester);
      await tester.pumpWidget(_app(_surface));

      expect(_nativeView, findsOneWidget);
      expect(_nativeShown(tester), isFalse);
      expect(_shaderShown(), isTrue);

      await tester.pump();
      await tester.pump();
      expect(_nativeShown(tester), isTrue);
      expect(_shaderShown(), isFalse);
      expect(find.text('glass'), findsOneWidget);
    });

    testWidgets('scrolling content can opt out of the system glass', (
      tester,
    ) async {
      _onIos26(tester);
      await tester.pumpWidget(
        _app(
          const SizedBox(
            width: 80,
            height: 40,
            child: LiquidGlassSurface(
              native: false,
              borderRadius: BorderRadius.zero,
            ),
          ),
        ),
      );
      await tester.pump();
      expect(_nativeView, findsNothing);
    });

    testWidgets('an explicit hold keeps the shader and spares the view', (
      tester,
    ) async {
      _onIos26(tester);
      final held = ValueNotifier(true);
      addTearDown(held.dispose);
      await tester.pumpWidget(
        _app(
          ValueListenableBuilder<bool>(
            valueListenable: held,
            builder: (context, value, _) => NativeGlassHold(
              held: value,
              child: const NativeGlassHold(held: false, child: _surface),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(_nativeShown(tester), isFalse);
      expect(_shaderShown(), isTrue);

      expect(_nativeView, findsNothing);

      held.value = false;
      await tester.pump();
      expect(_nativeView, findsOneWidget);
      expect(_shaderShown(), isTrue);
      await tester.pump();
      await tester.pump();
      expect(_nativeShown(tester), isTrue);
      expect(_shaderShown(), isFalse);
    });

    testWidgets('a surface that is never released creates no system view', (
      tester,
    ) async {
      _onIos26(tester);
      await tester.pumpWidget(
        _app(const NativeGlassHold(held: true, child: _surface)),
      );
      await tester.pump();
      await tester.pump();
      expect(_nativeView, findsNothing);
      expect(_shaderShown(), isTrue);
    });

    testWidgets('an animation hold releases only once the animation ends', (
      tester,
    ) async {
      _onIos26(tester);
      final controller = AnimationController(
        vsync: const TestVSync(),
        duration: const Duration(milliseconds: 200),
      );
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        _app(NativeGlassAnimationHold(animation: controller, child: _surface)),
      );
      controller.forward();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(_nativeShown(tester), isFalse);

      await tester.pump(const Duration(milliseconds: 150));
      await tester.pump();
      await tester.pump();
      await tester.pump();
      expect(_nativeShown(tester), isTrue);

      controller.reverse();
      await tester.pump();
      expect(_nativeShown(tester), isFalse);
      await tester.pump(const Duration(milliseconds: 250));
    });

    testWidgets('a fade holds the system glass until it settles visible', (
      tester,
    ) async {
      _onIos26(tester);
      final visible = ValueNotifier(false);
      addTearDown(visible.dispose);
      await tester.pumpWidget(
        _app(
          ValueListenableBuilder<bool>(
            valueListenable: visible,
            builder: (context, value, _) => NativeGlassAnimatedOpacity(
              opacity: value ? 1 : 0,
              duration: const Duration(milliseconds: 200),
              child: _surface,
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(_nativeShown(tester), isFalse);

      visible.value = true;
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(_nativeShown(tester), isFalse);

      await tester.pump(const Duration(milliseconds: 150));
      await tester.pump();
      await tester.pump();
      await tester.pump();
      expect(_nativeShown(tester), isTrue);
    });

    testWidgets('dialogs use the shader while their route animates', (
      tester,
    ) async {
      _onIos26(tester);
      await tester.pumpWidget(
        _app(
          Builder(
            builder: (context) => TextButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => const Center(child: _surface),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(_nativeShown(tester), isFalse);
      expect(_shaderShown(), isTrue);

      await tester.pumpAndSettle();
      expect(_nativeShown(tester), isTrue);

      Navigator.of(tester.element(_nativeView)).pop();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 20));
      expect(_nativeShown(tester), isFalse);
      await tester.pumpAndSettle();
    });
  });

  group('converted chrome', () {
    testWidgets('notifications are glass with the switch and frost without', (
      tester,
    ) async {
      _onIos26(tester);
      AppVisualStyle.current.value = VisualStyle.glossy;
      await tester.pumpWidget(_app(const SizedBox()));
      final context = tester.element(find.byType(Scaffold));

      showCustomNotification(context, 'saved');
      await tester.pump();
      expect(find.byType(LiquidGlassSurface), findsOneWidget);
      await tester.pump(const Duration(seconds: 3));

      NativeGlass.debugOverride(enabled: false);
      showCustomNotification(context, 'saved');
      await tester.pump();
      expect(find.byType(LiquidGlassSurface), findsNothing);
      expect(find.byType(BackdropFilter), findsOneWidget);
      await tester.pump(const Duration(seconds: 3));
    });

    testWidgets('the confirm dialog keeps AlertDialog for Material You', (
      tester,
    ) async {
      _onIos26(tester);
      AppVisualStyle.current.value = VisualStyle.materialYou;
      await tester.pumpWidget(_app(const SizedBox()));
      final context = tester.element(find.byType(Scaffold));

      final first = showConfirmDialog(context, message: 'sure?');
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.byType(LiquidGlassSurface), findsNothing);
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(await first, isTrue);

      AppVisualStyle.current.value = VisualStyle.liquidGlass;
      final second = showConfirmDialog(context, message: 'sure?');
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.byType(LiquidGlassSurface), findsOneWidget);
      expect(_nativeShown(tester), isTrue);
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(await second, isTrue);
    });

    testWidgets('the segmented toggle switches its track with the setting', (
      tester,
    ) async {
      _onIos26(tester);
      AppVisualStyle.current.value = VisualStyle.materialYou;
      var selected = 0;
      await tester.pumpWidget(
        _app(
          StatefulBuilder(
            builder: (context, setState) => SegmentedPillToggle(
              labels: const ['a', 'b'],
              selected: selected,
              onChanged: (i) => setState(() => selected = i),
            ),
          ),
        ),
      );
      expect(find.byType(LiquidGlassSurface), findsNothing);

      AppVisualStyle.current.value = VisualStyle.glossy;
      await tester.pump();
      expect(find.byType(LiquidGlassSurface), findsOneWidget);
      await tester.tap(find.text('b'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(selected, 1);
    });

    testWidgets('the back button turns into a glass circle', (tester) async {
      _onIos26(tester);
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => Scaffold(
                    appBar: AppBar(leading: const ChromeImpliedLeading()),
                  ),
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.byType(ChromeBackButton), findsOneWidget);
      expect(find.byType(BackButton), findsNothing);

      NativeGlass.debugOverride(enabled: false);
      AppVisualStyle.current.value = VisualStyle.glossy;
      await tester.pump();
      expect(find.byType(ChromeBackButton), findsNothing);
      expect(find.byType(BackButton), findsOneWidget);

      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.text('open'), findsOneWidget);
    });
  });
}
