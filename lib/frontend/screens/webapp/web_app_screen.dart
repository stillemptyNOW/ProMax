import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:path/path.dart' as p;

import '../../../backend/modules/webapp.dart';
import '../../../core/security/file_name_policy.dart';
import '../../../core/security/url_policy.dart';
import '../../../core/security/webview_sandbox.dart';
import '../../../core/storage/spoofing_service.dart';
import '../../../core/utils/file_names.dart';
import '../../../core/utils/link_opener.dart';
import '../../../core/utils/logger.dart';
import '../../../l10n/app_localizations.dart';
import '../../../main.dart' show api;
import '../../widgets/confirm_dialog.dart';
import '../../widgets/connection_status.dart';
import '../../widgets/error_view.dart';
import '../../widgets/sandbox_prompts.dart';
import '../../widgets/small_spinner.dart';
import '../../widgets/webview_permission_prompt.dart';
import 'web_app_bridge.dart';
import 'web_app_downloads.dart';
import 'web_app_origin_policy.dart';

class WebAppScreen extends StatefulWidget {
  final String title;
  final Future<WebAppLaunch> Function() loader;
  final String entryPoint;
  final bool privateChannel;
  final WebAppMobileIdVerifier? mobileIdVerifier;
  final List<UserScript>? extraUserScripts;
  final void Function(InAppWebViewController controller)? onWebViewCreated;
  final void Function(
    InAppWebViewController controller,
    ConsoleMessage consoleMessage,
  )?
  onConsoleMessage;
  final void Function(InAppWebViewController controller, WebUri? url)?
  onLoadStart;
  final Future<WebAppLaunch> Function(String url)? onExternalCallback;
  final bool closeAfterExternalCallback;
  final bool preferSystemUserAgent;
  final bool recoverTechnicalError;
  final Future<NavigationActionPolicy?> Function(
    InAppWebViewController controller,
    NavigationAction navigationAction,
    String? currentUrl,
  )?
  shouldOverrideUrlLoading;

  const WebAppScreen({
    super.key,
    required this.title,
    required this.loader,
    this.entryPoint = WebAppEntryPoint.webApp,
    this.privateChannel = false,
    this.mobileIdVerifier,
    this.extraUserScripts,
    this.onWebViewCreated,
    this.onConsoleMessage,
    this.onLoadStart,
    this.onExternalCallback,
    this.closeAfterExternalCallback = false,
    this.preferSystemUserAgent = false,
    this.recoverTechnicalError = false,
    this.shouldOverrideUrlLoading,
  });

  @override
  State<WebAppScreen> createState() => _WebAppScreenState();
}

class _WebAppScreenState extends State<WebAppScreen> {
  InAppWebViewController? _controller;
  WebAppBridge? _bridge;
  WebAppLaunch? _launch;
  WebAppOriginPolicy? _origins;
  WebViewEnvironment? _environment;
  String? _loadError;
  String _userAgent = '';
  double _progress = 0;
  bool _recovering = false;
  Size _viewport = Size.zero;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _bridge?.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loadError = null;
      _launch = null;
      _bridge?.dispose();
      _bridge = null;
    });
    try {
      // Тот же UA, что уходит в sessionInit (из handshake-устройства ядра),
      // чтобы веб-аппы видели нативный клиент; фолбэк — браузерный UA спуфа.
      // Для веб-аппов с внешней авторизацией (Госуслуги/ЕСИА) клиентский UA
      // ядра отбраковывается антифродом — там нужен UA настоящего WebView.
      _userAgent = '';
      if (widget.preferSystemUserAgent) {
        try {
          _userAgent = await InAppWebViewController.getDefaultUserAgent();
        } catch (_) {}
      }
      if (_userAgent.isEmpty) {
        _userAgent =
            api.session?.userAgent() ??
            await SpoofingService.getWebViewUserAgent() ??
            '';
      }
      _environment = await WebViewSandbox.environment();
      final launch = await widget.loader();
      if (!mounted) return;
      final origins = WebAppOriginPolicy(Uri.parse(launch.url));
      setState(() {
        _launch = launch;
        _origins = origins;
        _bridge = _createBridge(launch.botId, origins);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadError = e.toString());
    }
  }

  WebAppBridge _createBridge(int botId, WebAppOriginPolicy origins) =>
      WebAppBridge(
        botId: botId,
        entryPoint: widget.entryPoint,
        privateChannel: widget.privateChannel,
        mobileIdVerifier: widget.mobileIdVerifier,
        origins: origins,
        appTitle: widget.title,
        contextResolver: () => mounted ? context : null,
        viewportResolver: () => _viewport,
        onClose: _closeFromWebApp,
      );

  Future<void> _closeFromWebApp() async {
    if (_recovering) return;
    if (widget.recoverTechnicalError && _controller != null) {
      _recovering = true;
      try {
        final technicalError = await _controller!
            .evaluateJavascript(
              source:
                  "document.body && document.body.innerText.includes('Техническая заминка')",
            )
            .timeout(const Duration(seconds: 2));
        if (!mounted) return;
        if (technicalError == true) {
          await _load();
          return;
        }
      } catch (_) {
      } finally {
        _recovering = false;
      }
    }
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  Future<void> _closeByUser() async {
    final bridge = _bridge;
    if (bridge != null && bridge.needsCloseConfirmation) {
      final l10n = AppLocalizations.of(context)!;
      final confirmed = await showConfirmDialog(
        context,
        title: widget.title,
        message: l10n.webAppScreenCloseConfirm,
        confirmLabel: l10n.videoViewerClose,
      );
      if (!confirmed || !mounted) return;
    }
    Navigator.of(context).pop();
  }

  Future<bool> _handleBack() async {
    final bridge = _bridge;
    if (bridge != null && bridge.handlesBackButton) {
      bridge.notifyBackPressed();
      return false;
    }
    final controller = _controller;
    if (controller != null && await controller.canGoBack()) {
      await controller.goBack();
      return false;
    }
    if (bridge != null && bridge.needsCloseConfirmation && mounted) {
      final l10n = AppLocalizations.of(context)!;
      return showConfirmDialog(
        context,
        title: widget.title,
        message: l10n.webAppScreenCloseConfirm,
        confirmLabel: l10n.videoViewerClose,
      );
    }
    return true;
  }

  Future<NavigationActionPolicy?> _handleNavigation(
    InAppWebViewController controller,
    NavigationAction action,
  ) async {
    final uri = action.request.url;
    final callback = widget.onExternalCallback;
    if (callback != null && uri?.queryParameters['externalCallback'] == '1') {
      try {
        final launch = await callback(uri.toString());
        if (!mounted) return NavigationActionPolicy.CANCEL;
        if (widget.closeAfterExternalCallback) {
          Navigator.of(context).pop(launch);
          return NavigationActionPolicy.CANCEL;
        }
        _origins?.trust(Uri.parse(launch.url));
        setState(() {
          _launch = launch;
          _loadError = null;
        });
        await controller.loadUrl(
          urlRequest: URLRequest(url: WebUri(launch.url)),
        );
      } catch (e) {
        if (mounted) setState(() => _loadError = e.toString());
      }
      return NavigationActionPolicy.CANCEL;
    }
    final handler = widget.shouldOverrideUrlLoading;
    if (handler != null) return handler(controller, action, _launch?.url);
    if (uri == null) return NavigationActionPolicy.ALLOW;
    return _guardNavigation(uri, action.isForMainFrame);
  }

  Future<NavigationActionPolicy> _guardNavigation(
    Uri uri,
    bool mainFrame,
  ) async {
    final scheme = uri.scheme.toLowerCase();
    if (scheme == 'javascript') return NavigationActionPolicy.ALLOW;
    if (scheme == 'http' || scheme == 'https') {
      return _guardWebNavigation(uri, mainFrame);
    }
    if (!leavesWebView(scheme)) {
      final blocked = mainFrame && scheme == 'data';
      return blocked
          ? NavigationActionPolicy.CANCEL
          : NavigationActionPolicy.ALLOW;
    }
    if (mounted) await openExternalUrl(context, uri.toString());
    return NavigationActionPolicy.CANCEL;
  }

  Future<NavigationActionPolicy> _guardWebNavigation(
    Uri uri,
    bool mainFrame,
  ) async {
    final origins = _origins;
    if (!mainFrame || origins == null || origins.mayNavigate(uri)) {
      return NavigationActionPolicy.ALLOW;
    }
    if (!(_bridge?.userHasInteracted ?? false)) {
      origins.trust(uri);
      return NavigationActionPolicy.ALLOW;
    }
    if (!mounted) return NavigationActionPolicy.CANCEL;
    final choice = await askExternalNavigation(
      context,
      target: uri,
      allowInPlace: true,
    );
    switch (choice) {
      case ExternalNavigationChoice.here:
        origins.allowVisit(uri);
        return NavigationActionPolicy.ALLOW;
      case ExternalNavigationChoice.browser:
        if (mounted) await openExternalUrl(context, uri.toString());
        return NavigationActionPolicy.CANCEL;
      case ExternalNavigationChoice.cancel:
        return NavigationActionPolicy.CANCEL;
    }
  }

  Future<void> _openNewWindow(Uri? target) async {
    if (target == null || !mounted) return;
    final url = target.toString();
    if (isWebUri(target) && !(_origins?.trusts(target) ?? false)) {
      final choice = await askExternalNavigation(context, target: target);
      if (choice != ExternalNavigationChoice.browser || !mounted) return;
    }
    await openExternalUrl(context, url);
  }

  Future<void> _handleWebDownload(DownloadStartRequest request) async {
    final uri = request.url;
    if (!isWebUri(uri) || !mounted) return;
    final suggested = repairFileName(request.suggestedFilename ?? '');
    final name = sanitizeFileName(
      suggested,
      fallback: sanitizeFileName(p.basename(uri.path), fallback: 'download'),
    );
    final choice = await askMiniAppDownload(
      context,
      appTitle: widget.title,
      fileName: name,
      host: uri.host,
    );
    if (choice == MiniAppDownloadChoice.cancel || !mounted) return;
    final saved = await saveMiniAppDownload(
      choice: choice,
      url: uri.toString(),
      fileName: name,
      botId: _launch?.botId ?? 0,
      sourceName: widget.title,
      dialogTitle: AppLocalizations.of(context)!.photoViewerSaveAs,
    );
    reportMiniAppDownload(mounted ? context : null, choice, saved);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final navigator = Navigator.of(context);
        if (await _handleBack()) navigator.pop();
      },
      child: Scaffold(
        backgroundColor: cs.surface,
        floatingActionButtonLocation: FloatingActionButtonLocation.startFloat,
        floatingActionButton: const ConnectionSpinner(),
        appBar: AppBar(
          backgroundColor: cs.surface,
          surfaceTintColor: Colors.transparent,
          title: Text(widget.title),
          leading: IconButton(
            icon: const Icon(Symbols.close),
            onPressed: _closeByUser,
          ),
          actions: [
            IconButton(icon: const Icon(Symbols.refresh), onPressed: _load),
          ],
          bottom: _progress > 0 && _progress < 1
              ? PreferredSize(
                  preferredSize: const Size.fromHeight(2),
                  child: LinearProgressIndicator(
                    value: _progress,
                    minHeight: 2,
                    backgroundColor: Colors.transparent,
                  ),
                )
              : null,
        ),
        body: _buildBody(cs),
      ),
    );
  }

  Widget _buildBody(ColorScheme cs) {
    if (_loadError != null) {
      return ErrorView(message: _loadError!, onRetry: _load);
    }
    final launch = _launch;
    final bridge = _bridge;
    if (launch == null || bridge == null) {
      return const Center(child: SmallSpinner(size: 36));
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        _viewport = Size(constraints.maxWidth, constraints.maxHeight);
        return Listener(
          onPointerDown: (_) => bridge.registerGesture(),
          child: _buildWebView(launch, bridge),
        );
      },
    );
  }

  Widget _buildWebView(WebAppLaunch launch, WebAppBridge bridge) {
    return InAppWebView(
      key: ObjectKey(bridge),
      webViewEnvironment: _environment,
      initialUrlRequest: URLRequest(url: WebUri(launch.url)),
      initialUserScripts: UnmodifiableListView<UserScript>([
        bridge.userScript,
        ...?widget.extraUserScripts,
      ]),
      initialSettings: InAppWebViewSettings(
        javaScriptEnabled: true,
        domStorageEnabled: true,
        thirdPartyCookiesEnabled: true,
        supportZoom: false,
        transparentBackground: true,
        mediaPlaybackRequiresUserGesture: false,
        allowsInlineMediaPlayback: true,
        sharedCookiesEnabled: true,
        allowsBackForwardNavigationGestures: true,
        useHybridComposition: true,
        supportMultipleWindows: true,
        allowFileAccess: false,
        allowFileAccessFromFileURLs: false,
        allowUniversalAccessFromFileURLs: false,
        allowContentAccess: false,
        isInspectable: kDebugMode,
        useShouldOverrideUrlLoading: true,
        userAgent: _userAgent,
      ),
      onWebViewCreated: (controller) {
        _controller = controller;
        bridge.attach(controller);
        widget.onWebViewCreated?.call(controller);
      },
      onPermissionRequest: (controller, request) =>
          askWebViewPermission(context, request),
      onCreateWindow: (controller, action) async {
        await _openNewWindow(action.request.url);
        return false;
      },
      onDownloadStartRequest: (controller, request) =>
          _handleWebDownload(request),
      onConsoleMessage: widget.onConsoleMessage,
      onLoadStart: widget.onLoadStart,
      shouldOverrideUrlLoading: _handleNavigation,
      onProgressChanged: (controller, progress) {
        if (!mounted) return;
        setState(() => _progress = progress / 100);
      },
      onReceivedError: (controller, request, error) {
        final host = request.url.host;
        logger.w(
          'WebView ${widget.title}: ${error.type} ${error.description} '
          '($host${request.isForMainFrame ?? false ? ', главный фрейм' : ''})',
        );
        if (!mounted) return;
        if (request.isForMainFrame ?? false) {
          setState(() => _loadError = error.description);
        }
      },
    );
  }
}
