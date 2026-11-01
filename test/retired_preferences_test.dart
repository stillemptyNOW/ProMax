import 'package:flutter_test/flutter_test.dart';
import 'package:promax/core/storage/retired_preferences.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('retired settings are dropped and the rest is kept', () async {
    SharedPreferences.setMockInitialValues({
      'promax_ignored_senders': '{"1001":[2002]}',
      'promax_streamer_mode': true,
      'promax_ghost_mode': true,
    });
    final prefs = await SharedPreferences.getInstance();
    await RetiredPreferences.purge(prefs);
    for (final key in RetiredPreferences.keys) {
      expect(prefs.containsKey(key), isFalse, reason: key);
    }
    expect(prefs.getBool('promax_ghost_mode'), isTrue);
  });
}
