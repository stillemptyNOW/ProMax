import '../api.dart';
import '../../core/hub/diagnostics.dart';
import '../../core/privacy/host_policy.dart';
import '../../core/protocol/opcode_map.dart';
import '../../core/storage/app_database.dart';
import '../../core/storage/token_storage.dart';
import '../../core/utils/logger.dart';
import 'account/account_models.dart';

// #***! встроенные мини аппы со своими кнопками
abstract class EntryBannerApps {
  static const String sferumKey = 'entry_banner_app_sferum';
  static const String digitalIdKey = 'entry_banner_app_digital_id';

  static const Map<String, List<String>> iconMatchers = {
    sferumKey: ['sferum'],
    digitalIdKey: ['digital'],
  };

  static const Map<String, List<String>> titleMatchers = {
    sferumKey: ['ферум'],
    digitalIdKey: ['цифровой'],
  };

  static const Map<String, int> knownAppIds = {
    sferumKey: 2340831,
    digitalIdKey: 8250447,
  };

  static Map<String, int> appIdsFrom(Map serverConfig) {
    final banners = serverConfig['settings-entry-banners'];
    if (banners is! List) return const {};
    final resolved = <String, int>{};
    const passes = [('icon', iconMatchers), ('title', titleMatchers)];
    for (final (field, matchers) in passes) {
      for (final banner in banners) {
        final items = (banner is Map) ? banner['items'] : null;
        if (items is! List) continue;
        for (final item in items) {
          if (item is! Map) continue;
          final appId = item['appid'];
          if (appId is! int) continue;
          final value = item[field]?.toString().toLowerCase() ?? '';
          if (value.isEmpty) continue;
          for (final entry in matchers.entries) {
            if (resolved.containsKey(entry.key)) continue;
            if (entry.value.any(value.contains)) resolved[entry.key] = appId;
          }
        }
      }
    }
    return resolved;
  }
}

// #***! сервер зовёт эту опцию по разному
const Set<String> kMiniAppOptions = {'HAS_WEBAPP', 'HAS_WEB_APP', 'WEBAPP'};

bool hasMiniAppOption(Set<String>? options) =>
    options != null && options.any(kMiniAppOptions.contains);

// #***! адрес запуска мини аппы плюс id запроса
class WebAppLaunch {
  final String url;
  final String? queryId;
  final int botId;

  const WebAppLaunch({required this.url, required this.botId, this.queryId});
}

// #***! номер который разрешили дать боту, с подписью сервера
class WebAppPhone {
  final String phone;
  final String hash;
  final int authDate;

  const WebAppPhone({
    required this.phone,
    required this.hash,
    required this.authDate,
  });
}

// #***! результат колбэка госуслуг
class ExternalCallbackResult {
  final int botId;
  final String? startParam;

  const ExternalCallbackResult({required this.botId, this.startParam});

  static ExternalCallbackResult? fromPayload(dynamic payload) {
    final data = _findResponseMap(payload);
    if (data == null) return null;
    final botId = _asInt(data['botId'] ?? data['bot_id']);
    if (botId == null) return null;
    final startParam = data['startParam'] ?? data['start_param'];
    return ExternalCallbackResult(
      botId: botId,
      startParam: startParam?.toString(),
    );
  }

  // #***! нужное бывает завёрнуто в data result response, ищем рекурсивно
  static Map? _findResponseMap(dynamic value) {
    if (value is! Map) return null;
    if (value.containsKey('botId') || value.containsKey('bot_id')) return value;
    for (final key in const ['data', 'result', 'response']) {
      final nested = _findResponseMap(value[key]);
      if (nested != null) return nested;
    }
    return null;
  }
}

int? _asInt(dynamic value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '');
}

class DigitalIdCallback {
  DigitalIdCallback._(this._module, this.uri)
    : _account = TokenStorage.getActiveAccountId();

  final WebAppModule _module;
  final Uri uri;
  final Future<int?> _account;
  ExternalCallbackResult? _exchange;
  Future<WebAppLaunch>? _running;
  bool _launched = false;
  bool get hasLaunched => _launched;

  Future<WebAppLaunch> launch() => _running ??= _launch().whenComplete(() {
    _running = null;
  });

  Future<void> _checkAccount() async {
    final account = await _account;
    if (account == null || await TokenStorage.getActiveAccountId() != account) {
      throw const WebAppUnavailable('Аккаунт Цифрового ID изменился');
    }
  }

  Future<WebAppLaunch> _launch() async {
    await _checkAccount();
    final exchange = _exchange ??= await _module._exchangeDigitalIdCallback(
      uri,
    );
    await _checkAccount();
    final watch = Stopwatch()..start();
    var outcome = DiagnosticOutcome.failed;
    try {
      final launch = await _module.fetchLaunch(
        exchange.botId,
        startParam: exchange.startParam,
      );
      await _checkAccount();
      if (!_launched) {
        _launched = true;
        Diagnostics.recordFeature(DiagnosticStage.featureDigitalId);
      }
      outcome = DiagnosticOutcome.success;
      return launch;
    } finally {
      Diagnostics.recordOperation(
        DiagnosticStage.digitalIdExchange,
        outcome,
        elapsed: watch.elapsed,
      );
    }
  }
}

// #***! запуск мини аппок ботов
class WebAppModule {
  final Api _api;

  WebAppModule(this._api);

  // #***! тот же device_id что в хэндшейке, к нему привязан цифровой ID
  /// device_id сессии (опкод 6 sessionInit, с учётом спуфинга) — тот же id,
  /// к которому сервер привязывает Цифровой ID.
  String? get sessionDeviceId => _api.deviceId;

  // #***! сервер даёт подписанный url для вебвью
  Future<WebAppLaunch> fetchLaunch(
    int botId, {
    String? startParam,
    int? chatId,
  }) async {
    if (_api.state != SessionState.online) {
      throw const WebAppUnavailable('Нет соединения с сервером');
    }
    final normalizedStartParam =
        (startParam != null && startParam.trim().isNotEmpty)
        ? startParam
        : null;
    final packet = await _api.sendRequest(Opcode.webAppInitData, {
      'botId': botId,
      'startParam': ?normalizedStartParam,
      'chatId': ?chatId,
    });
    if (!packet.isOk) {
      throw const WebAppUnavailable('Не удалось открыть мини-приложение');
    }
    final data = packet.payload;
    final url = (data is Map) ? data['url'] as String? : null;
    if (url == null || url.isEmpty) {
      throw const WebAppUnavailable('Сервер не вернул адрес приложения');
    }
    final queryId = (data is Map) ? data['query_id']?.toString() : null;
    return WebAppLaunch(url: url, botId: botId, queryId: queryId);
  }

  // #***! номер боту только по явному действию юзера
  Future<WebAppPhone> requestPhone(int botId) async {
    if (_api.state != SessionState.online) {
      throw const WebAppUnavailable('Нет соединения с сервером');
    }
    final packet = await _api.sendRequest(Opcode.phoneWebappShare, {
      'botId': botId,
    });
    final data = packet.payload;
    if (!packet.isOk || data is! Map) {
      throw const WebAppUnavailable('Не удалось передать номер телефона');
    }
    final phone = data['phone']?.toString();
    final hash = data['hash']?.toString();
    final authDate = _asInt(data['authDate'] ?? data['auth_date']);
    if (phone == null ||
        phone.isEmpty ||
        hash == null ||
        hash.isEmpty ||
        authDate == null ||
        authDate == 0) {
      throw const WebAppUnavailable('Сервер не вернул номер телефона');
    }
    return WebAppPhone(phone: phone, hash: hash, authDate: authDate);
  }

  // #***! id ботов сферума и цифрового ID приходят в конфиге
  Future<WebAppLaunch> fetchSferum() async {
    final botId = await _resolveEntryApp(EntryBannerApps.sferumKey);
    if (botId == null) {
      throw const WebAppUnavailable(
        'Сферум сейчас недоступен. Переподключитесь и попробуйте снова.',
      );
    }
    return fetchLaunch(botId);
  }

  Future<WebAppLaunch> fetchDigitalId() async {
    final watch = Stopwatch()..start();
    var outcome = DiagnosticOutcome.failed;
    try {
      final botId = await _resolveEntryApp(EntryBannerApps.digitalIdKey);
      if (botId == null) {
        outcome = DiagnosticOutcome.unavailable;
        throw const WebAppUnavailable(
          'Цифровой ID сейчас недоступен. Переподключитесь и попробуйте снова.',
        );
      }
      final launch = await fetchLaunch(botId);
      outcome = DiagnosticOutcome.success;
      return launch;
    } finally {
      Diagnostics.recordOperation(
        DiagnosticStage.digitalIdLaunch,
        outcome,
        elapsed: watch.elapsed,
      );
    }
  }

  DigitalIdCallback digitalIdCallback(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null || !HostPolicy.isDigitalIdCallback(uri)) {
      throw const WebAppUnavailable('Некорректный callback Цифрового ID');
    }
    return DigitalIdCallback._(this, uri);
  }

  Future<ExternalCallbackResult> _exchangeDigitalIdCallback(Uri uri) async {
    if (_api.state != SessionState.online) {
      throw const WebAppUnavailable('Нет соединения с сервером');
    }
    final watch = Stopwatch()..start();
    var outcome = DiagnosticOutcome.failed;
    try {
      final packet = await _api.sendRequest(Opcode.externalCallback, {
        'url': uri.toString(),
      });
      final result = packet.isOk
          ? ExternalCallbackResult.fromPayload(packet.payload)
          : null;
      if (result == null) {
        throw const WebAppUnavailable(
          'Сервер не вернул данные для завершения Цифрового ID',
        );
      }
      outcome = DiagnosticOutcome.success;
      return result;
    } finally {
      Diagnostics.recordOperation(
        DiagnosticStage.digitalIdCallback,
        outcome,
        elapsed: watch.elapsed,
      );
    }
  }

  // #***! id мини аппы лежит в sync_state после login
  Future<int?> _resolveEntryApp(String key) async {
    final accountId = await TokenStorage.getActiveAccountId();
    if (accountId == null) return null;
    final raw = await AppDatabase.getSyncValue(accountId, key);
    final stored = int.tryParse(raw ?? '');
    if (stored != null) return stored;
    await LoginSyncParams.forgetServerConfig(accountId);
    final known = EntryBannerApps.knownAppIds[key];
    logger.w('Мини-аппа $key: id нет в конфиге, берём известный $known');
    return known;
  }
}

class WebAppUnavailable implements Exception {
  final String message;

  const WebAppUnavailable(this.message);

  @override
  String toString() => message;
}
