import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promax/frontend/screens/chats/chat/view/conversation_tile.dart';

void main() {
  testWidgets('narrow conversation keeps preview and actions accessible', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(240, 640);
    addTearDown(tester.view.reset);
    var activated = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(2)),
            child: ConversationTile(
              avatar: const CircleAvatar(child: Text('S')),
              title: 'Synthetic conversation',
              preview: const Text('Synthetic message'),
              time: '12:34',
              muted: true,
              pinned: true,
              verified: true,
              indicator: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [Text('@'), SizedBox(width: 4), Text('99+')],
              ),
              action: IconButton(
                onPressed: () => activated = true,
                icon: const Icon(Icons.open_in_new),
              ),
            ),
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    expect(
      tester.getSize(find.text('Synthetic message')).width,
      greaterThan(0),
    );
    await tester.tap(find.byType(IconButton));
    expect(activated, isTrue);
  });

  for (final brightness in Brightness.values) {
    testWidgets(
      'conversation lanes preserve actions at large text in $brightness',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(320, 640);
        addTearDown(tester.view.reset);
        var activated = false;
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(
              colorScheme: ColorScheme.fromSeed(
                seedColor: Colors.indigo,
                brightness: brightness,
              ),
            ),
            home: Scaffold(
              body: MediaQuery(
                data: const MediaQueryData(textScaler: TextScaler.linear(2)),
                child: ConversationTile(
                  avatar: const CircleAvatar(child: Text('S')),
                  title: 'Synthetic conversation with a long title',
                  preview: const Text(
                    'A synthetic message preview',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  time: '12:34',
                  muted: true,
                  pinned: true,
                  verified: true,
                  indicator: const Text('99+'),
                  action: IconButton(
                    onPressed: () => activated = true,
                    icon: const Icon(Icons.open_in_new),
                  ),
                ),
              ),
            ),
          ),
        );
        expect(tester.takeException(), isNull);
        expect(
          find.text('Synthetic conversation with a long title'),
          findsOneWidget,
        );
        expect(find.text('99+'), findsOneWidget);
        await tester.tap(find.byType(IconButton));
        expect(activated, isTrue);
      },
    );
  }
}
