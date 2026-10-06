import 'package:flutter_test/flutter_test.dart';
import 'package:promax/core/push/quiet_hours.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('windows cover overnight, daytime and weekday ranges', () {
    const night = QuietWindow(22, 8);
    expect(night.covers(DateTime(2026, 10, 6, 23)), isTrue);
    expect(night.covers(DateTime(2026, 10, 6, 7, 59)), isTrue);
    expect(night.covers(DateTime(2026, 10, 6, 8)), isFalse);
    const work = QuietWindow(9, 18, weekdaysOnly: true);
    expect(work.covers(DateTime(2026, 10, 6, 10)), isTrue);
    expect(work.covers(DateTime(2026, 10, 10, 10)), isFalse);
  });

  test('per-chat windows persist', () async {
    SharedPreferences.setMockInitialValues({});
    final service = QuietHours.instance;
    await service.set(-5, const QuietWindow(23, 7));
    service.windows.value = const {};
    await service.load();
    expect(service.windowFor(-5), const QuietWindow(23, 7));
    expect(service.isQuiet(-5, DateTime(2026, 10, 6, 3)), isTrue);
    expect(service.isQuiet(9, DateTime(2026, 10, 6, 3)), isFalse);
  });
}
