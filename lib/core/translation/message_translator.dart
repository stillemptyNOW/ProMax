import 'package:flutter/foundation.dart';

import 'translation_backend.dart';
import 'translation_cache.dart';
import 'translation_settings.dart';

enum TranslationPhase { idle, loading, translated, original, same, failed }

enum TranslateOutcome { translated, sameLanguage, failed, unavailable }

@immutable
class MessageTranslationState {
  final TranslationPhase phase;
  final String? sourceText;
  final String? targetLanguage;
  final String? text;
  final String? sourceLanguage;
  final bool auto;
  final TranslationFailure? failure;

  const MessageTranslationState({
    required this.phase,
    this.sourceText,
    this.targetLanguage,
    this.text,
    this.sourceLanguage,
    this.auto = false,
    this.failure,
  });

  static const idle = MessageTranslationState(phase: TranslationPhase.idle);

  bool get showsTranslation => phase == TranslationPhase.translated;

  bool get canRestoreTranslation => phase == TranslationPhase.original;

  MessageTranslationState withPhase(TranslationPhase next) =>
      MessageTranslationState(
        phase: next,
        sourceText: sourceText,
        targetLanguage: targetLanguage,
        text: text,
        sourceLanguage: sourceLanguage,
        auto: auto,
        failure: failure,
      );
}

class _TranslationSlot extends ValueNotifier<MessageTranslationState> {
  _TranslationSlot() : super(MessageTranslationState.idle);

  bool get watched => hasListeners;
}

class MessageTranslator {
  MessageTranslator({
    TranslationBackend backend = const MethodChannelTranslationBackend(),
    TranslationSettings? settings,
    TranslationCache? cache,
    this.maxSlots = 2000,
  }) : _backend = backend,
       _settings = settings ?? TranslationSettings.instance,
       cache = cache ?? TranslationCache();

  static final MessageTranslator instance = MessageTranslator();

  final TranslationBackend _backend;
  final TranslationSettings _settings;
  final TranslationCache cache;
  final int maxSlots;

  final Map<String, _TranslationSlot> _slots = {};
  final Map<String, Future<TranslateOutcome>> _inFlight = {};
  Future<TranslationCapabilities>? _capabilitiesFuture;
  bool _disposed = false;

  final ValueNotifier<TranslationCapabilities?> capabilities =
      ValueNotifier<TranslationCapabilities?>(null);

  TranslationBackend get backend => _backend;

  static String keyOf(int accountId, int chatId, String messageId) =>
      '$accountId:$chatId:$messageId';

  bool get available => capabilities.value?.available ?? false;

  Future<TranslationCapabilities> loadCapabilities() =>
      _capabilitiesFuture ??= _backend.capabilities().then((value) {
        if (!_disposed) capabilities.value = value;
        return value;
      });

  ValueListenable<MessageTranslationState> watch(String key) => _slot(key);

  MessageTranslationState stateOf(String key) =>
      _slots[key]?.value ?? MessageTranslationState.idle;

  _TranslationSlot _slot(String key) {
    final existing = _slots[key];
    if (existing != null) return existing;
    if (_slots.length >= maxSlots) _prune();
    return _slots[key] = _TranslationSlot();
  }

  void _prune() {
    final idle = [
      for (final entry in _slots.entries)
        if (!entry.value.watched &&
            entry.value.value.phase != TranslationPhase.loading)
          entry.key,
    ];
    for (final key in idle) {
      _slots.remove(key)?.dispose();
    }
  }

  Future<TranslateOutcome> translate(
    String key,
    String text, {
    required String target,
    bool auto = false,
  }) {
    final request = '$key\u0000$target\u0000$text';
    final running = _inFlight[request];
    if (running != null) return running;
    final future = _translate(key, text, target: target, auto: auto);
    _inFlight[request] = future;
    return future.whenComplete(() => _inFlight.remove(request));
  }

  Future<TranslateOutcome> _translate(
    String key,
    String text, {
    required String target,
    required bool auto,
  }) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return TranslateOutcome.failed;
    final caps = await loadCapabilities();
    if (_disposed || !caps.available) return TranslateOutcome.unavailable;

    final slot = _slot(key);
    final current = slot.value;
    if (current.sourceText == text && current.targetLanguage == target) {
      if (current.phase == TranslationPhase.translated) {
        return TranslateOutcome.translated;
      }
      if (current.phase == TranslationPhase.original && !auto) {
        slot.value = current.withPhase(TranslationPhase.translated);
        return TranslateOutcome.translated;
      }
      if (current.phase == TranslationPhase.same) {
        return TranslateOutcome.sameLanguage;
      }
      if (auto && current.phase != TranslationPhase.idle) {
        return current.phase == TranslationPhase.failed
            ? TranslateOutcome.failed
            : TranslateOutcome.translated;
      }
    }

    final cached = cache.get(target, text);
    if (cached != null) {
      return _apply(slot, text, cached, target: target, auto: auto);
    }

    final waiting = MessageTranslationState(
      phase: TranslationPhase.loading,
      sourceText: text,
      targetLanguage: target,
      auto: auto,
    );
    slot.value = waiting;
    try {
      final output = await _backend.translate(
        text: text,
        target: target,
        wifiOnly: _settings.wifiOnly.value,
      );
      cache.put(target, text, output);
      if (!_stillWaiting(key, slot, waiting)) return TranslateOutcome.failed;
      return _apply(slot, text, output, target: target, auto: auto);
    } on TranslationException catch (e) {
      if (_stillWaiting(key, slot, waiting)) {
        slot.value = MessageTranslationState(
          phase: TranslationPhase.failed,
          sourceText: text,
          targetLanguage: target,
          auto: auto,
          failure: e.failure,
        );
      }
      return TranslateOutcome.failed;
    } catch (_) {
      if (_stillWaiting(key, slot, waiting)) {
        slot.value = MessageTranslationState(
          phase: TranslationPhase.failed,
          sourceText: text,
          targetLanguage: target,
          auto: auto,
          failure: TranslationFailure.failed,
        );
      }
      return TranslateOutcome.failed;
    }
  }

  bool _stillWaiting(
    String key,
    _TranslationSlot slot,
    MessageTranslationState waiting,
  ) =>
      !_disposed &&
      identical(_slots[key], slot) &&
      identical(slot.value, waiting);

  TranslateOutcome _apply(
    _TranslationSlot slot,
    String text,
    TranslationOutput output, {
    required bool auto,
    required String target,
  }) {
    if (output.sameLanguage) {
      slot.value = MessageTranslationState(
        phase: TranslationPhase.same,
        sourceText: text,
        targetLanguage: target,
        sourceLanguage: output.sourceLanguage,
        auto: auto,
      );
      return TranslateOutcome.sameLanguage;
    }
    slot.value = MessageTranslationState(
      phase: TranslationPhase.translated,
      sourceText: text,
      text: output.text,
      targetLanguage: target,
      sourceLanguage: output.sourceLanguage,
      auto: auto,
    );
    return TranslateOutcome.translated;
  }

  void showOriginal(String key) {
    final slot = _slots[key];
    if (slot == null) return;
    final state = slot.value;
    if (state.phase != TranslationPhase.translated) return;
    slot.value = state.auto
        ? state.withPhase(TranslationPhase.original)
        : MessageTranslationState.idle;
  }

  void showTranslation(String key) {
    final slot = _slots[key];
    if (slot == null || !slot.value.canRestoreTranslation) return;
    slot.value = slot.value.withPhase(TranslationPhase.translated);
  }

  void reset(String key) {
    final slot = _slots[key];
    if (slot == null) return;
    slot.value = MessageTranslationState.idle;
  }

  void resetAutoInChat(int accountId, int chatId) {
    final prefix = '$accountId:$chatId:';
    for (final entry in _slots.entries) {
      if (entry.key.startsWith(prefix) && entry.value.value.auto) {
        entry.value.value = MessageTranslationState.idle;
      }
    }
  }

  void dispose() {
    _disposed = true;
    for (final slot in _slots.values) {
      slot.dispose();
    }
    _slots.clear();
    capabilities.dispose();
  }

  Future<List<String>> downloadedModels() => _backend.downloadedModels();

  Future<bool> deleteModel(String language) async {
    final deleted = await _backend.deleteModel(language);
    if (deleted) cache.clear();
    return deleted;
  }
}
