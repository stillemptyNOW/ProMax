import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../utils/logger.dart';

// #***! канал к нативному FKM, своё фоновое уведомление вместо фаербейза
/// Канал к нативному сервису FKM (foreground promax messaging).
class FkmBridge {
  FkmBridge._(this.isSupported);
  static final FkmBridge instance = FkmBridge._(_platformSupported());

  @visibleForTesting
  FkmBridge.forTesting({required this.isSupported});

  static const _method = MethodChannel('io.github.stillemptynow.promax/fkm');

  final bool isSupported;

  VoidCallback? _onDisabled;
  VoidCallback? _onAttached;
  bool _handlerSet = false;
  final StreamController<void> _attached = StreamController<void>.broadcast();

  Stream<void> get attached => _attached.stream;

  static bool _platformSupported() {
    try {
      return Platform.isAndroid || Platform.isIOS;
    } catch (_) {
      return false;
    }
  }

  // #***! юзер может выключить FKM прямо из уведомления
  void listen({
    required VoidCallback onDisabled,
    required VoidCallback onAttached,
  }) {
    _onDisabled = onDisabled;
    _onAttached = onAttached;
    if (_handlerSet || !isSupported) return;
    _handlerSet = true;
    _method.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'disabled':
          _onDisabled?.call();
        case 'attached':
          _onAttached?.call();
          _attached.add(null);
      }
      return null;
    });
  }

  // #***! дальше по методу на операцию натива
  Future<bool> isEnabled() async {
    if (!isSupported) return false;
    return await _invoke<bool>('isEnabled') ?? false;
  }

  Future<void> setEnabled(bool enabled) =>
      _invoke<void>('setEnabled', {'enabled': enabled});

  Future<void> setConnected(bool connected) =>
      _invoke<void>('setConnected', {'connected': connected});

  Future<void> showMessage(Map<String, String> data) =>
      _invoke<void>('showMessage', {'data': data});

  Future<void> showCall(Map<String, String> data) =>
      _invoke<void>('showCall', {'data': data});

  Future<void> editMessage(Map<String, String> data) =>
      _invoke<void>('editMessage', {'data': data});

  Future<void> removeMessage(Map<String, String> data) =>
      _invoke<void>('removeMessage', {'data': data});

  Future<bool> hasNotificationPermission() async {
    if (!isSupported) return false;
    return await _invoke<bool>('hasNotificationPermission') ?? false;
  }

  Future<bool> requestNotificationPermission() async {
    if (!isSupported) return false;
    return await _invoke<bool>('requestNotificationPermission') ?? false;
  }

  // #***! без отключённой оптимизации батареи андроид прибьёт сервис
  Future<bool> isIgnoringBatteryOptimizations() async {
    if (!isSupported) return true;
    return await _invoke<bool>('isIgnoringBatteryOptimizations') ?? true;
  }

  Future<void> requestIgnoreBatteryOptimizations() =>
      _invoke<void>('requestIgnoreBatteryOptimizations');

  // #***! ошибки канала не пробрасываем, без FKM просто не будет пушей
  Future<T?> _invoke<T>(String method, [Map<String, dynamic>? args]) async {
    if (!isSupported) return null;
    try {
      return await _method.invokeMethod<T>(method, args);
    } catch (e) {
      logger.w('FkmBridge.$method: $e');
      return null;
    }
  }
}
