import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

@immutable
class TranslationCapabilities {
  final bool available;
  final bool manageModels;
  final bool wifiOnlyOption;

  const TranslationCapabilities({
    required this.available,
    this.manageModels = false,
    this.wifiOnlyOption = false,
  });

  static const unavailable = TranslationCapabilities(available: false);

  factory TranslationCapabilities.fromMap(Map<Object?, Object?>? map) {
    if (map == null) return unavailable;
    return TranslationCapabilities(
      available: map['available'] == true,
      manageModels: map['manageModels'] == true,
      wifiOnlyOption: map['wifiOnlyOption'] == true,
    );
  }
}

@immutable
class TranslationOutput {
  final String text;
  final String? sourceLanguage;
  final bool sameLanguage;

  const TranslationOutput({
    required this.text,
    this.sourceLanguage,
    this.sameLanguage = false,
  });
}

enum TranslationFailure {
  unsupported,
  undetermined,
  needsWifi,
  downloadFailed,
  failed;

  static TranslationFailure fromCode(String code) => switch (code) {
    'unsupported' => unsupported,
    'undetermined' => undetermined,
    'needs_wifi' => needsWifi,
    'download_failed' => downloadFailed,
    _ => failed,
  };
}

class TranslationException implements Exception {
  final TranslationFailure failure;
  final String? message;

  const TranslationException(this.failure, [this.message]);

  @override
  String toString() => 'TranslationException(${failure.name}, $message)';
}

abstract class TranslationBackend {
  Future<TranslationCapabilities> capabilities();

  Future<String?> detect(String text);

  Future<TranslationOutput> translate({
    required String text,
    required String target,
    String? source,
    bool wifiOnly = false,
  });

  Future<List<String>> downloadedModels();

  Future<bool> deleteModel(String language);
}

class MethodChannelTranslationBackend implements TranslationBackend {
  static const MethodChannel _channel = MethodChannel(
    'io.github.stillemptynow.promax/translate',
  );

  const MethodChannelTranslationBackend();

  static bool get platformSupported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  @override
  Future<TranslationCapabilities> capabilities() async {
    if (!platformSupported) return TranslationCapabilities.unavailable;
    try {
      final map = await _channel.invokeMapMethod<Object?, Object?>(
        'capabilities',
      );
      return TranslationCapabilities.fromMap(map);
    } on PlatformException {
      return TranslationCapabilities.unavailable;
    } on MissingPluginException {
      return TranslationCapabilities.unavailable;
    }
  }

  @override
  Future<String?> detect(String text) async {
    try {
      return await _channel.invokeMethod<String>('detect', {'text': text});
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  @override
  Future<TranslationOutput> translate({
    required String text,
    required String target,
    String? source,
    bool wifiOnly = false,
  }) async {
    try {
      final map = await _channel.invokeMapMethod<Object?, Object?>(
        'translate',
        {
          'text': text,
          'target': target,
          'source': ?source,
          'wifiOnly': wifiOnly,
        },
      );
      final translated = map?['text'];
      if (translated is! String) {
        throw const TranslationException(TranslationFailure.failed);
      }
      return TranslationOutput(
        text: translated,
        sourceLanguage: map?['source'] as String?,
        sameLanguage: map?['same'] == true,
      );
    } on PlatformException catch (e) {
      throw TranslationException(
        TranslationFailure.fromCode(e.code),
        e.message,
      );
    } on MissingPluginException {
      throw const TranslationException(TranslationFailure.unsupported);
    }
  }

  @override
  Future<List<String>> downloadedModels() async {
    try {
      final list = await _channel.invokeListMethod<String>('models');
      return list ?? const [];
    } on PlatformException {
      return const [];
    } on MissingPluginException {
      return const [];
    }
  }

  @override
  Future<bool> deleteModel(String language) async {
    try {
      return await _channel.invokeMethod<bool>('deleteModel', {
            'language': language,
          }) ??
          false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }
}
