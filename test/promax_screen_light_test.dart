import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promax/core/config/call_lighting.dart';
import 'package:promax/frontend/widgets/call_screen_light.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'legacy default light becomes wider but stays white at 75 percent',
    () async {
      SharedPreferences.setMockInitialValues({'call_light_width': 24.0});
      final value = await CallLighting.load();
      expect(value.width, 64);
      expect(value.brightness, 0.75);
      expect(value.color.toARGB32(), 0xffffffff);
      expect((await CallLighting.load()).width, 64);
    },
  );

  test('explicit customization survives migration and reload', () async {
    SharedPreferences.setMockInitialValues({'call_light_width': 50.0});
    expect((await CallLighting.load()).width, 50);
    await const CallLighting(width: 24).save();
    expect((await CallLighting.load()).width, 24);
  });

  testWidgets('light paints pure white edges and corners over a dark screen', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final key = GlobalKey();
    var taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: RepaintBoundary(
          key: key,
          child: GestureDetector(
            onTap: () => taps++,
            child: const ColoredBox(
              color: Colors.black,
              child: CallScreenLight(lighting: CallLighting()),
            ),
          ),
        ),
      ),
    );
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final data = await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 1);
      try {
        return await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      } finally {
        image.dispose();
      }
    });
    final bytes = data!.buffer.asUint8List();
    List<int> pixel(int x, int y) =>
        bytes.sublist((y * 320 + x) * 4, (y * 320 + x) * 4 + 4);
    expect(pixel(0, 0), [255, 255, 255, 255]);
    expect(pixel(32, 320), [255, 255, 255, 255]);
    expect(pixel(160, 320), [0, 0, 0, 255]);
    await tester.tapAt(const Offset(32, 320));
    expect(taps, 1);
  });
}
