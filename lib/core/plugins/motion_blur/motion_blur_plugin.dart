import 'dart:convert';
import 'dart:ui' as ui;

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';

import '../../config/persisted_setting.dart';
import '../native_plugin.dart';
import 'motion_blur_curve.dart';
import 'motion_blur_settings.dart';

class MotionBlurPlugin implements NativePlugin {
  MotionBlurPlugin._();

  static final MotionBlurPlugin instance = MotionBlurPlugin._();

  static const String pluginId = 'promax.native.motion_blur';
  static const String prefKey = 'native_plugin_motion_blur_v1';
  static const String shaderAsset = 'shaders/motion_blur.frag';
  static const int _lowEndAndroidRamMb = 3500;
  static const int _lowEndIosRamMb = 2600;

  final PersistedSetting<MotionBlurSettings> _setting =
      PersistedSetting<MotionBlurSettings>(
        prefKey: prefKey,
        defaultValue: const MotionBlurSettings(),
        read: (prefs, key) {
          final raw = prefs.getString(key);
          if (raw == null) return null;
          try {
            return MotionBlurSettings.fromJson(jsonDecode(raw));
          } on FormatException {
            return null;
          }
        },
        write: (prefs, key, value) =>
            prefs.setString(key, jsonEncode(value.toJson())),
      );
  final ValueNotifier<bool> _enabled = ValueNotifier(false);
  final ValueNotifier<bool> _lowEnd = ValueNotifier(false);
  Future<void>? _budgetLoad;
  Future<void>? _programLoad;
  ui.FragmentProgram? _program;

  @override
  String get id => pluginId;

  @override
  String get version => '1.0';

  @override
  ValueListenable<bool> get enabled => _enabled;

  ValueListenable<MotionBlurSettings> get settings => _setting.current;

  ValueListenable<bool> get lowEnd => _lowEnd;

  MotionBlurBudget get budget =>
      _lowEnd.value ? MotionBlurBudget.lowEnd : MotionBlurBudget.full;

  ui.FragmentProgram? get program => _program;

  bool allows(MotionBlurTarget target) => _setting.current.value.allows(target);

  @override
  Future<void> load() async {
    final loaded = await _setting.load();
    _enabled.value = loaded.enabled;
    await (_budgetLoad ??= _detectBudget());
    if (loaded.enabled) await ensureShader();
  }

  @override
  Future<void> setEnabled(bool value) =>
      update(_setting.current.value.copyWith(enabled: value));

  Future<void> update(MotionBlurSettings next) async {
    _enabled.value = next.enabled;
    if (next.enabled) await ensureShader();
    await _setting.save(next);
  }

  void preview(MotionBlurSettings next) {
    _setting.current.value = next;
    _enabled.value = next.enabled;
  }

  Future<void> ensureShader() => _programLoad ??= _loadProgram();

  Future<void> _loadProgram() async {
    if (!ui.ImageFilter.isShaderFilterSupported) return;
    try {
      _program = await ui.FragmentProgram.fromAsset(shaderAsset);
    } catch (_) {
      _program = null;
    }
  }

  Future<void> _detectBudget() async {
    if (kIsWeb) return;
    try {
      final info = DeviceInfoPlugin();
      switch (defaultTargetPlatform) {
        case TargetPlatform.android:
          final android = await info.androidInfo;
          _lowEnd.value =
              android.isLowRamDevice ||
              (android.physicalRamSize > 0 &&
                  android.physicalRamSize < _lowEndAndroidRamMb);
        case TargetPlatform.iOS:
          final ios = await info.iosInfo;
          _lowEnd.value =
              ios.physicalRamSize > 0 && ios.physicalRamSize < _lowEndIosRamMb;
        default:
          return;
      }
    } catch (_) {
      _lowEnd.value = false;
    }
  }

  @visibleForTesting
  void debugOverride({
    MotionBlurSettings settings = const MotionBlurSettings(),
    bool lowEnd = false,
  }) {
    _setting.current.value = settings;
    _enabled.value = settings.enabled;
    _lowEnd.value = lowEnd;
  }
}
