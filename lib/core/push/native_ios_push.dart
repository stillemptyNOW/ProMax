import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import '../storage/token_storage.dart';
import '../webpush/web_push_service.dart';

class NativeIosPush {
  static const _channel = MethodChannel('ru.komet.app/notifications');
  static const _urlKey = 'promax_push_relay_url';
  static const _secretKey = 'promax_push_relay_secret';

  static Future<(String, String)> config() async => (
    await TokenStorage.readSecure(_urlKey) ?? '',
    await TokenStorage.readSecure(_secretKey) ?? '',
  );

  static Future<void> testLocal() =>
      _channel.invokeMethod('testLocalNotification');

  static Future<Map<String, dynamic>> capabilities() async =>
      await _channel.invokeMapMethod<String, dynamic>('pushCapabilities') ?? {};

  static Future<bool> testRegistration() async {
    final token = await _channel.invokeMethod<String>('registerNativePush');
    return token != null && token.isNotEmpty;
  }

  static Future<void> connect(String baseUrl, String secret) async {
    final base = Uri.tryParse(baseUrl.trim());
    if (base == null ||
        base.scheme != 'https' ||
        base.host.isEmpty ||
        base.userInfo.isNotEmpty ||
        base.hasQuery ||
        base.hasFragment) {
      throw const FormatException('Нужен HTTPS-адрес сервера push');
    }
    if (secret.length < 32) {
      throw const FormatException(
        'Ключ сервера должен содержать не менее 32 символов',
      );
    }
    if (!await WebPushService.instance.isAuthorized()) {
      throw StateError('Сначала подключите WEB-сессию MAX для уведомлений');
    }
    final token = await _channel.invokeMethod<String>('registerNativePush');
    if (token == null || token.isEmpty) {
      throw StateError('APNs не выдал токен. Проверьте сертификат в eSign.');
    }
    final profile = await capabilities();
    final environment = profile['apsEnvironment'] == 'development'
        ? 'sandbox'
        : 'production';
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15);
    try {
      final endpoint = base.replace(
        path: '${base.path.replaceAll(RegExp(r'/+$'), '')}/v1/subscriptions',
      );
      final request = await client.postUrl(endpoint);
      request.followRedirects = false;
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $secret');
      request.headers.contentType = ContentType.json;
      request.write(
        jsonEncode({'apnsToken': token, 'environment': environment}),
      );
      final response = await request.close().timeout(
        const Duration(seconds: 20),
      );
      if (response.statusCode != 200) {
        throw HttpException('Сервер push: ${response.statusCode}');
      }
      final text = await response
          .transform(utf8.decoder)
          .join()
          .timeout(const Duration(seconds: 15));
      final data = jsonDecode(text) as Map<String, dynamic>;
      final subscriptionUri = Uri.parse(data['endpoint'] as String);
      if (subscriptionUri.scheme != 'https' ||
          subscriptionUri.origin != base.origin) {
        throw const FormatException('Некорректный адрес подписки');
      }
      await WebPushService.instance.registerSubscription(
        WebPushSubscription(
          endpoint: subscriptionUri.toString(),
          publicKey: data['p256dh'] as String,
          authKey: data['auth'] as String,
        ),
      );
      await TokenStorage.writeSecure(_urlKey, baseUrl.trim());
      await TokenStorage.writeSecure(_secretKey, secret);
    } finally {
      client.close(force: true);
    }
  }
}
