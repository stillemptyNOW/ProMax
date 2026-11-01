import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promax/core/calls/camera_devices.dart';
import 'package:promax_effects/promax_effects.dart';

const _plugin = 'native/promax_effects';
const _kotlin = '$_plugin/android/src/main/kotlin/promax/effects';
const _bridge = '$_plugin/android/src/main/cpp/promax_effects_jni.cpp';

String _read(String path) =>
    File(path).readAsStringSync().replaceAll('\r\n', '\n');

Set<String> _matches(String pattern, String source) =>
    RegExp(pattern).allMatches(source).map((match) => match.group(1)!).toSet();

int _kotlinConstant(String name) {
  final source = _read('$_kotlin/NativeEffects.kt');
  final match = RegExp('const val $name = (\\d+)').firstMatch(source);
  expect(match, isNotNull, reason: name);
  return int.parse(match!.group(1)!);
}

int _nativeConstant(String source, String name) {
  final match = RegExp('$name = (\\d+);').firstMatch(source);
  expect(match, isNotNull, reason: name);
  return int.parse(match!.group(1)!);
}

Directory _packageRoot(String name) {
  final configFile = File('.dart_tool/package_config.json');
  final config = jsonDecode(configFile.readAsStringSync()) as Map;
  final package = (config['packages'] as List).cast<Map>().firstWhere(
    (entry) => entry['name'] == name,
  );
  final root = configFile.uri.resolve(package['rootUri'] as String);
  return Directory.fromUri(root);
}

void main() {
  group('call effects platforms', () {
    test('run on iOS and Android apps only', () {
      expect(ProMaxEffects.supportedOn(TargetPlatform.iOS, web: false), isTrue);
      expect(
        ProMaxEffects.supportedOn(TargetPlatform.android, web: false),
        isTrue,
      );
      for (final platform in [
        TargetPlatform.macOS,
        TargetPlatform.windows,
        TargetPlatform.linux,
        TargetPlatform.fuchsia,
      ]) {
        expect(
          ProMaxEffects.supportedOn(platform, web: false),
          isFalse,
          reason: '$platform',
        );
      }
      expect(
        ProMaxEffects.supportedOn(TargetPlatform.android, web: true),
        isFalse,
      );
      expect(ProMaxEffects.supportedOn(TargetPlatform.iOS, web: true), isFalse);
    });

    test('camera facing prefers the facing mode WebRTC reports', () {
      expect(
        CameraDevices.facingOfTrack('2f0c', {'facingMode': 'environment'}),
        CameraFacing.back,
      );
      expect(
        CameraDevices.facingOfTrack('2f0c', {'facingMode': 'user'}),
        CameraFacing.front,
      );
      expect(
        CameraDevices.facingOfTrack('Rear Camera', const {}),
        CameraFacing.back,
      );
      expect(
        CameraDevices.facingOfTrack('2f0c', const {}),
        CameraFacing.external,
      );
    });
  });

  group('Android effects plugin', () {
    test('registers the Kotlin plugin on the shared channel', () {
      final pubspec = _read('$_plugin/pubspec.yaml');
      expect(pubspec, contains('android:\n        package: promax.effects'));
      expect(pubspec, contains('pluginClass: ProMaxEffectsPlugin'));
      final plugin = _read('$_kotlin/ProMaxEffectsPlugin.kt');
      expect(plugin, startsWith('package promax.effects\n'));
      expect(plugin, contains('class ProMaxEffectsPlugin :'));
      expect(plugin, contains('"promax/effects"'));
      final dart = _read('$_plugin/lib/promax_effects.dart');
      final dartMethods = _matches(r"invokeMethod\('(\w+)'", dart);
      final kotlinMethods = _matches(r'"(\w+)" ->', plugin);
      expect(dartMethods, isNotEmpty);
      expect(kotlinMethods, containsAll(dartMethods));
    });

    test('declares every JNI entry point the Kotlin side loads', () {
      final kotlin = _read('$_kotlin/NativeEffects.kt');
      final bridge = _read(_bridge);
      final externals = _matches(r'external fun (\w+)\(', kotlin);
      final exported = _matches(
        r'Java_promax_effects_NativeEffects_(\w+)\(',
        bridge,
      );
      expect(externals, isNotEmpty);
      expect(exported, externals);
      expect(kotlin, contains('System.loadLibrary("promax_effects")'));
      final cmake = _read('$_plugin/android/CMakeLists.txt');
      expect(cmake, contains('add_library(promax_effects SHARED'));
      final proguard = _read('$_plugin/android/proguard-rules.pro');
      expect(proguard, contains('class promax.effects.NativeEffects'));
      expect(proguard, contains('native <methods>;'));
    });

    test('shares buffer layouts and the native cores with iOS', () {
      final bridge = _read(_bridge);
      expect(
        _kotlinConstant('SAMPLE_STRIDE'),
        _nativeConstant(bridge, 'kSampleStride'),
      );
      expect(
        _kotlinConstant('SPEC_SIZE'),
        _nativeConstant(bridge, 'kSpecSize'),
      );
      expect(
        _kotlinConstant('QUAD_STRIDE'),
        _nativeConstant(bridge, 'kQuadStride'),
      );
      final pose = _read('$_plugin/ios/Classes/MaskPose.h');
      final capacity = _nativeConstant(
        pose,
        r'static constexpr std::size_t kCapacity',
      );
      expect(_kotlinConstant('FACE_CAPACITY'), capacity);
      final cmake = _read('$_plugin/android/CMakeLists.txt');
      expect(cmake, contains(r'${CMAKE_CURRENT_SOURCE_DIR}/../ios/Classes'));
      expect(bridge, contains('#include "MaskPose.h"'));
      expect(bridge, contains('#include "VoiceProcessor.h"'));
    });

    test('reads the same mask artwork the Dart side bundles', () {
      final catalog = _read('$_kotlin/MaskCatalog.kt');
      expect(catalog, contains('const val PACKAGE = "promax_effects"'));
      expect(
        catalog,
        contains('const val DIRECTORY = "${ProMaxMask.directory}"'),
      );
    });

    test('compiles against the WebRTC build flutter_webrtc ships', () {
      final ours = _read('$_plugin/android/build.gradle');
      final pattern = RegExp(r"io\.github\.webrtc-sdk:android:([\w.]+)");
      final pinned = pattern.firstMatch(ours)?.group(1);
      expect(pinned, isNotNull);
      expect(ours, contains('compileOnly "io.github.webrtc-sdk:android:'));
      final webrtc = _packageRoot('flutter_webrtc');
      final upstream = File(
        '${webrtc.path}/android/build.gradle',
      ).readAsStringSync();
      expect(pattern.firstMatch(upstream)?.group(1), pinned);
    });

    test('keeps the SDK levels of the other native plugins', () {
      final gradle = _read('$_plugin/android/build.gradle');
      expect(gradle, contains('minSdk = 23'));
      expect(gradle, contains('namespace = "promax.effects"'));
      expect(gradle, contains('com.google.mlkit:face-detection:'));
      final app = _read('android/app/build.gradle.kts');
      expect(app, contains('minSdk = maxOf(flutter.minSdkVersion, 23)'));
    });
  });
}
