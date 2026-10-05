import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:promax/backend/modules/chats.dart';
import 'package:promax/backend/modules/messages.dart';
import 'package:promax/core/disappearing/disappearing_messages.dart';
import 'package:shared_preferences/shared_preferences.dart';

CachedMessage _message(String id, int sender, int time) => CachedMessage(
  id: id,
  accountId: 1,
  chatId: 9,
  senderId: sender,
  text: 'синтетика',
  time: time,
);

void main() {
  final service = DisappearingMessages.instance;
  late StreamController<MessageEvent> events;
  late List<(int, List<String>)> deleted;
  late bool succeed;
  var clock = DateTime(2026, 10, 6, 12);

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    events = StreamController<MessageEvent>.broadcast();
    deleted = [];
    succeed = true;
    clock = DateTime(2026, 10, 6, 12);
    service.now = () => clock;
    await service.start(
      events: events.stream,
      delete: (chatId, ids) async {
        deleted.add((chatId, ids));
        return succeed;
      },
      myId: () async => 1,
    );
  });

  tearDown(() async {
    await service.stop();
    await events.close();
  });

  Future<void> settle() => Future<void>.delayed(Duration.zero);

  test('own messages in a timed chat are deleted when due', () async {
    await service.setTimer(9, 30);
    final sentAt = clock.millisecondsSinceEpoch;
    events.add(MessageSentEvent(9, 'temp_1', _message('101', 1, sentAt)));
    events.add(MessageAddedEvent(9, _message('102', 1, sentAt)));
    events.add(MessageAddedEvent(9, _message('103', 2, sentAt)));
    await settle();
    await settle();
    expect(service.pending.map((e) => e.messageId).toSet(), {'101', '102'});

    await service.runDue();
    expect(deleted, isEmpty);

    clock = clock.add(const Duration(seconds: 31));
    await service.runDue();
    expect(deleted.single.$1, 9);
    expect(deleted.single.$2.toSet(), {'101', '102'});
    expect(service.pending, isEmpty);
  });

  test('untimed chats are ignored', () async {
    events.add(
      MessageSentEvent(
        5,
        'temp_2',
        _message('201', 1, clock.millisecondsSinceEpoch),
      ),
    );
    await settle();
    expect(service.pending, isEmpty);
  });

  test('failures retry and the queue survives a restart', () async {
    await service.setTimer(9, 30);
    succeed = false;
    await service.schedule(9, '301', clock.millisecondsSinceEpoch);
    clock = clock.add(const Duration(minutes: 1));
    await service.runDue();
    expect(service.pending.single.tries, 1);

    await service.stop();
    await service.start(
      events: events.stream,
      delete: (chatId, ids) async {
        deleted.add((chatId, ids));
        return true;
      },
      myId: () async => 1,
    );
    expect(service.timerFor(9), 30);
    clock = clock.add(const Duration(minutes: 2));
    await service.runDue();
    expect(service.pending, isEmpty);
    expect(deleted.last.$2, ['301']);
  });
}
