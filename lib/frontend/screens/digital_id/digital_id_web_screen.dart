import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../../../backend/modules/webapp.dart'
    show DigitalIdCallback, WebAppLaunch;
import '../../../core/security/webview_sandbox.dart';
import '../../../core/utils/logger.dart';
import '../../../core/utils/link_opener.dart';
import '../../../l10n/app_localizations.dart';
import '../../../main.dart' show digitalIdModule, webAppModule;
import '../webapp/web_app_bridge.dart';
import '../webapp/web_app_screen.dart';

Future<void> resetDigitalIdWebData() async {
  await CookieManager.instance(
    webViewEnvironment: await WebViewSandbox.environment(),
  ).deleteAllCookies();
  try {
    await WebStorageManager.instance().deleteAllData();
  } catch (_) {}
}

Future<void> resetDigitalIdSession() async {
  digitalIdModule.reset();
  try {
    await resetDigitalIdWebData();
  } catch (_) {}
}

class DigitalIdWebScreen extends StatefulWidget {
  final DigitalIdCallback? initialCallback;

  const DigitalIdWebScreen({super.key, this.initialCallback});

  @override
  State<DigitalIdWebScreen> createState() => _DigitalIdWebScreenState();
}

class _DigitalIdWebScreenState extends State<DigitalIdWebScreen> {
  late DigitalIdCallback? _callback = widget.initialCallback;

  Future<WebAppLaunch> _loadLaunch() =>
      _callback?.launch() ?? webAppModule.fetchDigitalId();

  Future<WebAppLaunch> _completeExternalCallback(String url) {
    final current = _callback;
    if (current != null && current.uri.toString() == url) {
      return current.launch();
    }
    return (_callback = webAppModule.digitalIdCallback(url)).launch();
  }

  @override
  Widget build(BuildContext context) {
    return WebAppScreen(
      title: AppLocalizations.of(context)!.digitalIdTitle,
      entryPoint: widget.initialCallback == null
          ? WebAppEntryPoint.webApp
          : WebAppEntryPoint.externalCallback,
      preferSystemUserAgent: true,
      privateChannel: true,
      recoverTechnicalError: true,
      mobileIdVerifier: digitalIdModule.fetchMobileIdVerification,
      loader: _loadLaunch,
      onExternalCallback: _completeExternalCallback,
      onConsoleMessage: (controller, consoleMessage) {
        final lvl = consoleMessage.messageLevel.toString().toUpperCase();
        if (kDebugMode) logger.i('[DID] console level: $lvl');
      },
      onLoadStart: (controller, url) {
        if (url != null) {
          logger.i('[DID] loadStart: ${url.scheme}://${url.host}${url.path}');
        }
      },
      shouldOverrideUrlLoading: (_, action, _) async {
        final uri = action.request.url;
        final url = uri?.toString() ?? '';
        final scheme = uri?.scheme ?? '';
        if (kDebugMode) {
          debugPrint('[PROMAX-DID] nav: ${uri?.scheme}://${uri?.host}');
        }
        if (scheme != 'http' && scheme != 'https') {
          if (context.mounted) await openExternalUrl(context, url);
          return NavigationActionPolicy.CANCEL;
        }
        return NavigationActionPolicy.ALLOW;
      },
    );
  }
}
