import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promax/core/utils/save_file_as.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('io.github.stillemptynow.promax/media_export');
  late Directory dir;
  late File source;
  final calls = <MethodCall>[];

  setUp(() {
    dir = Directory.systemTemp.createTempSync('save_file_as_test');
    source = File('${dir.path}/cache_0001.bin')..writeAsBytesSync([1, 2, 3]);
    calls.clear();
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    dir.deleteSync(recursive: true);
  });

  void answer(Object? Function(MethodCall call) reply) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return reply(call);
        });
  }

  for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
    test('$platform hands the file to the system export sheet', () async {
      debugDefaultTargetPlatformOverride = platform;
      answer((_) => '/exported/photo.jpg');

      final result = await saveFileAs(
        source: source,
        fileName: 'photo.jpg',
        dialogTitle: 'Save',
      );

      expect(result.saved, isTrue);
      expect(result.path, '/exported/photo.jpg');
      expect(calls.single.method, 'saveAs');
      expect(calls.single.arguments, {
        'path': source.path,
        'name': 'photo.jpg',
      });
    });
  }

  test('a dismissed export sheet counts as cancelled', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    answer((_) => null);

    final result = await saveFileAs(
      source: source,
      fileName: 'photo.jpg',
      dialogTitle: 'Save',
    );

    expect(result.saved, isFalse);
    expect(result.cancelled, isTrue);
  });

  test('a native export error is reported as a failure', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    answer((_) => throw PlatformException(code: 'EXPORT_FAILED'));

    final result = await saveFileAs(
      source: source,
      fileName: 'photo.jpg',
      dialogTitle: 'Save',
    );

    expect(result.saved, isFalse);
    expect(result.cancelled, isFalse);
    expect(result.error, isNotNull);
  });
}
