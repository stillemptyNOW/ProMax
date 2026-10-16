import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promax/frontend/screens/webapp/mini_app_privacy.dart';

MiniAppPrivacy _privacy(
  TargetPlatform platform, {
  bool isolated = true,
  bool blockTrackers = true,
}) => MiniAppPrivacy(
  isolated: isolated,
  blockTrackers: blockTrackers,
  platform: platform,
);

void main() {
  test('Android не включает глобальный incognito и чистит данные сам', () {
    final android = _privacy(TargetPlatform.android);
    expect(android.incognito, isFalse);
    expect(android.wipesVisitedOriginsOnClose, isTrue);
    expect(android.trackerBlocking, TrackerBlockingMode.interceptRequests);
    expect(android.contentBlockers, isEmpty);
  });

  test('iOS и Windows изолируют через incognito', () {
    expect(_privacy(TargetPlatform.iOS).incognito, isTrue);
    expect(_privacy(TargetPlatform.macOS).incognito, isTrue);
    expect(_privacy(TargetPlatform.windows).incognito, isTrue);
    expect(_privacy(TargetPlatform.iOS).wipesVisitedOriginsOnClose, isFalse);
  });

  test('на iOS трекеры режет нативный блокировщик', () {
    final ios = _privacy(TargetPlatform.iOS);
    expect(ios.trackerBlocking, TrackerBlockingMode.contentBlockers);
    expect(ios.contentBlockers, isNotEmpty);
    expect(
      _privacy(TargetPlatform.windows).trackerBlocking,
      TrackerBlockingMode.interceptRequests,
    );
  });

  test('выключенные настройки ничего не меняют', () {
    final off = _privacy(
      TargetPlatform.iOS,
      isolated: false,
      blockTrackers: false,
    );
    expect(off.incognito, isFalse);
    expect(off.trackerBlocking, TrackerBlockingMode.none);
    expect(off.contentBlockers, isEmpty);
    expect(
      _privacy(
        TargetPlatform.android,
        isolated: false,
      ).wipesVisitedOriginsOnClose,
      isFalse,
    );
  });

  test('в вебе плагин не трогает куки и не перехватывает запросы', () {
    const web = MiniAppPrivacy(
      isolated: true,
      blockTrackers: true,
      platform: TargetPlatform.android,
      isWeb: true,
    );
    expect(web.incognito, isFalse);
    expect(web.wipesVisitedOriginsOnClose, isFalse);
    expect(web.trackerBlocking, TrackerBlockingMode.none);
  });

  test('посещённые источники запоминаются без Цифрового ID', () {
    final origins = MiniAppVisitedOrigins()
      ..note(Uri.parse('https://game.example.org/play?x=1'))
      ..note(Uri.parse('https://game.example.org/other'))
      ..note(Uri.parse('https://digital-id.max.ru/'))
      ..note(Uri.parse('about:blank'))
      ..note(null);
    expect(origins.origins, {'https://game.example.org'});
  });

  test('запрос к трекеру получает пустой ответ', () async {
    final blocked = await MiniAppPrivacy.interceptTracker(
      _NoController(),
      WebResourceRequest(url: WebUri('https://mc.yandex.ru/watch/1')),
    );
    expect(blocked?.statusCode, 403);
    final allowed = await MiniAppPrivacy.interceptTracker(
      _NoController(),
      WebResourceRequest(url: WebUri('https://game.example.org/app.js')),
    );
    expect(allowed, isNull);
  });
}

class _NoController implements InAppWebViewController {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
