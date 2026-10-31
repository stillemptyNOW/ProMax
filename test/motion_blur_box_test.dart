import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promax/core/plugins/motion_blur/motion_blur_plugin.dart';
import 'package:promax/core/plugins/motion_blur/motion_blur_settings.dart';
import 'package:promax/frontend/widgets/motion_blur/motion_blur_box.dart';
import 'package:promax/frontend/widgets/motion_blur/motion_blur_page_transitions.dart';
import 'package:promax/frontend/widgets/motion_blur/motion_blur_scroll_behavior.dart';

const _enabled = MotionBlurSettings(enabled: true);

Widget _list({Widget Function(int index)? extra, double? cacheExtent}) =>
    ListView.builder(
      scrollCacheExtent: cacheExtent == null
          ? null
          : ScrollCacheExtent.pixels(cacheExtent),
      itemCount: 200,
      itemBuilder: (context, index) => SizedBox(
        key: ValueKey(index),
        height: 56,
        child: extra?.call(index) ?? Text('Row $index'),
      ),
    );

Widget _app(Widget home, {bool disableAnimations = false}) => MaterialApp(
  scrollBehavior: const MotionBlurScrollBehavior(MaterialScrollBehavior()),
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(disableAnimations: disableAnimations),
    child: child!,
  ),
  home: Scaffold(body: home),
);

Iterable<RenderMotionBlur> _hosts(WidgetTester tester) =>
    tester.allRenderObjects.whereType<RenderMotionBlur>();

bool _filterLayerPresent(WidgetTester tester) {
  var found = false;
  void visit(Layer layer) {
    if (layer is ImageFilterLayer) found = true;
    if (layer is ContainerLayer) {
      var child = layer.firstChild;
      while (child != null) {
        visit(child);
        child = child.nextSibling;
      }
    }
  }

  visit(tester.layers.first);
  return found;
}

Future<bool> _blursWhileFlinging(WidgetTester tester) async {
  await tester.fling(find.byType(ListView), const Offset(0, -500), 4000);
  var blurred = false;
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 16));
    if (_hosts(tester).any((host) => host.isBlurring) &&
        _filterLayerPresent(tester)) {
      blurred = true;
    }
  }
  return blurred;
}

void main() {
  tearDown(() => MotionBlurPlugin.instance.debugOverride());

  testWidgets('wraps every scrollable without a filter at rest', (
    tester,
  ) async {
    MotionBlurPlugin.instance.debugOverride(settings: _enabled);
    await tester.pumpWidget(_app(_list()));
    expect(_hosts(tester), isNotEmpty);
    expect(_hosts(tester).any((host) => host.isBlurring), isFalse);
    expect(_filterLayerPresent(tester), isFalse);
  });

  testWidgets('blurs while scrolling and rests afterwards', (tester) async {
    MotionBlurPlugin.instance.debugOverride(settings: _enabled);
    await tester.pumpWidget(_app(_list()));
    expect(await _blursWhileFlinging(tester), isTrue);
    final host = _hosts(tester).firstWhere((host) => host.isBlurring);
    expect(host.debugFilter, isNotNull);
    await tester.pumpAndSettle();
    expect(_hosts(tester).any((host) => host.isBlurring), isFalse);
    expect(_filterLayerPresent(tester), isFalse);
  });

  testWidgets('does nothing while the plugin is disabled', (tester) async {
    MotionBlurPlugin.instance.debugOverride();
    await tester.pumpWidget(_app(_list()));
    expect(await _blursWhileFlinging(tester), isFalse);
    await tester.pumpAndSettle();
  });

  testWidgets('respects the scrolling switch', (tester) async {
    MotionBlurPlugin.instance.debugOverride(
      settings: _enabled.withTarget(MotionBlurTarget.scrolling, false),
    );
    await tester.pumpWidget(_app(_list()));
    expect(await _blursWhileFlinging(tester), isFalse);
    await tester.pumpAndSettle();
  });

  testWidgets('never blurs with reduced motion', (tester) async {
    MotionBlurPlugin.instance.debugOverride(settings: _enabled);
    await tester.pumpWidget(_app(_list(), disableAnimations: true));
    expect(await _blursWhileFlinging(tester), isFalse);
    await tester.pumpAndSettle();
  });

  testWidgets('skips subtrees that host platform views', (tester) async {
    MotionBlurPlugin.instance.debugOverride(settings: _enabled);
    await tester.pumpWidget(
      _app(
        _list(
          extra: (index) => index == 0
              ? const MotionBlurExclusion(child: SizedBox.expand())
              : Text('Row $index'),
          cacheExtent: 20000,
        ),
      ),
    );
    expect(await _blursWhileFlinging(tester), isFalse);
    await tester.pumpAndSettle();
  });

  testWidgets('keeps the blur when a screen narrows the scroll behavior', (
    tester,
  ) async {
    MotionBlurPlugin.instance.debugOverride(settings: _enabled);
    await tester.pumpWidget(
      _app(
        Builder(
          builder: (context) => ScrollConfiguration(
            behavior: ScrollConfiguration.of(
              context,
            ).copyWith(scrollbars: false, overscroll: false),
            child: _list(),
          ),
        ),
      ),
    );
    expect(await _blursWhileFlinging(tester), isTrue);
    await tester.pumpAndSettle();
  });

  testWidgets('blurs a page during a route transition', (tester) async {
    MotionBlurPlugin.instance.debugOverride(
      settings: _enabled.withTarget(MotionBlurTarget.scrolling, false),
    );
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigator,
        theme: ThemeData(
          pageTransitionsTheme: const PageTransitionsTheme(
            builders: {
              TargetPlatform.android: MotionBlurPageTransitionsBuilder(
                CupertinoPageTransitionsBuilder(),
              ),
            },
          ),
        ),
        home: const Scaffold(body: Text('first')),
      ),
    );
    expect(_filterLayerPresent(tester), isFalse);
    navigator.currentState!.push(
      MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('second')),
      ),
    );
    var blurred = false;
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      if (_filterLayerPresent(tester)) blurred = true;
    }
    expect(blurred, isTrue);
    await tester.pumpAndSettle();
    expect(_filterLayerPresent(tester), isFalse);
  });

  testWidgets('preview blurs even while the plugin is disabled', (
    tester,
  ) async {
    MotionBlurPlugin.instance.debugOverride();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ScrollConfiguration(
            behavior: const MotionBlurScrollBehavior(
              MaterialScrollBehavior(),
              preview: true,
            ),
            child: _list(),
          ),
        ),
      ),
    );
    expect(await _blursWhileFlinging(tester), isTrue);
    await tester.pumpAndSettle();
  });
}
