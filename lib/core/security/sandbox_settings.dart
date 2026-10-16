import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/windows_registry.dart';

abstract final class SandboxSettings {
  static const String _confirmEveryFileKey = 'sandbox_confirm_every_file';
  static const String processPolicyKey = r'Software\ProMax\Sandbox';
  static const String strictProcessValue = 'StrictProcess';

  static bool get strictProcessSupported => !kIsWeb && Platform.isWindows;

  static Future<bool> confirmEveryFile() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_confirmEveryFileKey) ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<void> setConfirmEveryFile(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_confirmEveryFileKey, value);
  }

  static bool strictProcess() {
    if (!strictProcessSupported) return false;
    return WindowsRegistry.currentUser?.readDword(
          processPolicyKey,
          strictProcessValue,
        ) ==
        1;
  }

  static bool setStrictProcess(bool value) {
    if (!strictProcessSupported) return false;
    return WindowsRegistry.currentUser?.writeDword(
          processPolicyKey,
          strictProcessValue,
          value ? 1 : 0,
        ) ??
        false;
  }
}
