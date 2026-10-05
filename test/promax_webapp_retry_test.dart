import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promax/backend/modules/webapp.dart';
import 'package:promax/frontend/screens/webapp/web_app_screen.dart';
import 'package:promax/l10n/app_localizations.dart';
import 'package:promax/main.dart' show api;

class _Controller extends PlatformInAppWebViewController {
  _Controller()
    : super.implementation(
        const PlatformInAppWebViewControllerCreationParams(id: 'synthetic'),
      );

  final handlers = <String, JavaScriptHandlerCallback>{};
  bool technicalError = true;

  @override
  Future<String> getDefaultUserAgent() async => 'Synthetic WebView';

  @override
  void addJavaScriptHandler({
    required String handlerName,
    required JavaScriptHandlerCallback callback,
  }) => handlers[handlerName] = callback;

  @override
  Future<dynamic> evaluateJavascript({
    required String source,
    ContentWorld? contentWorld,
  }) async => source.contains('innerText') ? technicalError : null;

  @override
  void dispose({bool isKeepAlive = false}) {}
}

class _WebWidget extends PlatformInAppWebViewWidget {
  _WebWidget(PlatformInAppWebViewWidgetCreationParams params, this.controller)
    : super.implementation(params) {
    params.onWebViewCreated?.call(
      controllerFromPlatform<InAppWebViewController>(controller),
    );
  }

  final _Controller controller;

  @override
  Widget build(BuildContext context) => const SizedBox.expand();

  @override
  T controllerFromPlatform<T>(PlatformInAppWebViewController controller) =>
      params.controllerFromPlatform!(controller) as T;

  @override
  void dispose() => controller.dispose();
}

class _Platform extends InAppWebViewPlatform {
  final views = <_WebWidget>[];

  @override
  PlatformInAppWebViewController createPlatformInAppWebViewControllerStatic() =>
      _Controller();

  @override
  PlatformInAppWebViewController createPlatformInAppWebViewController(
    PlatformInAppWebViewControllerCreationParams params,
  ) => _Controller();

  @override
  PlatformInAppWebViewWidget createPlatformInAppWebViewWidget(
    PlatformInAppWebViewWidgetCreationParams params,
  ) {
    final view = _WebWidget(params, _Controller());
    views.add(view);
    return view;
  }
}

void main() {
  setUpAll(() => api.state);
  tearDownAll(() => api.dispose());
  late _Platform platform;
  setUp(() {
    platform = _Platform();
    InAppWebViewPlatform.instance = platform;
  });

  Future<void> open(
    WidgetTester tester,
    Future<WebAppLaunch> Function() loader,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('ru'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => WebAppScreen(
                    title: 'Synthetic digital ID',
                    loader: loader,
                    preferSystemUserAgent: true,
                    privateChannel: true,
                    recoverTechnicalError: true,
                  ),
                ),
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  testWidgets(
    'technical error retry fetches a new URL and keeps the screen open',
    (tester) async {
      var launches = 0;
      await open(
        tester,
        () async => WebAppLaunch(
          botId: 101,
          url: 'https://example.test/digital-id?launch=${++launches}',
        ),
      );
      expect(launches, 1);
      final first = platform.views.single;
      await first.controller.handlers['webAppEvent']!([
        'WebAppClose',
        '{}',
        false,
      ]);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 20));
      expect(launches, 2);
      expect(find.text('Synthetic digital ID'), findsOneWidget);
      expect(platform.views.length, 2);
      expect(
        platform.views.last.params.initialUrlRequest!.url.toString(),
        'https://example.test/digital-id?launch=2',
      );
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('normal close still leaves the mini app', (tester) async {
    var launches = 0;
    await open(tester, () async {
      launches++;
      return const WebAppLaunch(
        botId: 101,
        url: 'https://example.test/digital-id',
      );
    });
    final controller = platform.views.single.controller..technicalError = false;
    await controller.handlers['webAppEvent']!(['WebAppClose', '{}', false]);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
    expect(launches, 1);
    expect(find.text('Open'), findsOneWidget);
    expect(find.text('Synthetic digital ID'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
}
