import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:promax/core/config/app_message_actions_style.dart';
import 'package:promax/core/utils/format.dart';
import 'package:promax/frontend/widgets/message_actions_overlay.dart';
import 'package:promax/l10n/app_localizations.dart';

final AppLocalizations _ru = lookupAppLocalizations(const Locale('ru'));
final AppLocalizations _en = lookupAppLocalizations(const Locale('en'));

Future<MessageActionsController> _openMenu(
  WidgetTester tester, {
  MessageReadSummary? Function()? readSummary,
  Listenable? readRevision,
  Future<List<MessageReader>> Function()? loadReadBy,
  VoidCallback? onReply,
  MessageActionsInteraction interaction = MessageActionsInteraction.click,
}) async {
  final controller = MessageActionsController();
  addTearDown(controller.dispose);

  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('ru'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => showMessageActions(
              context: context,
              originRect: const Rect.fromLTWH(120, 160, 200, 40),
              tapPoint: const Offset(160, 180),
              isMe: true,
              messageText: 'синтетика',
              copyText: 'синтетика',
              controller: controller,
              style: MessageActionsStyle.list,
              interaction: interaction,
              readSummary: readSummary,
              readRevision: readRevision,
              loadReadBy: loadReadBy,
              onReply: onReply,
              onDispose: () {},
            ),
            child: const Text('open menu'),
          ),
        ),
      ),
    ),
  );

  await tester.tap(find.text('open menu'));
  await tester.pumpAndSettle();
  return controller;
}

int _todayAt(int hour, int minute) {
  final now = DateTime.now();
  return DateTime(
    now.year,
    now.month,
    now.day,
    hour,
    minute,
  ).millisecondsSinceEpoch;
}

void main() {
  group('formatReadStamp', () {
    final now = DateTime(2026, 10, 16, 18, 5);

    test('names today and yesterday', () {
      expect(
        formatReadStamp(_ru, DateTime(2026, 10, 16, 14, 32), now: now),
        'сегодня в 14:32',
      );
      expect(
        formatReadStamp(_ru, DateTime(2026, 10, 15, 9, 5), now: now),
        'вчера в 09:05',
      );
      expect(
        formatReadStamp(_en, DateTime(2026, 10, 15, 9, 5), now: now),
        'yesterday at 09:05',
      );
    });

    test('shows the date and only a foreign year', () {
      expect(
        formatReadStamp(_ru, DateTime(2026, 10, 12, 9, 15), now: now),
        '12 окт в 09:15',
      );
      expect(
        formatReadStamp(_ru, DateTime(2025, 10, 12, 9, 15), now: now),
        '12 окт 2025 в 09:15',
      );
      expect(
        formatReadStamp(_en, DateTime(2026, 3, 2, 21, 0), now: now),
        '2 Mar at 21:00',
      );
    });

    test('keeps yesterday across a daylight saving switch', () {
      expect(
        formatReadStamp(
          _ru,
          DateTime(2026, 3, 28, 23, 50),
          now: DateTime(2026, 3, 29, 0, 30),
        ),
        'вчера в 23:50',
      );
    });
  });

  testWidgets('without read data the menu has no read line', (tester) async {
    await _openMenu(tester, loadReadBy: () async => const []);

    expect(find.byIcon(Symbols.done_all), findsNothing);
    expect(find.text(_ru.msgActionsReadBy), findsOneWidget);
  });

  testWidgets('a dialog shows when the message was read on top', (
    tester,
  ) async {
    final text = _ru.readReceiptReadAt('сегодня в 14:32');
    var replied = 0;
    await _openMenu(
      tester,
      readSummary: () => MessageReadSummary.status(text, read: true),
      onReply: () => replied++,
    );

    final header = find.text(text);
    final reply = find.text(_ru.msgActionsReply);
    expect(header, findsOneWidget);
    expect(find.byIcon(Symbols.done_all), findsOneWidget);
    expect(tester.getCenter(header).dy, lessThan(tester.getCenter(reply).dy));

    await tester.tap(reply);
    await tester.pumpAndSettle();

    expect(replied, 1);
  });

  testWidgets('the read line follows a late read push', (tester) async {
    final revision = ValueNotifier(0);
    addTearDown(revision.dispose);
    await _openMenu(
      tester,
      readRevision: revision,
      readSummary: () => revision.value == 0
          ? MessageReadSummary.status(_ru.readReceiptNotRead, read: false)
          : MessageReadSummary.status(_ru.readReceiptReadUnknown, read: true),
    );

    expect(find.text(_ru.readReceiptNotRead), findsOneWidget);
    expect(find.byIcon(Symbols.done), findsOneWidget);

    revision.value++;
    await tester.pumpAndSettle();

    expect(find.text(_ru.readReceiptNotRead), findsNothing);
    expect(find.text(_ru.readReceiptReadUnknown), findsOneWidget);
    expect(find.byIcon(Symbols.done_all), findsOneWidget);
  });

  testWidgets('drag and release still lands on the shifted items', (
    tester,
  ) async {
    var replied = 0;
    final controller = await _openMenu(
      tester,
      interaction: MessageActionsInteraction.dragAndRelease,
      readSummary: () =>
          MessageReadSummary.status(_ru.readReceiptReadUnknown, read: true),
      onReply: () => replied++,
    );

    controller.initialPointer = const Offset(160, 180);
    controller.updatePointer(tester.getCenter(find.text(_ru.msgActionsReply)));
    await tester.pump();
    controller.commit();
    await tester.pumpAndSettle();

    expect(replied, 1);
  });

  testWidgets('a group line opens readers with their read time', (
    tester,
  ) async {
    final exact = _todayAt(14, 32);
    final bound = _todayAt(9, 15);
    await _openMenu(
      tester,
      readSummary: () => const MessageReadSummary.readers(2),
      loadReadBy: () async => [
        MessageReader(id: 11, name: 'Синтетик Один', readAt: exact),
        MessageReader(
          id: 12,
          name: 'Синтетик Два',
          readAt: bound,
          readAtMost: true,
        ),
        const MessageReader(id: 13, name: 'Синтетик Три'),
      ],
    );

    expect(find.text(_ru.readReceiptReadCount(2)), findsOneWidget);
    expect(find.text(_ru.msgActionsReadBy), findsNothing);
    expect(find.byIcon(Symbols.chevron_right), findsOneWidget);

    await tester.tap(find.text(_ru.readReceiptReadCount(2)));
    await tester.pumpAndSettle();

    expect(find.text('Синтетик Один'), findsOneWidget);
    expect(find.text('сегодня в 14:32'), findsOneWidget);
    expect(find.text(_ru.readReceiptTimeAtMost('сегодня в 09:15')), findsOne);
    expect(find.text(_ru.readReceiptTimeUnknown), findsOneWidget);

    await tester.tap(find.byIcon(Symbols.arrow_back));
    await tester.pumpAndSettle();

    expect(find.text(_ru.readReceiptReadCount(3)), findsOneWidget);
  });

  testWidgets('a group nobody has read says so', (tester) async {
    await _openMenu(
      tester,
      readSummary: () => const MessageReadSummary.readers(0),
      loadReadBy: () async => const [],
    );

    expect(find.text(_ru.msgActionsReadByEmpty), findsOneWidget);
    expect(find.byIcon(Symbols.done), findsOneWidget);
  });
}
