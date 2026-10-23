import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promax/frontend/screens/calls/call_mask_sheet.dart';
import 'package:promax/l10n/app_localizations.dart';
import 'package:promax_effects/promax_effects.dart';

const _plugin = 'native/promax_effects';

List<Map<String, dynamic>> _manifest() {
  final file = File('$_plugin/${ProMaxMask.manifest}');
  final root = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
  return (root['masks'] as List).cast<Map<String, dynamic>>();
}

Set<String> _nativeAnchors() {
  final header = File('$_plugin/ios/Classes/MaskPose.h').readAsStringSync();
  return RegExp(
    r'\{"(\w+)", ProMaxMaskAnchor\w+\}',
  ).allMatches(header).map((match) => match.group(1)!).toSet();
}

(int, int) _pngSize(File file) {
  final bytes = file.readAsBytesSync();
  final data = ByteData.sublistView(bytes);
  expect(bytes.sublist(1, 4), utf8.encode('PNG'), reason: file.path);
  return (data.getUint32(16), data.getUint32(20));
}

Future<void> _pumpSheet(
  WidgetTester tester, {
  required ProMaxMask initial,
  required Future<bool> Function(ProMaxMask mask) onSelected,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('ru'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: Align(
          alignment: Alignment.bottomCenter,
          child: CallMaskSheet(initial: initial, onSelected: onSelected),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  group('mask manifest', () {
    test('lists every mask of the Dart enum and nothing else', () {
      final ids = _manifest().map((entry) => entry['id']).toList();
      expect(ids.toSet().length, ids.length);
      expect(ids, [
        for (final mask in ProMaxMask.values)
          if (mask != ProMaxMask.none) mask.id,
      ]);
    });

    test('points every artwork mask at its bundled image', () {
      final entries = {
        for (final entry in _manifest()) entry['id'] as String: entry,
      };
      for (final mask in ProMaxMask.values) {
        if (mask == ProMaxMask.none) continue;
        final entry = entries[mask.id]!;
        expect(entry['asset'], mask.asset, reason: mask.id);
        if (mask.asset == null) {
          expect(entry['effect'], 'pixelate', reason: mask.id);
          continue;
        }
        final (width, height) = _pngSize(File('$_plugin/${mask.assetPath}'));
        expect(width, inInclusiveRange(16, 512), reason: mask.id);
        expect(height, inInclusiveRange(16, 512), reason: mask.id);
      }
    });

    test('uses anchors and geometry the native tracker understands', () {
      final anchors = _nativeAnchors();
      expect(anchors, containsAll(['eyes', 'eachEye', 'forehead', 'nose']));
      for (final entry in _manifest()) {
        final id = entry['id'];
        expect(anchors, contains(entry['anchor']), reason: '$id');
        expect(entry['scale'], isA<num>(), reason: '$id');
        expect(entry['scale'] as num, greaterThan(0), reason: '$id');
        for (final key in ['offset', 'pivot']) {
          final value = entry[key];
          if (value == null) continue;
          expect(value, hasLength(2), reason: '$id $key');
          expect(value, everyElement(isA<num>()), reason: '$id $key');
        }
        final pivot = entry['pivot'] as List?;
        if (pivot != null) {
          expect(pivot, everyElement(inInclusiveRange(0, 1)), reason: '$id');
        }
      }
    });

    test('ships the artwork license with the plugin resources', () {
      final license = File(
        '$_plugin/${ProMaxMask.directory}/LICENSE-fluentui-emoji.txt',
      ).readAsStringSync();
      expect(license, contains('MIT License'));
      expect(license, contains('Copyright (c) Microsoft Corporation.'));
      final podspec = File(
        '$_plugin/ios/promax_effects.podspec',
      ).readAsStringSync();
      expect(podspec, contains("'Resources/masks/*.{png,json,txt}'"));
      final pubspec = File('$_plugin/pubspec.yaml').readAsStringSync();
      expect(pubspec, contains('- ${ProMaxMask.directory}/'));
    });
  });

  group('CallMaskSheet', () {
    testWidgets('applies a tapped mask and marks it selected', (tester) async {
      final applied = <ProMaxMask>[];
      await _pumpSheet(
        tester,
        initial: ProMaxMask.none,
        onSelected: (mask) async {
          applied.add(mask);
          return true;
        },
      );
      expect(find.text('Без маски'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey(ProMaxMask.sunglasses)));
      await tester.pumpAndSettle();
      expect(applied, [ProMaxMask.sunglasses]);
      expect(find.text('Солнечные очки'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey(ProMaxMask.sunglasses)));
      await tester.pumpAndSettle();
      expect(applied, [ProMaxMask.sunglasses]);
    });

    testWidgets('keeps the previous mask when applying fails', (tester) async {
      await _pumpSheet(
        tester,
        initial: ProMaxMask.none,
        onSelected: (_) async => false,
      );
      await tester.tap(find.byKey(const ValueKey(ProMaxMask.goggles)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Без маски'), findsOneWidget);
      expect(find.text('Не удалось включить эффект'), findsOneWidget);
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
    });
  });
}
