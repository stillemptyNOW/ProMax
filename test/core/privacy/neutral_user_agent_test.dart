import 'package:flutter_test/flutter_test.dart';
import 'package:promax/core/privacy/neutral_user_agent.dart';

void main() {
  test('из WebView-агента Android убираются модель, сборка и версия', () {
    const system =
        'Mozilla/5.0 (Linux; Android 14; Synthetic-X1 Build/SYN1.000000.001; '
        'wv) AppleWebKit/537.36 (KHTML, like Gecko) Version/4.0 '
        'Chrome/124.0.6367.82 Mobile Safari/537.36';
    final agent = NeutralUserAgent.webView(system);
    expect(
      agent,
      'Mozilla/5.0 (Linux; Android 10; K; wv) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Version/4.0 Chrome/124.0.0.0 Mobile Safari/537.36',
    );
    expect(agent, isNot(contains('Synthetic')));
    expect(agent, isNot(contains('Build/')));
  });

  test('браузерный агент Android сводится к урезанному виду Chrome', () {
    const system =
        'Mozilla/5.0 (Linux; Android 13; Synthetic-Y2) AppleWebKit/537.36 '
        '(KHTML, like Gecko) Chrome/120.0.6099.230 Mobile Safari/537.36';
    expect(
      NeutralUserAgent.webView(system),
      'Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36',
    );
  });

  test('без системного агента берётся нейтральный мобильный', () {
    expect(NeutralUserAgent.webView(null), NeutralUserAgent.mobileWeb);
    expect(NeutralUserAgent.webView('  '), NeutralUserAgent.mobileWeb);
  });

  test('десктопный агент без модели не ломается', () {
    const system =
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
        '(KHTML, like Gecko) Chrome/130.0.2849.56 Safari/537.36 '
        'Edg/130.0.2849.56';
    expect(
      NeutralUserAgent.webView(system),
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/130.0.0.0 Safari/537.36 Edg/130.0.0.0',
    );
  });

  test('агент для CDN несёт только продукт и платформу', () {
    expect(NeutralUserAgent.cdn('1.2.3'), 'OKMessages/1.2.3 (Android)');
    expect(
      NeutralUserAgent.cdnFromSession(
        'OKMessages/1.2.3 (Android 14; Synthetic Phone; 1x1)',
      ),
      'OKMessages/1.2.3 (Android)',
    );
    expect(
      NeutralUserAgent.cdnFromSession('(no product)'),
      'OKMessages (Android)',
    );
  });
}
