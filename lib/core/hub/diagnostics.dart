import 'dart:convert';
import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'hub_client.dart';
import '../config/app_performance.dart';
import '../config/platform_settings.dart';

enum DiagnosticStage {
  digitalIdLaunch,
  digitalIdCallback,
  digitalIdExchange,
  digitalIdWebView,
  digitalIdDocuments,
  digitalIdVerification,
  apnsPermission,
  apnsToken,
  apnsRegistration,
  apnsUnregistration,
  apnsDelivery,
  apnsLocalTest,
  apnsRelayHealth,
  hubRequest,
  maxConnection,
  webPushAuth,
  webPushLink,
  webPushReceipt,
  webPushSubscription,
  featureSession,
  featureAppearance,
  featureSettingsShare,
  featureDigitalId,
  featureWebPush,
  featureGroupEncryption,
  featureBatchFiles,
  featureAntiReadException,
  featureChatSearch,
}

enum DiagnosticOutcome {
  started,
  success,
  failed,
  timeout,
  denied,
  cancelled,
  skipped,
  invalid,
  unavailable,
  retry,
  offline,
}

abstract final class Diagnostics {
  static const enabledKey = 'promax_diagnostics_enabled';
  static const operationsEnabledKey = 'promax_diagnostics_operations_enabled';
  static final enabled = ValueNotifier<bool>(true);
  static final operationsEnabled = ValueNotifier<bool>(false);
  static final _pending = <Map<String, Object>>[];
  static final _operations = <Map<String, Object>>[];
  static final _featuresSeen = <DiagnosticStage>{};
  static HubClient _client = HubClient();
  static HubClient _operationsClient = HubClient();
  static final _operationVersionPattern = RegExp(
    r'^[0-9]{1,5}\.[0-9]{1,5}\.[0-9]{1,5}(?:\+[0-9]{0,10})?$',
  );
  static String _version = 'unknown';
  static String? _installation;
  static bool _ready = false;
  static bool _sending = false;
  static bool _sendingOperations = false;
  static int _generation = 0;
  static int _operationsGeneration = 0;
  static Timer? _timer;
  static Timer? _soon;

  static Future<void> init({
    HubClient? client,
    HubClient? operationsClient,
  }) async {
    if (_ready) return;
    if (client != null) _client = client;
    if (operationsClient != null) _operationsClient = operationsClient;
    final prefs = await SharedPreferences.getInstance();
    enabled.value = prefs.getBool(enabledKey) ?? true;
    operationsEnabled.value = prefs.getBool(operationsEnabledKey) ?? false;
    if (enabled.value) {
      try {
        final saved = jsonDecode(
          prefs.getString('promax_diagnostics_queue') ?? '[]',
        ) as List;
        for (final entry in saved.take(16)) {
          if (entry is! Map) continue;
          if (!const {
            'flutter_error',
            'uncaught_error',
            'log_error',
          }.contains(entry['kind'])) {
            continue;
          }
          if (entry['error_type'] is! String ||
              entry['version'] is! String ||
              entry['platform'] is! String) {
            continue;
          }
          _pending.add({
            'kind': entry['kind'] as String,
            'error_type': entry['error_type'] as String,
            'version': entry['version'] as String,
            'platform': entry['platform'] as String,
            'frames': appFrames(
              StackTrace.fromString('${entry['frames'] ?? ''}'),
            ),
          });
        }
      } catch (_) {}
    } else {
      await prefs.remove('promax_diagnostics_queue');
    }
    _installation = prefs.getString('promax_diagnostics_id');
    if (_installation == null) {
      final random = Random.secure();
      _installation = List.generate(
        24,
        (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
      ).join();
      await prefs.setString('promax_diagnostics_id', _installation!);
    }
    try {
      final info = await PackageInfo.fromPlatform();
      _version = '${info.version}+${info.buildNumber}';
    } catch (_) {}
    _ready = true;
    recordFeature(DiagnosticStage.featureSession);
    if (_pending.isNotEmpty) _schedule();
    _timer?.cancel();
    _timer = Timer.periodic(
      const Duration(minutes: 2),
      (_) => unawaited(flush()),
    );
  }

  static Future<void> setEnabled(bool value) async {
    enabled.value = value;
    _generation++;
    if (!value) {
      _pending.clear();
      _client.cancel();
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(enabledKey, value);
    if (!value) {
      if (_operations.isEmpty) {
        _soon?.cancel();
        _soon = null;
      }
      await prefs.remove('promax_diagnostics_queue');
    }
  }

  static Future<void> setOperationsEnabled(bool value) async {
    operationsEnabled.value = value;
    _operationsGeneration++;
    if (!value) {
      _operations.clear();
      _featuresSeen.clear();
      _operationsClient.cancel();
    } else {
      recordFeature(DiagnosticStage.featureSession);
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(operationsEnabledKey, value);
  }

  static Future<bool> sendPerformance() async {
    if (!_ready || !enabled.value || AppPerformance.frameHealth.frames == 0) {
      return false;
    }
    final generation = _generation;
    await _client.request(
      '/v1/performance',
      method: 'POST',
      body: {
        'installation': _installation,
        'version': _version,
        'platform': PlatformSettings.current,
        'mode': AppPerformance.mode.value.name,
        'tier': AppPerformance.effectiveTier.name,
        'refresh_hz': AppPerformance.displayRefreshRate().round().clamp(
          30,
          1000,
        ),
        'summary': AppPerformance.frameHealth.summary,
      },
    );
    return enabled.value && generation == _generation;
  }

  @visibleForTesting
  static List<String> appFrames(StackTrace? stack) =>
      RegExp(
            r'package:(?:promax|promax_effects|promax_crypto|promax_tlottie)/[A-Za-z0-9_./-]+\.dart:\d+(?::\d+)?',
          )
          .allMatches(stack?.toString() ?? '')
          .take(16)
          .map((match) => match.group(0)!)
          .toList();

  static void record(String kind, Object error, StackTrace? stack) {
    if (!_ready || !enabled.value || _pending.length >= 16) return;
    _pending.add({
      'kind': kind,
      'error_type': error.runtimeType.toString(),
      'frames': appFrames(stack),
      'version': _version,
      'platform': PlatformSettings.current,
    });
    unawaited(_persist());
    _schedule();
  }

  static void recordOperation(
    DiagnosticStage stage,
    DiagnosticOutcome outcome, {
    Duration? elapsed,
    int? statusCode,
  }) {
    if (!_ready || !operationsEnabled.value || _operations.length >= 16) {
      return;
    }
    _operations.add({
      'stage': stage.name,
      'outcome': outcome.name,
      'version': _operationVersionPattern.hasMatch(_version)
          ? _version
          : 'unknown',
      'platform': PlatformSettings.current,
      if (elapsed != null)
        'duration_ms': elapsed.inMilliseconds.clamp(0, 3600000),
      if (statusCode != null && statusCode >= 100 && statusCode <= 599)
        'status_code': statusCode,
    });
    _schedule();
  }

  static void recordFeature(DiagnosticStage feature) {
    if (!_ready ||
        !operationsEnabled.value ||
        _operations.length >= 16 ||
        !feature.name.startsWith('feature') ||
        !_featuresSeen.add(feature)) {
      return;
    }
    recordOperation(feature, DiagnosticOutcome.success);
  }

  static void _schedule() {
    _soon ??= Timer(const Duration(seconds: 15), () {
      _soon = null;
      unawaited(flush());
    });
  }

  static Future<void> _persist() async {
    final generation = _generation;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (generation != _generation || !enabled.value) return;
      await prefs.setString('promax_diagnostics_queue', jsonEncode(_pending));
    } catch (_) {}
  }

  static void dispose() {
    _ready = false;
    _generation++;
    _operationsGeneration++;
    _timer?.cancel();
    _soon?.cancel();
    _timer = null;
    _soon = null;
    _pending.clear();
    _operations.clear();
    _featuresSeen.clear();
    _client.cancel();
    _operationsClient.cancel();
  }

  static Future<void> flush() async {
    await Future.wait([_flushErrors(), _flushOperations()]);
  }

  static Future<void> _flushErrors() async {
    if (!_ready || !enabled.value || _sending || _pending.isEmpty) return;
    _sending = true;
    final generation = _generation;
    final batch = List<Map<String, Object>>.of(_pending);
    try {
      if (!enabled.value || generation != _generation) return;
      await _client.request(
        '/v1/telemetry',
        method: 'POST',
        body: {'installation': _installation, 'events': batch},
      );
      if (generation == _generation) {
        _pending.removeRange(0, min(batch.length, _pending.length));
      }
      await _persist();
    } catch (_) {
    } finally {
      _sending = false;
    }
  }

  static Future<void> _flushOperations() async {
    if (!_ready ||
        !operationsEnabled.value ||
        _sendingOperations ||
        _operations.isEmpty) {
      return;
    }
    _sendingOperations = true;
    final generation = _operationsGeneration;
    final batch = List<Map<String, Object>>.of(_operations);
    var removeBatch = false;
    try {
      await _operationsClient.request(
        '/v1/telemetry/operations',
        method: 'POST',
        body: {'events': batch},
      );
      removeBatch = true;
    } on HubException catch (error) {
      removeBatch = const {400, 404, 413, 422}.contains(error.status);
    } catch (_) {
    } finally {
      if (removeBatch && generation == _operationsGeneration) {
        _operations.removeRange(0, batch.length);
      }
      _sendingOperations = false;
    }
  }
}
