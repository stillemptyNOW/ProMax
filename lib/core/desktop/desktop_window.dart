import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../push/notification_policy.dart';
import '../utils/logger.dart';

class DesktopWindow {
  DesktopWindow._();

  static final DesktopWindow instance = DesktopWindow._();

  static const _channel = MethodChannel(
    'io.github.stillemptynow.promax/window',
  );
  static const closeToTrayPrefKey = 'desktop_close_to_tray';
  static const minimizedArgument = '--minimized';

  final ValueNotifier<bool> closeToTray = ValueNotifier(true);
  final ValueNotifier<bool> autostart = ValueNotifier(false);

  Future<void> Function()? _onQuitRequested;
  bool _started = false;

  bool get supported {
    if (kIsWeb) return false;
    try {
      return Platform.isWindows;
    } catch (_) {
      return false;
    }
  }

  bool get isDesktop {
    if (kIsWeb) return false;
    try {
      return Platform.isWindows || Platform.isLinux || Platform.isMacOS;
    } catch (_) {
      return false;
    }
  }

  Future<void> init({required Future<void> Function() onQuitRequested}) async {
    if (_started || !supported) return;
    _started = true;
    _onQuitRequested = onQuitRequested;
    _channel.setMethodCallHandler(_onNativeCall);
    final prefs = await SharedPreferences.getInstance();
    closeToTray.value = prefs.getBool(closeToTrayPrefKey) ?? true;
    await _invoke<void>('setCloseToTray', {'enabled': closeToTray.value});
    autostart.value = await _invoke<bool>('autostart') ?? false;
    await _invoke<void>('setTrayLabels', {
      'open': 'Открыть ProMax',
      'exit': 'Выход',
    });
  }

  Future<void> setCloseToTray(bool value) async {
    closeToTray.value = value;
    await _invoke<void>('setCloseToTray', {'enabled': value});
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(closeToTrayPrefKey, value);
  }

  Future<bool> setAutostart(bool value) async {
    final applied = await _invoke<bool>('setAutostart', {'enabled': value});
    autostart.value = await _invoke<bool>('autostart') ?? false;
    return applied ?? false;
  }

  Future<WindowPresence> presence() async {
    if (supported) {
      final raw = await _invoke<Map<Object?, Object?>>('presence');
      if (raw != null) {
        return WindowPresence(
          visible: raw['visible'] == true,
          minimized: raw['minimized'] == true,
          focused: raw['focused'] == true,
        );
      }
    }
    final state = WidgetsBinding.instance.lifecycleState;
    return WindowPresence(
      visible: state != AppLifecycleState.hidden,
      minimized: false,
      focused: state == null || state == AppLifecycleState.resumed,
    );
  }

  Future<void> reveal() => _invoke<void>('reveal');

  Future<void> hide() => _invoke<void>('hide');

  Future<void> flash() => _invoke<void>('flash');

  Future<void> quit() => _invoke<void>('quit');

  Future<dynamic> _onNativeCall(MethodCall call) async {
    if (call.method != 'quitRequested') return null;
    final onQuit = _onQuitRequested;
    if (onQuit == null) {
      await quit();
      return null;
    }
    unawaited(_quitAfter(onQuit));
    return null;
  }

  Future<void> _quitAfter(Future<void> Function() prepare) async {
    try {
      await prepare();
    } catch (e) {
      logger.w('DesktopWindow: подготовка к выходу не удалась: $e');
    }
    await quit();
  }

  Future<T?> _invoke<T>(String method, [Object? arguments]) async {
    if (!supported) return null;
    try {
      return await _channel.invokeMethod<T>(method, arguments);
    } on MissingPluginException {
      return null;
    } on PlatformException catch (e) {
      logger.w('DesktopWindow.$method: ${e.message}');
      return null;
    }
  }
}
