import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promax/core/config/app_performance.dart';
import 'package:promax/core/storage/chat_wallpaper_store.dart';
import 'package:promax/core/utils/app_foreground.dart';
import 'package:promax/frontend/widgets/chat_wallpaper_view.dart';
import 'package:promax/frontend/widgets/mesh_gradient_background.dart';

void main() {
  testWidgets('wallpaper motion releases the sensor while in background', (
    tester,
  ) async {
    final previous = AppPerformance.budget.value;
    addTearDown(() {
      AppPerformance.budget.value = previous;
      AppForeground.update(foreground: true);
    });
    var started = 0;
    var stopped = 0;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel('dev.fluttercommunity.plus/sensors/method'),
      (_) async => null,
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel('dev.fluttercommunity.plus/sensors/accelerometer'),
      (call) async {
        if (call.method == 'listen') started++;
        if (call.method == 'cancel') stopped++;
        return null;
      },
    );
    AppPerformance.budget.value = EffectBudget.high;
    AppForeground.update(foreground: true);
    final image = MemoryImage(
      base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/a7sAAAAASUVORK5CYII=',
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: WallpaperImageLayer(image: image, motion: true)),
      ),
    );
    await tester.pump();
    expect(started, 1);
    AppForeground.update(foreground: false);
    await tester.pump();
    expect(stopped, 1);
    AppForeground.update(foreground: true);
    await tester.pump();
    expect(started, 2);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    expect(stopped, 2);
  });

  testWidgets('animated chat wallpaper pauses in background and low budget', (
    tester,
  ) async {
    final previous = AppPerformance.budget.value;
    addTearDown(() {
      AppPerformance.budget.value = previous;
      AppForeground.update(foreground: true);
    });
    AppPerformance.budget.value = EffectBudget.high;
    AppForeground.update(foreground: true);
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ChatWallpaperView(
            wallpaper: ChatWallpaper.gradient([
              Colors.blue,
              Colors.purple,
            ], gradientAnimated: true),
          ),
        ),
      ),
    );
    bool animates() => tester
        .widget<MeshGradientBackground>(find.byType(MeshGradientBackground))
        .animate;
    expect(animates(), isTrue);
    AppForeground.update(foreground: false);
    await tester.pump();
    expect(animates(), isFalse);
    AppForeground.update(foreground: true);
    AppPerformance.budget.value = EffectBudget.low;
    await tester.pump();
    expect(animates(), isFalse);
    AppPerformance.budget.value = EffectBudget.high;
    await tester.pump();
    expect(animates(), isTrue);
  });
}
