import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
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
  MessageActionsStyle style = MessageActionsStyle.list,
  Rect originRect = const Rect.fromLTWH(120, 160, 200, 40),
  Offset tapPoint = const Offset(160, 180),
  double bottomReservedSpace = 0,
  double textScale = 1,
}) async {
  final controller = MessageActionsController();
  addTearDown(controller.dispose);

  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('ru'),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => showMessageActions(
              context: context,
              originRect: originRect,
              tapPoint: tapPoint,
              bottomReservedSpace: bottomReservedSpace,
              isMe: true,
              messageText: 'синтетика',
              copyText: 'синтетика',
              controller: controller,
              style: style,
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

  testWidgets('the read line appears once the data arrives', (tester) async {
    final revision = ValueNotifier(0);
    addTearDown(revision.dispose);
    await _openMenu(
      tester,
      readRevision: revision,
      readSummary: () => revision.value == 0
          ? null
          : MessageReadSummary.status(_ru.readReceiptReadUnknown, read: true),
      onReply: () {},
    );
    final replyBefore = tester.getCenter(find.text(_ru.msgActionsReply)).dy;
    expect(find.text(_ru.readReceiptReadUnknown), findsNothing);

    revision.value++;
    await tester.pumpAndSettle();

    expect(find.text(_ru.readReceiptReadUnknown), findsOneWidget);
    expect(
      tester.getCenter(find.text(_ru.msgActionsReply)).dy,
      greaterThan(replyBefore),
    );
  });

  testWidgets('a deleted message leaves no empty read strip', (tester) async {
    final revision = ValueNotifier(0);
    addTearDown(revision.dispose);
    await _openMenu(
      tester,
      readRevision: revision,
      readSummary: () => revision.value == 0
          ? MessageReadSummary.status(_ru.readReceiptReadUnknown, read: true)
          : null,
      onReply: () {},
    );
    final replyBefore = tester.getCenter(find.text(_ru.msgActionsReply)).dy;
    expect(find.byType(Divider), findsOneWidget);

    revision.value++;
    await tester.pumpAndSettle();

    expect(find.text(_ru.readReceiptReadUnknown), findsNothing);
    expect(find.byType(Divider), findsNothing);
    expect(
      tester.getCenter(find.text(_ru.msgActionsReply)).dy,
      lessThanOrEqualTo(replyBefore - 40),
    );
  });

  testWidgets('large text keeps the whole read line and the hit targets', (
    tester,
  ) async {
    final text = _ru.readReceiptReadAtMost('12 окт 2025 в 14:32');
    var replied = 0;
    final controller = await _openMenu(
      tester,
      textScale: 2,
      interaction: MessageActionsInteraction.dragAndRelease,
      readSummary: () => MessageReadSummary.status(text, read: true),
      onReply: () => replied++,
    );

    final line = find.text(text);
    expect(line, findsOneWidget);
    final paragraph = tester.renderObject<RenderParagraph>(line);
    expect(
      paragraph.size.height,
      greaterThanOrEqualTo(
        paragraph.getMinIntrinsicHeight(paragraph.size.width),
      ),
    );
    expect(
      tester.getBottomLeft(line).dy,
      lessThanOrEqualTo(tester.getTopLeft(find.byType(Divider)).dy),
    );

    controller.initialPointer = const Offset(160, 180);
    controller.updatePointer(tester.getCenter(find.text(_ru.msgActionsReply)));
    await tester.pump();
    controller.commit();
    await tester.pumpAndSettle();

    expect(replied, 1);
  });

  testWidgets('the radial menu shows the read line clear of the buttons', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final text = _ru.readReceiptReadAt('сегодня в 14:32');
    final controller = await _openMenu(
      tester,
      style: MessageActionsStyle.radial,
      interaction: MessageActionsInteraction.dragAndRelease,
      originRect: const Rect.fromLTWH(150, 650, 230, 48),
      tapPoint: const Offset(300, 674),
      bottomReservedSpace: 60,
      readSummary: () => MessageReadSummary.status(text, read: true),
      onReply: () {},
    );

    final line = tester.getRect(find.text(text));
    for (final icon in [Symbols.reply, Symbols.content_copy]) {
      expect(tester.getRect(find.byIcon(icon)).overlaps(line), isFalse);
    }

    controller.initialPointer = const Offset(300, 674);
    controller.updatePointer(tester.getCenter(find.byIcon(Symbols.reply)));
    await tester.pumpAndSettle();

    expect(find.text(_ru.msgActionsReply), findsOneWidget);
    expect(find.text(text), findsNothing);
  });
}
