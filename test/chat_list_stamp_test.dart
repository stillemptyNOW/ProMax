import 'package:flutter_test/flutter_test.dart';
import 'package:promax/core/utils/format.dart';

void main() {
  final now = DateTime(2026, 10, 6, 14, 0);

  test('chat list stamps follow the age of the message', () {
    expect(formatChatListStamp(DateTime(2026, 10, 6, 9, 5), now: now), '09:05');
    expect(
      formatChatListStamp(DateTime(2026, 10, 5, 23, 59), now: now),
      'Вчера',
    );
    expect(formatChatListStamp(DateTime(2026, 10, 2, 12), now: now), 'Пт');
    expect(formatChatListStamp(DateTime(2026, 9, 20, 12), now: now), '20 сен');
    expect(
      formatChatListStamp(DateTime(2025, 12, 31, 12), now: now),
      '31.12.25',
    );
  });
}
