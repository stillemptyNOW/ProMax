abstract final class NeutralUserAgent {
  static const String product = 'OKMessages';

  static const String mobileWeb =
      'Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/136.0.0.0 Mobile Safari/537.36';

  static final RegExp _androidPlatform = RegExp(
    r'\(Linux;[^)]*\bAndroid\b[^)]*\)',
  );
  static final RegExp _webViewToken = RegExp(r';\s*wv\s*\)$');
  static final RegExp _chromiumVersion = RegExp(
    r'\b(Chrome|CriOS|EdgA|Edg)/(\d+)(?:\.\d+)+',
  );
  static final RegExp _productToken = RegExp(r'^[^\s/()]+/[^\s()]+');

  static String cdn(String appVersion) => '$product/$appVersion (Android)';

  static String cdnFromSession(String sessionUserAgent) {
    final productToken = _productToken.firstMatch(sessionUserAgent.trim());
    return '${productToken?.group(0) ?? product} (Android)';
  }

  static String webView(String? systemUserAgent) {
    final agent = systemUserAgent?.trim() ?? '';
    if (agent.isEmpty) return mobileWeb;
    final withoutDevice = agent.replaceFirstMapped(
      _androidPlatform,
      (match) => _webViewToken.hasMatch(match[0]!)
          ? '(Linux; Android 10; K; wv)'
          : '(Linux; Android 10; K)',
    );
    return withoutDevice.replaceAllMapped(
      _chromiumVersion,
      (match) => '${match[1]}/${match[2]}.0.0.0',
    );
  }
}
