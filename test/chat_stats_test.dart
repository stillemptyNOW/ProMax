import 'package:flutter_test/flutter_test.dart';
import 'package:promax/backend/modules/messages.dart';
import 'package:promax/core/stats/chat_stats.dart';

CachedMessage _m(
  String id,
  int sender,
  String text,
  DateTime time, {
  bool deleted = false,
}) => CachedMessage(
  id: id,
  accountId: 1,
  chatId: 3,
  senderId: sender,
  text: text,
  time: time.millisecondsSinceEpoch,
  deleted: deleted,
);

void main() {
  test('counts senders, hours, weekdays and frequent words', () {
    final stats = ChatStats.compute([
      _m('1', 1, 'Синтетика и синтетика', DateTime(2026, 9, 7, 10)),
      _m('2', 2, 'синтетика тест', DateTime(2026, 9, 7, 10, 30)),
      _m('3', 1, 'тест', DateTime(2026, 9, 8, 22)),
      _m('4', 2, 'удалено', DateTime(2026, 9, 8, 23), deleted: true),
    ]);
    expect(stats.total, 3);
    expect(stats.bySender, {1: 2, 2: 1});
    expect(stats.byHour[10], 2);
    expect(stats.byHour[22], 1);
    expect(stats.byWeekday[0], 2);
    expect(stats.byWeekday[1], 1);
    expect(stats.words, 6);
    expect(stats.topWords.first.key, 'синтетика');
    expect(stats.topWords.first.value, 3);
    expect(stats.busiestDayCount, 2);
    expect(stats.activeDays, 2);
    expect(stats.topSenders.first.key, 1);
  });

  test('empty history is safe', () {
    final stats = ChatStats.compute(const []);
    expect(stats.total, 0);
    expect(stats.perDay, 0);
    expect(stats.first, isNull);
  });
}
