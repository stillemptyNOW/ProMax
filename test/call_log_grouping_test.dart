import 'package:flutter_test/flutter_test.dart';
import 'package:promax/backend/modules/calls.dart';

CallLogEntry _call(String id, int peer, CallStatus status, DateTime time) =>
    CallLogEntry(
      id: id,
      accountId: 1,
      peerId: peer,
      name: 'Синтетический собеседник',
      status: status,
      time: time.millisecondsSinceEpoch,
    );

void main() {
  test('a grouped row remembers every call it stands for', () {
    final day = DateTime(2026, 3, 4, 12);
    final grouped = groupCallLog([
      _call('11', 7, CallStatus.missed, day),
      _call('12', 7, CallStatus.missed, day.subtract(const Duration(hours: 1))),
      _call('13', 7, CallStatus.missed, day.subtract(const Duration(hours: 2))),
      _call('14', 8, CallStatus.missed, day.subtract(const Duration(hours: 3))),
      _call('15', 8, CallStatus.missed, day.subtract(const Duration(days: 1))),
    ]);

    expect(grouped.map((c) => c.id), ['11', '14', '15']);
    expect(grouped.first.count, 3);
    expect(grouped.first.historyIds, ['11', '12', '13']);
    expect(grouped[1].historyIds, ['14']);
    expect(grouped[2].historyIds, ['15']);
  });

  test('different outcomes are never merged', () {
    final day = DateTime(2026, 3, 4, 12);
    final grouped = groupCallLog([
      _call('21', 7, CallStatus.missed, day),
      _call('22', 7, CallStatus.incoming, day),
    ]);

    expect(grouped.map((c) => c.historyIds), [
      ['21'],
      ['22'],
    ]);
  });
}
