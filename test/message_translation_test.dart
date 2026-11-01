import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:promax/core/translation/message_translator.dart';
import 'package:promax/core/translation/translation_backend.dart';
import 'package:promax/core/translation/translation_cache.dart';
import 'package:promax/core/translation/translation_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Backend implements TranslationBackend {
  final pending = <Completer<TranslationOutput>>[];
  int calls = 0;

  @override
  Future<TranslationCapabilities> capabilities() async =>
      const TranslationCapabilities(available: true);

  @override
  Future<TranslationOutput> translate({
    required String text,
    required String target,
    String? source,
    bool wifiOnly = false,
  }) {
    calls++;
    final task = Completer<TranslationOutput>();
    pending.add(task);
    return task.future;
  }

  @override
  Future<String?> detect(String text) async => 'en';

  @override
  Future<List<String>> downloadedModels() async => [];

  @override
  Future<bool> deleteModel(String language) async => true;
}

void main() {
  late _Backend backend;
  late MessageTranslator translator;
  const key = '101:202:303';

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    backend = _Backend();
    translator = MessageTranslator(backend: backend);
  });
  tearDown(() => translator.dispose());

  test('concurrent requests for one text and language share work', () async {
    final first = translator.translate(key, 'synthetic hello', target: 'ru');
    final second = translator.translate(key, 'synthetic hello', target: 'ru');
    await pumpEventQueue();
    expect(backend.calls, 1);
    backend.pending.single.complete(
      const TranslationOutput(text: 'синтетический привет'),
    );
    expect(await first, TranslateOutcome.translated);
    expect(await second, TranslateOutcome.translated);
  });

  test('changing target ignores a late result in the old language', () async {
    final old = translator.translate(key, 'synthetic hello', target: 'ru');
    await pumpEventQueue();
    final next = translator.translate(key, 'synthetic hello', target: 'de');
    await pumpEventQueue();
    expect(backend.calls, 2);
    backend.pending[1].complete(
      const TranslationOutput(text: 'synthetisches Hallo'),
    );
    await next;
    backend.pending[0].complete(
      const TranslationOutput(text: 'синтетический привет'),
    );
    await old;
    expect(translator.stateOf(key).targetLanguage, 'de');
    expect(translator.stateOf(key).text, 'synthetisches Hallo');
  });

  test('completed translations are keyed by target as well as text', () async {
    final first = translator.translate(key, 'synthetic hello', target: 'ru');
    await pumpEventQueue();
    backend.pending[0].complete(
      const TranslationOutput(text: 'синтетический привет'),
    );
    await first;
    final second = translator.translate(key, 'synthetic hello', target: 'en');
    await pumpEventQueue();
    expect(backend.calls, 2);
    backend.pending[1].complete(
      const TranslationOutput(text: 'synthetic hello', sameLanguage: true),
    );
    expect(await second, TranslateOutcome.sameLanguage);
  });

  test('turning off auto translation discards an unfinished result', () async {
    final task = translator.translate(
      key,
      'synthetic hello',
      target: 'ru',
      auto: true,
    );
    await pumpEventQueue();
    translator.resetAutoInChat(101, 202);
    backend.pending.single.complete(
      const TranslationOutput(text: 'синтетический привет'),
    );
    await task;
    expect(translator.stateOf(key).phase, TranslationPhase.idle);
  });

  test('platform and download errors become recoverable state', () async {
    final task = translator.translate(key, 'synthetic hello', target: 'ru');
    await pumpEventQueue();
    backend.pending.single.completeError(
      const TranslationException(TranslationFailure.needsWifi),
    );
    expect(await task, TranslateOutcome.failed);
    expect(translator.stateOf(key).failure, TranslationFailure.needsWifi);
  });

  test(
    'auto translation can show the original and restore its result',
    () async {
      final task = translator.translate(
        key,
        'synthetic hello',
        target: 'ru',
        auto: true,
      );
      await pumpEventQueue();
      backend.pending.single.complete(
        const TranslationOutput(text: 'синтетический привет'),
      );
      await task;
      translator.showOriginal(key);
      expect(translator.stateOf(key).phase, TranslationPhase.original);
      translator.showTranslation(key);
      expect(translator.stateOf(key).showsTranslation, isTrue);
      expect(backend.calls, 1);
    },
  );

  test('settings survive reload and isolate chat/account identities', () async {
    final settings = TranslationSettings.instance;
    await settings.setTargetLanguage('de');
    await settings.setWifiOnly(true);
    await settings.setAuto(101, 202, true);
    await settings.load();
    expect(settings.targetFor('ru'), 'de');
    expect(settings.wifiOnly.value, isTrue);
    expect(settings.isAuto(101, 202), isTrue);
    expect(settings.isAuto(102, 202), isFalse);
  });

  test('cache evicts the least recently used text', () {
    final cache = TranslationCache(capacity: 2);
    const output = TranslationOutput(text: 'synthetic');
    cache.put('ru', 'one', output);
    cache.put('ru', 'two', output);
    cache.get('ru', 'one');
    cache.put('de', 'three', output);
    expect(cache.get('ru', 'two'), isNull);
    expect(cache.get('ru', 'one'), isNotNull);
    expect(cache.get('en', 'one'), isNull);
  });
}
