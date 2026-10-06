import 'package:flutter_test/flutter_test.dart';
import 'package:promax/core/reminders/message_reminders.dart';
import 'package:promax/core/reminders/reminder_scheduler.dart';
import 'package:promax/core/utils/format.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeScheduler implements ReminderScheduler {
  _FakeScheduler({this.permitted = true});

  final bool permitted;
  final scheduled = <int>[];
  final cancelled = <int>[];

  @override
  Future<bool> ensurePermission() async => permitted;

  @override
  Future<void> schedule(MessageReminder reminder) async =>
      scheduled.add(reminder.id);

  @override
  Future<void> cancel(int id) async => cancelled.add(id);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    MessageReminders.instance.resetForTest();
  });

  Future<MessageReminder?> addOne({
    String messageId = 'm1',
    Duration delay = const Duration(hours: 1),
  }) => MessageReminders.instance.add(
    chatId: -42,
    messageId: messageId,
    chatName: 'Синтетический чат',
    text: 'Синтетический текст',
    messageTime: 1,
    at: DateTime.now().add(delay),
  );

  test('a reminder is scheduled, persisted and replaced per message', () async {
    final scheduler = _FakeScheduler();
    MessageReminders.instance.scheduler = scheduler;

    final first = await addOne();
    final second = await addOne(delay: const Duration(hours: 2));

    expect(first, isNotNull);
    expect(second, isNotNull);
    expect(MessageReminders.instance.items.value, [second]);
    expect(scheduler.scheduled, [first!.id, second!.id]);
    expect(scheduler.cancelled, [first.id]);

    MessageReminders.instance.resetForTest();
    await MessageReminders.instance.load();
    final restored = MessageReminders.instance.find(-42, 'm1');
    expect(restored?.at, second.at);
    expect(restored?.chatName, 'Синтетический чат');
  });

  test('nothing is stored when notifications are not allowed', () async {
    MessageReminders.instance.scheduler = _FakeScheduler(permitted: false);
    expect(await addOne(), isNull);
    expect(MessageReminders.instance.items.value, isEmpty);
  });

  test('a due reminder fires in the app and leaves the list', () async {
    final fired = <MessageReminder>[];
    final sub = MessageReminders.instance.due.listen(fired.add);
    addTearDown(sub.cancel);

    await addOne(delay: const Duration(milliseconds: 20));
    await Future<void>.delayed(const Duration(milliseconds: 80));

    expect(fired.single.messageId, 'm1');
    expect(MessageReminders.instance.items.value, isEmpty);
  });

  test('expired reminders are dropped on load', () async {
    SharedPreferences.setMockInitialValues({
      MessageReminders.prefKey:
          '[{"id":1,"c":-1,"m":"old","n":"","t":"","mt":0,"at":1000}]',
    });
    await MessageReminders.instance.load();
    expect(MessageReminders.instance.items.value, isEmpty);
  });

  test('presets stay in the future and skip a passed evening', () {
    final late = DateTime(2026, 10, 6, 22, 30);
    final presets = ReminderPreset.forNow(late);
    expect(presets.every((p) => p.at.isAfter(late)), isTrue);
    expect(presets.any((p) => p.label.contains('19:00')), isFalse);
    expect(
      presets.firstWhere((p) => p.label.contains('понедельник')).at,
      DateTime(2026, 10, 12, 9),
    );
  });

  test('reminder stamps read naturally', () {
    final now = DateTime(2026, 10, 6, 12);
    expect(
      formatReminderStamp(DateTime(2026, 10, 6, 19), now: now),
      'сегодня в 19:00',
    );
    expect(
      formatReminderStamp(DateTime(2026, 10, 7, 9), now: now),
      'завтра в 09:00',
    );
    expect(
      formatReminderStamp(DateTime(2026, 10, 9, 9), now: now),
      'пт в 09:00',
    );
    expect(
      formatReminderStamp(DateTime(2027, 1, 2, 8, 5), now: now),
      '2 янв 2027 в 08:05',
    );
  });

  test('notification payload round-trips the chat', () {
    final reminder = MessageReminder(
      id: 7,
      chatId: -5,
      messageId: 'x',
      chatName: '',
      text: '',
      messageTime: 0,
      at: 0,
    );
    expect(reminderChatFromPayload(reminderPayload(reminder)), -5);
    expect(reminderChatFromPayload('{"type":"other","chat":1}'), isNull);
    expect(reminderChatFromPayload('not json'), isNull);
  });
}
