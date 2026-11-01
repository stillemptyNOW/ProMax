import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promax/core/config/app_chat_chrome.dart';
import 'package:promax/frontend/screens/chats/chat/chat_search_controller.dart';
import 'package:promax/frontend/screens/chats/chat/command_panel_controller.dart';
import 'package:promax/frontend/screens/chats/chat/mention_panel_controller.dart';
import 'package:promax/frontend/screens/chats/chat/video_note_controller.dart';
import 'package:promax/frontend/screens/chats/chat/view/chat_body_layout.dart';
import 'package:promax/frontend/widgets/promax_aura_background.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _atmosphereKey = ValueKey('atmosphere');
const _messagesKey = ValueKey('messages');

class _Harness extends StatefulWidget {
  const _Harness({required this.underlap});

  final bool underlap;

  @override
  State<_Harness> createState() => _HarnessState();
}

class _HarnessState extends State<_Harness> with TickerProviderStateMixin {
  late final mention = MentionPanelController(
    vsync: this,
    chatId: 1,
    enabled: () => false,
    selfId: () => 1,
    valueOf: () => TextEditingValue.empty,
    onSelected: (_, _) {},
  );
  late final command = CommandPanelController(
    vsync: this,
    textOf: () => '',
    onSelected: (_) {},
  );
  late final note = VideoNoteController(
    contextOf: () => context,
    isMounted: () => mounted,
    onRecorded: (File _, int _) async {},
    formatElapsed: (ms) => '$ms',
    bottomInset: () => 0,
  );
  late final search = ChatSearchController(chatId: 1, isMounted: () => mounted);
  final composerHeight = ValueNotifier<double>(0);
  final pinnedHeight = ValueNotifier<double>(0);

  @override
  Widget build(BuildContext context) => ChatBodyLayout(
    underlap: widget.underlap,
    cs: Theme.of(context).colorScheme,
    chat: null,
    effectiveChrome: ChatChromeStyle.color,
    liquidChrome: false,
    pillBackdrop: null,
    onJumpToPinnedMessage: () {},
    onUnpinCurrentMessage: null,
    onJoinCall: null,
    composerFrosted: false,
    composerHeight: composerHeight,
    pinnedBannerHeight: pinnedHeight,
    composerAreaBuilder: (_) => const SizedBox(height: 40),
    messagesArea: const SizedBox.expand(key: _messagesKey),
    atmosphere: const SizedBox.expand(key: _atmosphereKey),
    mentionPanel: mention,
    commandPanel: command,
    note: note,
    searchAnim: const AlwaysStoppedAnimation(0),
    search: search,
    onOpenSearchResult: (_) {},
    searchSenderName: (_) => '',
    searchSenderAvatar: (_) => null,
    chromeVignette: false,
    composerPaintsSurface: false,
    pinnedBannerTop: 0,
    defaultEdgeVignetteHeight: 0,
    wallpaper: null,
  );
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final underlap in [false, true]) {
    testWidgets('atmosphere sits between the background and the messages '
        '(underlap: $underlap)', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: _Harness(underlap: underlap)),
        ),
      );
      final stack = tester.widget<Stack>(
        find
            .ancestor(
              of: find.byKey(_messagesKey),
              matching: find.byType(Stack),
            )
            .first,
      );
      int indexOf(Finder finder) => stack.children.indexWhere(
        (child) =>
            find
                .descendant(of: find.byWidget(child), matching: finder)
                .evaluate()
                .isNotEmpty ||
            find
                .byWidget(child)
                .evaluate()
                .any((element) => finder.evaluate().contains(element)),
      );
      final background = indexOf(find.byType(ProMaxAuraBackground));
      final atmosphere = indexOf(find.byKey(_atmosphereKey));
      final messages = indexOf(find.byKey(_messagesKey));
      expect(background, isNonNegative);
      expect(atmosphere, background + 1);
      expect(messages, atmosphere + 1);
    });
  }
}
