import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promax/core/config/app_liquid_glass.dart';
import 'package:promax/core/config/promax_glass.dart';
import 'package:promax/core/config/promax_theme_presets.dart';
import 'package:promax/frontend/widgets/liquid_glass.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _defaults = ProMaxGlassTheme(
  blur: 1,
  refraction: 11,
  specular: 1,
  chroma: 0,
  rim: 0.5,
  tint: 1,
);

ColorScheme _scheme(Brightness brightness) => ColorScheme.fromSeed(
  seedColor: const Color(0xFF3390EC),
  brightness: brightness,
);

double _scaleOf(WidgetTester tester) {
  final transform = tester.widget<Transform>(
    find.descendant(
      of: find.byType(GlassPressEffect),
      matching: find.byType(Transform),
    ),
  );
  return transform.transform.entry(0, 0);
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('panel glass follows the Telegram fill and rim recipe', () {
    final light = AppLiquidGlass.material(
      _scheme(Brightness.light),
      GlassRole.panel,
      glass: _defaults,
    );
    expect(light.fill.a, closeTo(0.85, 0.001));
    expect(light.rim.top, const Color(0xFFFFFFFF));
    expect(light.rim.bottom, const Color(0xFFFFFFFF));
    expect(light.rim.width, 0.5);
    expect(light.blurSigma, AppLiquidGlass.blurSigma);
    expect(light.thickness, 11);
    expect(light.shadow.contact, const Color(0x20000000));

    final dark = AppLiquidGlass.material(
      _scheme(Brightness.dark),
      GlassRole.panel,
      glass: _defaults,
    );
    expect(dark.rim.top, const Color(0x28FFFFFF));
    expect(dark.rim.bottom, const Color(0x14FFFFFF));
    expect(dark.shadow.contact.a, 0);
  });

  test('bar glass uses the main tabs hairlines and frosted fallback', () {
    final cs = _scheme(Brightness.light);
    final bar = AppLiquidGlass.material(cs, GlassRole.bar, glass: _defaults);
    expect(bar.rim.top, const Color(0x11000000));
    expect(bar.rim.bottom, const Color(0x20000000));
    expect(bar.rim.width, closeTo(0.4, 0.001));

    final frosted = AppLiquidGlass.material(
      cs,
      GlassRole.bar,
      glass: _defaults,
      frosted: true,
    );
    expect(frosted.fill.a, closeTo(0.76, 0.001));
    expect(frosted.blurSigma, AppLiquidGlass.frostedBlurSigma);
  });

  test('a custom tint is painted over the glass fill', () {
    final cs = _scheme(Brightness.light);
    final tinted = AppLiquidGlass.material(
      cs,
      GlassRole.panel,
      glass: _defaults,
      tint: cs.error,
    );
    expect(tinted.fill, cs.error);
    final clear = AppLiquidGlass.material(
      cs,
      GlassRole.panel,
      glass: _defaults,
      tint: cs.error.withValues(alpha: 0),
    );
    expect(clear.fill.a, closeTo(0.85, 0.001));
  });

  testWidgets('pressing glass lifts it by 20 points and springs back', (
    tester,
  ) async {
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: SizedBox(
            width: 200,
            height: 50,
            child: GlassPressEffect(
              borderRadius: BorderRadius.all(Radius.circular(25)),
              child: SizedBox.expand(),
            ),
          ),
        ),
      ),
    );
    expect(_scaleOf(tester), 1);

    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(GlassPressEffect)),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(_scaleOf(tester), closeTo(1 + 20 / 200, 0.002));

    await gesture.up();
    await tester.pumpAndSettle();
    expect(_scaleOf(tester), 1);
  });

  testWidgets('disabled glass ignores presses', (tester) async {
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: SizedBox(
            width: 80,
            height: 80,
            child: GlassPressEffect(
              borderRadius: BorderRadius.all(Radius.circular(40)),
              enabled: false,
              child: SizedBox.expand(),
            ),
          ),
        ),
      ),
    );
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(GlassPressEffect)),
    );
    await tester.pump(const Duration(milliseconds: 500));
    expect(_scaleOf(tester), 1);
    await gesture.up();
  });

  testWidgets('glass degrades to a saturated frost without the shader', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(colorScheme: _scheme(Brightness.light)),
        home: const Scaffold(
          body: Center(
            child: SizedBox(
              width: 240,
              height: 56,
              child: LiquidGlassSurface(
                borderRadius: BorderRadius.all(Radius.circular(28)),
                child: Text('Синтетика'),
              ),
            ),
          ),
        ),
      ),
    );
    expect(LiquidGlass.isSupported, isFalse);
    expect(find.byType(BackdropFilter), findsOneWidget);
    expect(find.text('Синтетика'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test(
    'an outdated look resets hand-tuned glass to the new defaults',
    () async {
      SharedPreferences.setMockInitialValues({
        'promax_glass_look_version': 2,
        'app_accent_seed': 0xFF3390EC,
        'promax_glass_rim': 2.6,
        'promax_glass_specular': 0.85,
      });
      await ProMaxThemePresets.ensureDefault();
      await ProMaxGlass.load();
      expect(ProMaxGlass.rim.value, ProMaxGlass.rim.defaultValue);
      expect(ProMaxGlass.specular.value, ProMaxGlass.specular.defaultValue);
    },
  );
}
