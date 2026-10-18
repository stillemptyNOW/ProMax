import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:promax/core/transport/network_watch.dart';

void main() {
  testWidgets('a burst of network changes wakes the session once', (
    tester,
  ) async {
    final events = StreamController<Object?>();
    final watch = NetworkWatch(events: events.stream);
    var wakes = 0;
    watch.start(() => wakes++);

    events
      ..add('lost')
      ..add('available')
      ..add('available');
    await tester.pump(const Duration(milliseconds: 100));
    expect(wakes, 0);
    await tester.pump(const Duration(seconds: 1));
    expect(wakes, 1);

    events.add('lost');
    await tester.pump(const Duration(seconds: 1));
    expect(wakes, 1);
    expect(NetworkWatch.offline.value, isTrue);

    events.add('available');
    await tester.pump();
    expect(NetworkWatch.offline.value, isFalse);
    await tester.pump(const Duration(seconds: 1));
    expect(wakes, 2);

    watch.stop();
    unawaited(events.close());
  });
}
