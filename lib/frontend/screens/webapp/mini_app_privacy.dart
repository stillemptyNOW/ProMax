import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../../../core/privacy/host_policy.dart';
import '../../../core/utils/logger.dart';

enum TrackerBlockingMode { none, contentBlockers, interceptRequests }

class MiniAppPrivacy {
  const MiniAppPrivacy({
    required this.isolated,
    required this.blockTrackers,
    required this.platform,
  });

  final bool isolated;
  final bool blockTrackers;
  final TargetPlatform platform;

  bool get _isAppleWebKit =>
      platform == TargetPlatform.iOS || platform == TargetPlatform.macOS;

  bool get incognito =>
      isolated && (_isAppleWebKit || platform == TargetPlatform.windows);

  bool get wipesVisitedOriginsOnClose =>
      isolated && platform == TargetPlatform.android;

  TrackerBlockingMode get trackerBlocking {
    if (!blockTrackers) return TrackerBlockingMode.none;
    if (_isAppleWebKit) return TrackerBlockingMode.contentBlockers;
    if (platform == TargetPlatform.android ||
        platform == TargetPlatform.windows) {
      return TrackerBlockingMode.interceptRequests;
    }
    return TrackerBlockingMode.none;
  }

  List<ContentBlocker> get contentBlockers =>
      trackerBlocking == TrackerBlockingMode.contentBlockers
      ? [
          for (final filter in HostPolicy.trackerUrlFilters())
            ContentBlocker(
              trigger: ContentBlockerTrigger(urlFilter: filter),
              action: ContentBlockerAction(
                type: ContentBlockerActionType.BLOCK,
              ),
            ),
        ]
      : const [];

  static Future<WebResourceResponse?> interceptTracker(
    InAppWebViewController controller,
    WebResourceRequest request,
  ) async {
    if (!HostPolicy.isTracker(request.url)) return null;
    return WebResourceResponse(
      contentType: 'text/plain',
      contentEncoding: 'utf-8',
      data: Uint8List(0),
      statusCode: 403,
      reasonPhrase: 'Forbidden',
    );
  }
}

class MiniAppVisitedOrigins {
  final Set<String> _origins = {};

  Set<String> get origins => Set.unmodifiable(_origins);

  void note(Uri? url) {
    if (url == null) return;
    if (!url.isScheme('http') && !url.isScheme('https')) return;
    if (url.host.isEmpty || HostPolicy.isPersistentWebHost(url.host)) return;
    _origins.add(url.origin);
  }

  Future<void> wipe() async {
    final origins = List<String>.of(_origins);
    _origins.clear();
    final cookies = CookieManager.instance();
    final storage = WebStorageManager.instance();
    for (final origin in origins) {
      final url = WebUri(origin);
      try {
        await cookies.deleteCookies(url: url);
        for (final domain in HostPolicy.cookieDomainsToClear(url.host)) {
          await cookies.deleteCookies(url: url, domain: domain);
        }
      } catch (e) {
        logger.w('mini app cookies for $origin not cleared: $e');
      }
      try {
        await storage.deleteOrigin(origin: origin);
      } catch (e) {
        logger.w('mini app storage for $origin not cleared: $e');
      }
    }
  }
}
