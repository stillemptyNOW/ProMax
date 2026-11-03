import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:promax/core/config/app_design.dart';
import 'package:promax/core/config/app_stories.dart';
import 'package:promax/frontend/screens/chats/chat/view/chat_header.dart';
import 'package:promax/frontend/widgets/glossy_pill.dart';
import 'package:promax/l10n/app_localizations.dart';

void main() {
  for (final classic in [false, true]) {
    testWidgets(
      'the ${classic ? 'classic' : 'new'} header keeps navigation and contact actions',
      (tester) async {
        AppDesign.classic.value = classic;
        final previousStories = AppStories.current.value;
        AppStories.current.value = false;
        addTearDown(() {
          AppDesign.classic.value = false;
          AppStories.current.value = previousStories;
        });
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(320, 640);
        addTearDown(tester.view.reset);
        final status = ValueNotifier('Synthetic status');
        final scheduled = ValueNotifier(1);
        final unread = ValueNotifier(0);
        addTearDown(status.dispose);
        addTearDown(scheduled.dispose);
        addTearDown(unread.dispose);
        var closed = 0;
        var opened = 0;
        var called = 0;
        var menu = 0;
        await tester.pumpWidget(
          MaterialApp(
            locale: const Locale('en'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: Builder(
                builder: (context) => Align(
                  alignment: Alignment.topCenter,
                  child: SizedBox(
                    height: 76,
                    child: ChatHeaderRow(
                      glossy: true,
                      frosted: false,
                      cs: Theme.of(context).colorScheme,
                      embedded: true,
                      chatId: 101,
                      heroTag: 'synthetic-header',
                      name: 'Synthetic contact',
                      imageUrl: '',
                      chatType: 'CHAT',
                      isOfficial: false,
                      myId: 0,
                      headerStatus: status,
                      scheduledCount: scheduled,
                      otherUnread: unread,
                      showCall: true,
                      onClose: () => closed++,
                      onOpenInfo: () => opened++,
                      onOpenScheduled: () {},
                      onCall: () => called++,
                      onMenu: (_) => menu++,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        expect(tester.takeException(), isNull);
        expect(find.byType(GlossyPill), findsNWidgets(classic ? 3 : 1));
        await tester.tap(find.text('Synthetic contact'));
        await tester.tap(find.byIcon(Symbols.call));
        await tester.tap(find.byIcon(Symbols.more_vert));
        await tester.tap(find.byIcon(Symbols.close));
        expect([opened, called, menu, closed], [1, 1, 1, 1]);
      },
    );
  }
}
