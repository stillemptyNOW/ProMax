import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';

import 'package:device_info_plus/device_info_plus.dart';

import '../hub/diagnostics.dart';
import '../protocol/opcode_map.dart';
import '../storage/token_storage.dart';
import '../utils/ids.dart';
import '../utils/logger.dart';
import 'max_web_socket.dart';

// #***! подписка браузера на пуши
class WebPushSubscription {
  final String endpoint;
  final String publicKey;
  final String authKey;

  const WebPushSubscription({
    required this.endpoint,
    required this.publicKey,
    required this.authKey,
  });

  static WebPushSubscription? fromAppleLink(Uri uri) {
    final parameters = uri.queryParametersAll;
    if (parameters.length != 3 ||
        parameters.values.any((values) => values.length != 1)) {
      return null;
    }
    final endpoint = uri.queryParameters['endpoint'];
    final publicKey = uri.queryParameters['p256dh'];
    final authKey = uri.queryParameters['auth'];
    if (endpoint == null ||
        publicKey == null ||
        authKey == null ||
        endpoint.length > 2048 ||
        publicKey.length > 100 ||
        authKey.length > 32) {
      return null;
    }
    final target = Uri.tryParse(endpoint);
    if (target == null ||
        target.scheme != 'https' ||
        target.port != 443 ||
        !target.host.endsWith('.push.apple.com') ||
        target.userInfo.isNotEmpty ||
        target.hasFragment ||
        target.path.length < 2) {
      return null;
    }
    try {
      final point = base64Url.decode(base64Url.normalize(publicKey));
      final secret = base64Url.decode(base64Url.normalize(authKey));
      if (point.length != 65 || point.first != 4 || secret.length != 16) {
        return null;
      }
    } on FormatException {
      return null;
    }
    return WebPushSubscription(
      endpoint: endpoint,
      publicKey: publicKey,
      authKey: authKey,
    );
  }
}

// #***! что сейчас привязано
class WebPushLinkInfo {
  final String endpoint;
  final DateTime? linkedAt;
  final String deviceId;

  const WebPushLinkInfo({
    required this.endpoint,
    required this.linkedAt,
    required this.deviceId,
  });

  String get shortEndpoint {
    final token = endpoint.split('/').last;
    if (token.length <= 24) return token;
    return '${token.substring(0, 12)}…${token.substring(token.length - 8)}';
  }

  String get host => Uri.tryParse(endpoint)?.host ?? endpoint;
}

// #***! QR трек авторизации
class WebPushQrTrack {
  final String trackId;
  final String qrLink;
  final Duration pollInterval;
  final Duration lifetime;

  const WebPushQrTrack({
    required this.trackId,
    required this.qrLink,
    required this.pollInterval,
    required this.lifetime,
  });
}

// #***! аккаунт с 2FA, нужен пароль
class WebPushPasswordChallenge {
  final String trackId;
  final String? hint;

  const WebPushPasswordChallenge({required this.trackId, this.hint});
}

// #***! шаг авторизации, токен или запрос пароля
class WebPushAuthStep {
  final String? loginToken;
  final WebPushPasswordChallenge? passwordChallenge;

  const WebPushAuthStep({this.loginToken, this.passwordChallenge});

  bool get needsPassword => loginToken == null && passwordChallenge != null;
}

// #***! привязка вебпушей, вход по QR через веб API
class WebPushService {
  WebPushService._();

  static final WebPushService instance = WebPushService._();

  static const int _opcodeQrCreate = 288;
  static const int _opcodeQrStatus = 289;
  static const int _opcodeQrFinish = 291;

  static const String _tokenKey = 'webpush_login_token';
  static const String _deviceIdKey = 'webpush_device_id';
  static const String _endpointKey = 'webpush_endpoint';
  static const String _linkedAtKey = 'webpush_linked_at';

  // #***! представляемся конкретной версией веб клиента, от неё зависят опкоды
  static const String _appVersion = '26.8.8';
  static const Duration _defaultPoll = Duration(seconds: 5);
  static const Duration _defaultLifetime = Duration(minutes: 2);

  MaxWebSocketSession? _authSocket;
  int? _authAccountId;

  // #***! changes на изменение привязки, экран настроек подписан
  final ValueNotifier<int> changes = ValueNotifier<int>(0);

  void _notifyChanged() => changes.value++;

  // #***! состояние привязки в защищённом хранилище
  Future<bool> isAuthorized() async {
    final accountId = await TokenStorage.getActiveAccountId();
    if (accountId == null) return false;
    return (await TokenStorage.readSecure(
          '${_tokenKey}_$accountId',
        ))?.isNotEmpty ??
        false;
  }

  Future<WebPushLinkInfo?> linkInfo() async {
    final accountId = await TokenStorage.getActiveAccountId();
    if (accountId == null) return null;
    final endpoint = await TokenStorage.readSecure(
      '${_endpointKey}_$accountId',
    );
    if (endpoint == null || endpoint.isEmpty) return null;

    final stamp = await TokenStorage.readSecure('${_linkedAtKey}_$accountId');
    return WebPushLinkInfo(
      endpoint: endpoint,
      linkedAt: stamp == null ? null : DateTime.tryParse(stamp),
      deviceId: await _deviceId(accountId),
    );
  }

  Future<String> _deviceId(int accountId) async {
    final key = '${_deviceIdKey}_$accountId';
    final saved = await TokenStorage.readSecure(key);
    if (saved != null && saved.isNotEmpty) return saved;

    final generated = uuidV4();
    await TokenStorage.writeSecure(key, generated);
    return generated;
  }

  Future<MaxWebDevice> _device(int accountId) async {
    return MaxWebDevice(
      deviceId: await _deviceId(accountId),
      appVersion: _appVersion,
      userAgent: await _safariUserAgent(),
      screen: _browserScreen(),
    );
  }

  // #***! создаём QR трек, юзер подтверждает в приложении
  Future<WebPushQrTrack> startQrAuth() async {
    final accountId = await _activeAccount();
    await cancelAuth();

    final socket = MaxWebSocketSession(device: await _device(accountId));
    _authSocket = socket;
    _authAccountId = accountId;
    await socket.connect();

    final payload = _asMap(
      await socket.request(_opcodeQrCreate, null),
      'создание QR',
    );

    final trackId = payload['trackId'];
    final qrLink = payload['qrLink'];
    if (trackId is! String || qrLink is! String) {
      throw const MaxWebException('сервер не вернул ссылку для входа');
    }

    return WebPushQrTrack(
      trackId: trackId,
      qrLink: qrLink,
      pollInterval: _durationFrom(payload['pollingInterval'], _defaultPoll),
      lifetime: _durationFrom(payload['ttl'], _defaultLifetime),
    );
  }

  // #***! опрос до подтверждения или истечения
  Future<WebPushAuthStep> awaitApproval(WebPushQrTrack track) async {
    final socket = await _requireSocket();
    final deadline = DateTime.now().add(track.lifetime);

    while (DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(track.pollInterval);

      final payload = _asMap(
        await socket.request(_opcodeQrStatus, <String, Object?>{
          'trackId': track.trackId,
        }),
        'опрос входа',
      );

      final status = payload['status'];
      final available = status is Map ? status['loginAvailable'] : null;
      if (available != true) continue;

      final finish = _asMap(
        await socket.request(_opcodeQrFinish, <String, Object?>{
          'trackId': track.trackId,
        }),
        'завершение входа',
      );
      return _stepFrom(finish);
    }

    throw const MaxWebException('время подтверждения истекло');
  }

  // #***! второй шаг при 2FA
  Future<WebPushAuthStep> submitPassword(
    String trackId,
    String password,
  ) async {
    final socket = await _requireSocket();
    final payload = _asMap(
      await socket.request(Opcode.authLoginCheckPassword, <String, Object?>{
        'trackId': trackId,
        'password': password,
      }),
      'проверка пароля',
    );
    return _stepFrom(payload);
  }

  Future<void> finishAuth(String loginToken) async {
    final accountId = _authAccountId;
    await _requireSocket();
    if (accountId == null || accountId != _authAccountId) {
      throw const MaxWebException('сессия входа потеряна, начните заново');
    }
    await TokenStorage.writeSecure('${_tokenKey}_$accountId', loginToken);
    await cancelAuth();
    _notifyChanged();
    logger.i('WebPush: WEB-сессия авторизована по QR');
  }

  Future<void> cancelAuth() async {
    final socket = _authSocket;
    _authSocket = null;
    _authAccountId = null;
    await socket?.close();
  }

  // #***! регистрация подписки на сервере
  Future<void> registerSubscription(
    WebPushSubscription subscription, {
    int? expectedAccountId,
  }) async {
    final accountId = await _activeAccount();
    if (expectedAccountId != null && accountId != expectedAccountId) {
      throw const MaxWebException(
        'Аккаунт изменился. Откройте ссылку привязки заново.',
      );
    }
    final token = await TokenStorage.readSecure('${_tokenKey}_$accountId');
    if (token == null || token.isEmpty) {
      throw const MaxWebException(
        'сначала подключите уведомления в настройках',
      );
    }

    final socket = MaxWebSocketSession(device: await _device(accountId));
    final watch = Stopwatch()..start();
    var outcome = DiagnosticOutcome.failed;
    try {
      await socket.connect();
      try {
        await _login(socket, token);
      } on MaxWebException catch (e) {
        if (e.code != 'FAIL_LOGIN_TOKEN') rethrow;
        final stored = await TokenStorage.readSecure('${_tokenKey}_$accountId');
        if (stored == token) await _clearAuthorization(accountId);
        throw const MaxWebException(
          'Сессия уведомлений истекла. Подключите её заново в настройках.',
        );
      }
      await socket.request(Opcode.config, <String, Object?>{
        'subscribe': true,
        'pushToken': subscription.endpoint,
        'secretKey': subscription.authKey,
        'publicKey': subscription.publicKey,
      });
      await TokenStorage.writeSecure(
        '${_endpointKey}_$accountId',
        subscription.endpoint,
      );
      await TokenStorage.writeSecure(
        '${_linkedAtKey}_$accountId',
        DateTime.now().toIso8601String(),
      );
      _notifyChanged();
      logger.i('WebPush: подписка зарегистрирована');
      outcome = DiagnosticOutcome.success;
      Diagnostics.recordFeature(DiagnosticStage.featureWebPush);
    } on TimeoutException {
      outcome = DiagnosticOutcome.timeout;
      rethrow;
    } finally {
      Diagnostics.recordOperation(
        DiagnosticStage.webPushLink,
        outcome,
        elapsed: watch.elapsed,
      );
      await socket.close();
    }
  }

  // #***! отвязка, гасим сессию и чистим локальное
  Future<void> signOut() async {
    final accountId = await _activeAccount();
    await cancelAuth();

    final token = await TokenStorage.readSecure('${_tokenKey}_$accountId');
    final endpoint = await TokenStorage.readSecure(
      '${_endpointKey}_$accountId',
    );
    if (token != null && token.isNotEmpty) {
      try {
        await _terminateWebSession(accountId, token, endpoint);
      } catch (e) {
        logger.w('WebPush: веб-сессию завершить не удалось ($e)');
      }
    }

    await _clearAuthorization(accountId);
  }

  Future<void> _terminateWebSession(
    int accountId,
    String token,
    String? endpoint,
  ) async {
    final socket = MaxWebSocketSession(device: await _device(accountId));
    try {
      await socket.connect();
      await _login(socket, token);

      if (endpoint != null && endpoint.isNotEmpty) {
        try {
          await socket.request(Opcode.config, <String, Object?>{
            'subscribe': false,
            'pushToken': endpoint,
            'secretKey': '',
            'publicKey': '',
          });
        } catch (e) {
          logger.w('WebPush: подписку снять не удалось ($e)');
        }
      }

      await socket.request(Opcode.logout, <String, Object?>{});
      logger.i('WebPush: веб-сессия завершена');
    } finally {
      await socket.close();
    }
  }

  Future<Object?> _login(MaxWebSocketSession socket, String token) =>
      socket.request(Opcode.login, <String, Object?>{
        'token': token,
        'chatsCount': 0,
        'interactive': false,
        'chatsSync': 0,
        'contactsSync': 0,
        'presenceSync': -1,
        'draftsSync': 0,
      });

  Future<void> _clearAuthorization(int accountId) async {
    await TokenStorage.deleteSecure('${_tokenKey}_$accountId');
    await TokenStorage.deleteSecure('${_endpointKey}_$accountId');
    await TokenStorage.deleteSecure('${_linkedAtKey}_$accountId');
    _notifyChanged();
  }

  Future<int> _activeAccount() async {
    final accountId = await TokenStorage.getActiveAccountId();
    if (accountId == null) {
      throw const MaxWebException('Сначала войдите в аккаунт MAX');
    }
    return accountId;
  }

  Future<MaxWebSocketSession> _requireSocket() async {
    final accountId = await _activeAccount();
    final socket = _authSocket;
    if (socket == null || _authAccountId != accountId) {
      throw const MaxWebException('сессия входа потеряна, начните заново');
    }
    return socket;
  }

  WebPushAuthStep _stepFrom(Map<Object?, Object?> payload) {
    final attrs = payload['tokenAttrs'];
    if (attrs is Map) {
      final login = attrs['LOGIN'];
      if (login is Map) {
        final token = login['token'];
        if (token is String && token.isNotEmpty) {
          return WebPushAuthStep(loginToken: token);
        }
      }
    }

    final challenge = payload['passwordChallenge'];
    if (challenge is Map) {
      final trackId = challenge['trackId'];
      if (trackId is String && trackId.isNotEmpty) {
        final hint = challenge['hint'];
        return WebPushAuthStep(
          passwordChallenge: WebPushPasswordChallenge(
            trackId: trackId,
            hint: hint is String && hint.isNotEmpty ? hint : null,
          ),
        );
      }
    }

    throw const MaxWebException('сервер не вернул ни токен, ни запрос пароля');
  }

  Map<Object?, Object?> _asMap(Object? payload, String step) {
    if (payload is Map<Object?, Object?>) return payload;
    throw MaxWebException('$step: неожиданный ответ сервера');
  }

  Duration _durationFrom(Object? value, Duration fallback) {
    if (value is int && value > 0) return Duration(milliseconds: value);
    return fallback;
  }

  // #***! юзерагент сафари, сервер принимает вебпуши только от известных браузеров
  Future<String> _safariUserAgent() async {
    var release = '18_5';
    var version = '18.5';

    if (Platform.isIOS) {
      try {
        final info = await DeviceInfoPlugin().iosInfo;
        final systemVersion = info.systemVersion;
        if (systemVersion.isNotEmpty) {
          version = systemVersion;
          release = systemVersion.replaceAll('.', '_');
        }
      } catch (e) {
        logger.w('WebPush: не удалось прочитать версию iOS ($e)');
      }
    }

    return 'Mozilla/5.0 (iPhone; CPU iPhone OS $release like Mac OS X) '
        'AppleWebKit/605.1.15 (KHTML, like Gecko) Version/$version '
        'Mobile/15E148 Safari/604.1';
  }

  String _browserScreen() {
    final view = PlatformDispatcher.instance.views.first;
    final ratio = view.devicePixelRatio;
    final height = (view.physicalSize.height / ratio).round();
    final width = (view.physicalSize.width / ratio).round();
    return '${height}x$width ${ratio.toStringAsFixed(1)}x';
  }
}
