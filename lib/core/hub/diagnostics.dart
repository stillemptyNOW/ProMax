import 'dart:convert';
import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'hub_client.dart';

abstract final class Diagnostics {
  static const enabledKey = 'promax_diagnostics_enabled';
  static final enabled = ValueNotifier<bool>(true);
  static final _pending = <Map<String, Object>>[];
  static HubClient _client = HubClient();
  static String _version = 'unknown';
  static String? _installation;
  static bool _ready = false;
  static bool _sending = false;
  static int _generation = 0;
  static Timer? _timer;
  static Timer? _soon;

  static Future<void> init({HubClient? client}) async {
    if (_ready) return;
    if (client != null) _client = client;
    final prefs = await SharedPreferences.getInstance();
    enabled.value = prefs.getBool(enabledKey) ?? true;
    if (enabled.value) {
      try {
        final saved =
            jsonDecode(prefs.getString('promax_diagnostics_queue') ?? '[]')
                as List;
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
      _soon?.cancel();
      _soon = null;
      await prefs.remove('promax_diagnostics_queue');
    }
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
      'platform': kIsWeb ? 'web' : defaultTargetPlatform.name,
    });
    unawaited(_persist());
    _schedule();
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
    _timer?.cancel();
    _soon?.cancel();
    _timer = null;
    _soon = null;
    _pending.clear();
    _client.cancel();
  }

  static Future<void> flush() async {
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
}
