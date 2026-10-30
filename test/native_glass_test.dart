import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promax/core/config/app_liquid_glass.dart';
import 'package:promax/core/config/app_native_glass.dart';
import 'package:promax/core/config/app_visual_style.dart';
import 'package:promax/frontend/widgets/liquid_glass.dart';
import 'package:promax/frontend/widgets/native_glass_view.dart';
import 'package:promax/frontend/widgets/native_tab_bar.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _tint = Color(0xFF3390EC);

NativeTabItem _item(String title, {String? badge, String? key, int seed = 1}) =>
    NativeTabItem(
      title: title,
      symbol: 'circle',
      selectedSymbol: 'circle.fill',
      badge: badge,
      avatarKey: key,
      avatar: key == null ? null : Uint8List.fromList([seed, seed, seed]),
    );

NativeTabBarConfig _config({
  List<NativeTabItem>? items,
  int selected = 0,
  bool dark = true,
  Color tint = _tint,
}) => NativeTabBarConfig(
  items: items ?? [_item('a'), _item('b'), _item('c')],
  selectedIndex: selected,
  dark: dark,
  tint: tint,
);

class _PlatformViews {
  final List<MethodCall> calls = [];
  final Map<int, String> created = {};

  void install(WidgetTester tester) {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform_views,
      (call) async {
        calls.add(call);
        if (call.method == 'create') {
          final args = call.arguments as Map;
          created[args['id'] as int] = args['viewType'] as String;
        }
        return null;
      },
    );
  }

  void uninstall(WidgetTester tester) {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform_views,
      null,
    );
  }
}

Widget _host(Widget child, {Brightness brightness = Brightness.dark}) =>
    MaterialApp(
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: _tint,
          brightness: brightness,
        ),
      ),
      home: Scaffold(body: Center(child: child)),
    );

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    NativeGlass.debugReset();
  });

  tearDown(NativeGlass.debugReset);

  group('NativeGlass support', () {
    test('is off by default, as it is in tests and off iOS', () async {
      await NativeGlass.load();
      expect(NativeGlass.isSupported, isFalse);
      expect(NativeGlass.active, isFalse);
      expect(NativeGlass.enabled.value, isTrue);
    });

    test('is active only when supported and left switched on', () {
      NativeGlass.debugOverride(supported: true);
      expect(NativeGlass.active, isTrue);
      NativeGlass.debugOverride(enabled: false);
      expect(NativeGlass.active, isFalse);
      NativeGlass.debugOverride(supported: false, enabled: true);
      expect(NativeGlass.active, isFalse);
    });

    test('the switch is remembered', () async {
      NativeGlass.debugOverride(supported: true);
      await NativeGlass.save(false);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('app_native_glass'), isFalse);
      expect(NativeGlass.active, isFalse);
    });
  });

  group('NativeTabBarPolicy', () {
    test('the system tab bar follows the switch, not the pill style', () {
      bool use(VisualStyle style, {bool native = true}) =>
          NativeTabBarPolicy.shouldUse(
            nativeActive: native,
            visualStyle: style,
          );

      expect(use(VisualStyle.liquidGlass), isTrue);
      expect(use(VisualStyle.glossy), isTrue);
      expect(use(VisualStyle.materialYou), isFalse);
      expect(use(VisualStyle.liquidGlass, native: false), isFalse);
    });
  });

  group('NativeTabBarConfig', () {
    test('an unchanged bar sends nothing', () {
      expect(_config().updatesFrom(_config()), isEmpty);
    });

    test('a new selection is sent as a plain select', () {
      final calls = _config(selected: 2).updatesFrom(_config());
      expect(calls, hasLength(1));
      expect(calls.single.method, 'select');
      expect(calls.single.arguments, {'index': 2});
    });

    test('badge changes resend the items without the avatar bytes', () {
      final before = _config(
        items: [
          _item('a'),
          _item('s', key: 'me'),
        ],
      );
      final after = _config(
        items: [
          _item('a', badge: '3'),
          _item('s', key: 'me'),
        ],
      );
      final calls = after.updatesFrom(before);
      expect(calls.single.method, 'setItems');
      final items = (calls.single.arguments as Map)['items'] as List;
      expect((items[0] as Map)['badge'], '3');
      expect((items[1] as Map)['avatarKey'], 'me');
      expect((items[1] as Map).containsKey('avatar'), isFalse);
    });

    test('a new avatar is sent with its bytes', () {
      final before = _config(items: [_item('a'), _item('s')]);
      final after = _config(
        items: [
          _item('a'),
          _item('s', key: 'me'),
        ],
      );
      final items =
          (after.updatesFrom(before).single.arguments as Map)['items'] as List;
      expect((items[1] as Map)['avatar'], isA<Uint8List>());
      expect((items[0] as Map).containsKey('avatar'), isFalse);
    });

    test('theme changes restyle the bar', () {
      final calls = _config(dark: false).updatesFrom(_config());
      expect(calls.single.method, 'setStyle');
      expect(calls.single.arguments, {'dark': false, 'tint': _tint.toARGB32()});
    });

    test('creation params carry everything the bar needs', () {
      final params = _config(
        items: [
          _item('a'),
          _item('s', key: 'me'),
        ],
        selected: 1,
      ).creationParams();
      expect(params['selectedIndex'], 1);
      expect(params['dark'], isTrue);
      final items = params['items'] as List;
      expect(items, hasLength(2));
      expect((items[1] as Map)['avatar'], isA<Uint8List>());
    });

    test('only selections inside the bar are accepted', () {
      final config = _config();
      expect(config.acceptSelection({'index': 1}), 1);
      expect(config.acceptSelection({'index': 3}), isNull);
      expect(config.acceptSelection({'index': -1}), isNull);
      expect(config.acceptSelection({'index': '1'}), isNull);
      expect(config.acceptSelection(null), isNull);
    });
  });

  group('NativeGlassParams', () {
    test('keeps each corner and picks Telegram-like default tints', () {
      final dark = NativeGlassParams.surface(
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(1),
          topRight: Radius.circular(2),
          bottomLeft: Radius.circular(3),
          bottomRight: Radius.circular(4),
        ),
        brightness: Brightness.dark,
      );
      expect(dark.toMap(), {
        'radii': [1.0, 2.0, 3.0, 4.0],
        'dark': true,
        'style': 'regular',
        'tint': 0x06FFFFFF,
      });

      final overlay = NativeGlassParams.surface(
        borderRadius: BorderRadius.zero,
        brightness: Brightness.light,
        role: GlassRole.overlay,
      );
      expect(overlay.clear, isTrue);
      expect(overlay.tint, isNull);
    });

    test('a caller tint wins over the default', () {
      final params = NativeGlassParams.surface(
        borderRadius: BorderRadius.circular(20),
        brightness: Brightness.light,
        tint: const Color(0x40FF0000),
      );
      expect(params.tint, const Color(0x40FF0000));
    });
  });

  group('LiquidGlassSurface', () {
    testWidgets('stays on the Flutter glass when native glass is missing', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          const SizedBox(
            width: 120,
            height: 40,
            child: LiquidGlassSurface(borderRadius: BorderRadius.zero),
          ),
        ),
      );
      expect(find.byType(NativeGlassView), findsNothing);
    });

    testWidgets('renders the system glass behind its content on iOS 26', (
      tester,
    ) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      final views = _PlatformViews()..install(tester);
      NativeGlass.debugOverride(supported: true);

      await tester.pumpWidget(
        _host(
          const SizedBox(
            width: 120,
            height: 40,
            child: LiquidGlassSurface(
              borderRadius: BorderRadius.all(Radius.circular(20)),
              child: Text('glass'),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(NativeGlassView), findsOneWidget);
      expect(find.text('glass'), findsOneWidget);
      expect(views.created.values, contains(NativeGlass.glassViewType));
      final pointer = tester.widget<IgnorePointer>(
        find
            .ancestor(
              of: find.byType(UiKitView),
              matching: find.byType(IgnorePointer),
            )
            .first,
      );
      expect(pointer.ignoring, isTrue);

      NativeGlass.debugOverride(enabled: false);
      await tester.pump();
      expect(find.byType(NativeGlassView), findsNothing);

      await tester.pumpWidget(const SizedBox());
      views.uninstall(tester);
      debugDefaultTargetPlatformOverride = null;
    });
  });

  group('NativeTabBar', () {
    testWidgets('relays native selections and pushes Dart selections', (
      tester,
    ) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      final views = _PlatformViews()..install(tester);
      final sent = <MethodCall>[];
      final selections = <int>[];
      var selected = 0;
      late StateSetter rebuild;

      await tester.pumpWidget(
        _host(
          StatefulBuilder(
            builder: (context, setState) {
              rebuild = setState;
              return SizedBox(
                width: 360,
                child: NativeTabBar(
                  items: [_item('a'), _item('b'), _item('c')],
                  selectedIndex: selected,
                  onSelected: (index) {
                    selections.add(index);
                    setState(() => selected = index);
                  },
                ),
              );
            },
          ),
        ),
      );
      await tester.pump();

      final id = views.created.entries
          .firstWhere((e) => e.value == NativeGlass.tabBarViewType)
          .key;
      final channel = '${NativeGlass.tabBarViewType}/$id';
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        MethodChannel(channel),
        (call) async {
          sent.add(call);
          return call.method == 'intrinsicHeight' ? 70.0 : null;
        },
      );

      Future<void> nativeSays(String method, Object? args) async {
        await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
          channel,
          const StandardMethodCodec().encodeMethodCall(
            MethodCall(method, args),
          ),
          (_) {},
        );
        await tester.pump();
      }

      await nativeSays('selected', {'index': 2});
      expect(selections, [2]);
      expect(sent.where((c) => c.method == 'select'), isEmpty);

      await nativeSays('selected', {'index': 7});
      expect(selections, [2]);

      rebuild(() => selected = 1);
      await tester.pump();
      final selects = sent.where((c) => c.method == 'select').toList();
      expect(selects, hasLength(1));
      expect(selects.single.arguments, {'index': 1});

      await tester.pumpWidget(const SizedBox());
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        MethodChannel(channel),
        null,
      );
      views.uninstall(tester);
      debugDefaultTargetPlatformOverride = null;
    });
  });
}
