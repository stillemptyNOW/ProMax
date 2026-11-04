import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promax/core/hub/hub_client.dart';
import 'package:promax/core/hub/hub_content.dart';
import 'package:promax/core/hub/hub_inbox.dart';
import 'package:promax/frontend/screens/promax_hub/service_chat_screen.dart';
import 'package:promax/frontend/widgets/hub/hub_announcement_card.dart';
import 'package:promax/l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Client extends HubClient {
  _Client(this.feed);
  List<HubMessage> feed;
  @override
  Future<List<HubMessage>> messages({int after = 0}) async => [
    for (final message in feed)
      if (message.id > after) message,
  ];
}

Widget _host(Widget child) => MaterialApp(
  locale: const Locale('en'),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(body: child),
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('old server messages decode with default meta', () {
    final message = HubMessage.fromJson({
      'id': 1,
      'text': 'synthetic',
      'created': 5,
    });
    expect(message.meta, HubMeta.plain);
    expect(message.meta.hasButton, isFalse);
  });

  test('meta survives a json round trip and unknown kinds fall back', () {
    const meta = HubMeta(
      kind: HubKind.promo,
      title: 'Synthetic',
      buttonLabel: 'Go',
      buttonUrl: 'https://example.test',
    );
    final back = HubMessage.fromJson(
      HubMessage(id: 2, text: 't', created: 1, meta: meta).toJson(),
    );
    expect(back.meta, meta);
    expect(back.meta.hasButton, isTrue);
    expect(HubMeta.fromJson({'kind': 'unknown_kind'}).kind, HubKind.news);
  });

  test('rich text parses bold, links and bullets', () {
    final blocks = HubRichText.parse(
      '**Hi** [site](https://example.test)\n- one\n\n- two',
    );
    expect(blocks.length, 3);
    expect(blocks[0].spans.first.style, HubSpanStyle.bold);
    expect(blocks[0].spans.last.url, 'https://example.test');
    expect(blocks[1].bullet, isTrue);
    expect(HubRichText.plain('**Hi** there'), 'Hi there');
  });

  testWidgets('card shows type, title, unread dot, pin and button', (
    tester,
  ) async {
    var pressed = 0;
    await tester.pumpWidget(
      _host(
        HubAnnouncementCard(
          text: '**Bold** body',
          meta: const HubMeta(
            kind: HubKind.important,
            title: 'Synthetic title',
            buttonLabel: 'Open it',
            buttonUrl: 'https://example.test',
          ),
          footer: 'now',
          unread: true,
          pinned: true,
          onAction: () => pressed++,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Important'), findsOneWidget);
    expect(find.text('Synthetic title'), findsOneWidget);
    expect(find.byKey(const ValueKey('hub_unread_dot')), findsOneWidget);
    await tester.tap(find.text('Open it'));
    expect(pressed, 1);
  });

  testWidgets('feed groups by day, hides and mutes from the menu', (
    tester,
  ) async {
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final inbox = HubInbox(
      accountId: 1,
      phone: 2,
      client: _Client([
        HubMessage(id: 1, text: 'synthetic first', created: now),
        HubMessage(
          id: 2,
          text: 'synthetic second',
          created: now,
          meta: const HubMeta(kind: HubKind.important),
        ),
      ]),
    );
    await inbox.init();
    expect(inbox.banner?.id, 2);
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: ServiceChatScreen(inbox: inbox, kind: ServiceChat.announcements),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Today'), findsOneWidget);
    await tester.longPress(find.text('synthetic first'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Hide'));
    await tester.pumpAndSettle();
    expect(find.text('synthetic first'), findsNothing);
    await inbox.setMuted(true);
    expect(inbox.banner, isNull);
    await tester.pumpWidget(const SizedBox());
    inbox.dispose();
  });
}
