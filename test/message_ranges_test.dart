import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:promax/backend/modules/chats.dart';
import 'package:promax/backend/modules/messages.dart';
import 'package:promax/core/storage/app_database.dart';
import 'package:promax/core/storage/message_ranges.dart';
import 'package:promax/frontend/screens/chats/chat/chat_controller.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class _SyntheticPathProvider extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  final String directory;

  _SyntheticPathProvider(this.directory);

  @override
  Future<String?> getApplicationSupportPath() async => directory;
}

const _accountId = 1;
const _chatId = 700001;

MessageRange _r(int start, int end) => MessageRange(start, end);

Map<String, dynamic> _row(int n) => CachedMessage(
  id: '$n',
  accountId: _accountId,
  chatId: _chatId,
  senderId: 5,
  text: 'synthetic $n',
  time: n * 10,
  status: 'sent',
).toDbRow();

void main() {
  group('coverage of a history fetch', () {
    test('a full backward page covers from its oldest message to from', () {
      expect(
        MessageRanges.coverageOfFetch(
          fromTime: 500,
          forward: 0,
          backward: 3,
          times: [470, 480, 490],
        ),
        _r(470, 500),
      );
    });

    test('a short backward page reaches the start of the chat', () {
      expect(
        MessageRanges.coverageOfFetch(
          fromTime: 500,
          forward: 0,
          backward: 30,
          times: [470, 480],
        ),
        _r(0, 500),
      );
    });

    test('the latest page ends at its newest message, not in the future', () {
      expect(
        MessageRanges.coverageOfFetch(
          fromTime: null,
          forward: 0,
          backward: 3,
          times: [900, 910, 920],
        ),
        _r(900, 920),
      );
    });

    test('an empty latest page records nothing', () {
      expect(
        MessageRanges.coverageOfFetch(
          fromTime: null,
          forward: 0,
          backward: 50,
          times: const [],
        ),
        isNull,
      );
    });

    test('a window around a message spans both sides', () {
      expect(
        MessageRanges.coverageOfFetch(
          fromTime: 501,
          forward: 2,
          backward: 3,
          times: [480, 490, 500, 510, 520],
        ),
        _r(480, 520),
      );
    });

    test('a forward page starts at from', () {
      expect(
        MessageRanges.coverageOfFetch(
          fromTime: 500,
          forward: 3,
          backward: 0,
          times: [510, 520],
        ),
        _r(500, 520),
      );
    });
  });

  group('what a history answer proves deleted', () {
    const now = 1000000;
    const settled = now - 10000;

    MessageRange? window({
      int? fromTime,
      int forward = 0,
      int backward = 30,
      List<int> times = const [],
      bool emptyConfirmed = false,
    }) => MessageRanges.reconcileWindow(
      fromTime: fromTime,
      requestedAt: now,
      forward: forward,
      backward: backward,
      times: times,
      emptyConfirmed: emptyConfirmed,
    );

    test('a single empty answer proves nothing', () {
      expect(window(), isNull);
      expect(window(fromTime: 5000, backward: 2), isNull);
      expect(window(fromTime: 5000, forward: 2, backward: 0), isNull);
    });

    test('a confirmed empty latest history covers the whole chat', () {
      expect(window(emptyConfirmed: true), _r(0, settled));
    });

    test('a short latest history reaches back to the start', () {
      expect(window(times: [900000]), _r(0, settled));
    });

    test('a full latest page covers only back to its oldest message', () {
      expect(window(backward: 2, times: [800000, 900000]), _r(800000, settled));
    });

    test('messages sent while the request was in flight are spared', () {
      expect(window(times: [995000]), _r(0, 995000));
    });

    test('an older page stops just before the edge it was asked from', () {
      expect(
        window(fromTime: 5000, backward: 2, times: [3000, 4000]),
        _r(3000, 4999),
      );
      expect(
        window(fromTime: 5000, backward: 2, emptyConfirmed: true),
        _r(0, 4999),
      );
    });

    test('a newer page starts just after its edge', () {
      expect(
        window(fromTime: 5000, forward: 2, backward: 0, times: [6000, 7000]),
        _r(5001, 7000),
      );
      expect(
        window(fromTime: 5000, forward: 2, backward: 0, times: [6000]),
        _r(5001, settled),
      );
    });

    test('a full page around a message proves nothing outside it', () {
      expect(
        window(fromTime: 5000, forward: 1, backward: 1, times: [4000, 6000]),
        _r(4000, 6000),
      );
    });

    test('an empty newer page with no backward side proves nothing', () {
      expect(
        window(fromTime: 5000, forward: 0, backward: 0, emptyConfirmed: true),
        isNull,
      );
    });
  });

  group('merging ranges', () {
    test('touching ranges fuse, distant ones stay apart', () {
      final merged = MessageRanges.merge([
        _r(0, 100),
        _r(300, 400),
      ], _r(100, 200));
      expect(merged, [_r(0, 200), _r(300, 400)]);
    });

    test('a range bridging two others joins all three', () {
      final merged = MessageRanges.merge([
        _r(0, 100),
        _r(300, 400),
      ], _r(50, 350));
      expect(merged, [_r(0, 400)]);
    });
  });

  group('trusting pages', () {
    final ranges = MessageRanges([_r(100, 500), _r(800, 900)]);

    test('an older page inside the range is trusted', () {
      expect(
        ranges.coversOlderPage(
          edgeTime: 300,
          pageTimes: [290, 280, 270],
          limit: 3,
        ),
        isTrue,
      );
    });

    test('an older page crossing the start of the range is not', () {
      expect(
        ranges.coversOlderPage(
          edgeTime: 120,
          pageTimes: [110, 100, 60],
          limit: 3,
        ),
        isFalse,
      );
      expect(ranges.clipOlder([110, 100, 60], 120, (t) => t), [110, 100]);
    });

    test('a short older page is trusted only at the start of the chat', () {
      expect(
        ranges.coversOlderPage(edgeTime: 120, pageTimes: [110], limit: 3),
        isFalse,
      );
      expect(
        MessageRanges([
          _r(0, 500),
        ]).coversOlderPage(edgeTime: 120, pageTimes: [110], limit: 3),
        isTrue,
      );
    });

    test('a newer page may not jump over the hole to the next range', () {
      expect(
        ranges.coversNewerPage(
          edgeTime: 480,
          pageTimes: [490, 500, 810],
          limit: 3,
          newestKnownTime: 900,
        ),
        isFalse,
      );
      expect(ranges.clipNewer([490, 500, 810], 480, (t) => t), [490, 500]);
    });

    test('the latest page drops an island below the newest range', () {
      expect(ranges.clipLatest([900, 850, 800, 500, 400], (t) => t), [
        900,
        850,
        800,
      ]);
      expect(ranges.coversNewest(900), isTrue);
      expect(ranges.coversNewest(950), isFalse);
    });

    test('a window must sit inside one range and be complete', () {
      expect(
        ranges.coversWindow(
          centerTime: 300,
          windowTimes: [280, 290, 300, 310],
          before: 3,
          after: 1,
          newestKnownTime: 900,
        ),
        isTrue,
      );
      expect(
        ranges.coversWindow(
          centerTime: 490,
          windowTimes: [480, 490, 500, 810],
          before: 2,
          after: 2,
          newestKnownTime: 900,
        ),
        isFalse,
      );
    });
  });

  group('stored ranges', () {
    TestWidgetsFlutterBinding.ensureInitialized();

    setUp(() async {
      final directory = Directory.systemTemp.createTempSync(
        'synthetic_message_ranges_test',
      );
      PathProviderPlatform.instance = _SyntheticPathProvider(directory.path);
      addTearDown(() async {
        await AppDatabase.close();
        if (directory.existsSync()) directory.deleteSync(recursive: true);
      });
      await AppDatabase.init();
      await AppDatabase.saveProfile(
        ProfileData(
          id: _accountId,
          firstName: 'Synthetic owner',
          phone: 100000,
          country: 'ZZ',
          accountStatus: 0,
          updateTime: 1,
        ),
      );
      await chats.cacheServerChat({
        'id': _chatId,
        'type': 'CHAT',
        'status': 'ACTIVE',
        'title': 'Synthetic group',
        'participants': {'$_accountId': 0},
      }, _accountId);
    });

    test('ranges merge as they are recorded', () async {
      await AppDatabase.addMessageRange(_accountId, _chatId, _r(100, 200));
      await AppDatabase.addMessageRange(_accountId, _chatId, _r(500, 600));
      await AppDatabase.addMessageRange(_accountId, _chatId, _r(200, 300));

      final ranges = await AppDatabase.loadMessageRanges(_accountId, _chatId);
      expect(ranges.ranges, [_r(100, 300), _r(500, 600)]);
    });

    test(
      'a live message extends only a range that reached the last one',
      () async {
        await AppDatabase.addMessageRange(_accountId, _chatId, _r(100, 300));

        await AppDatabase.extendMessageRange(
          _accountId,
          _chatId,
          previousLastTime: 400,
          time: 410,
        );
        expect(
          (await AppDatabase.loadMessageRanges(_accountId, _chatId)).ranges,
          [_r(100, 300)],
        );

        await AppDatabase.extendMessageRange(
          _accountId,
          _chatId,
          previousLastTime: 300,
          time: 310,
        );
        expect(
          (await AppDatabase.loadMessageRanges(_accountId, _chatId)).ranges,
          [_r(100, 310)],
        );
      },
    );

    test('clearing the history forgets its ranges', () async {
      await AppDatabase.addMessageRange(_accountId, _chatId, _r(100, 300));
      await AppDatabase.clearMessages(_accountId, _chatId);

      expect(
        (await AppDatabase.loadMessageRanges(_accountId, _chatId)).isEmpty,
        isTrue,
      );
    });

    test('scrolling up stops at a hole instead of joining an island', () async {
      await AppDatabase.saveMessages([
        for (var n = 1; n <= 20; n++) _row(n),
        for (var n = 60; n <= 100; n++) _row(n),
      ]);
      await AppDatabase.addMessageRange(_accountId, _chatId, _r(10, 200));
      await AppDatabase.addMessageRange(_accountId, _chatId, _r(600, 1000));

      final controller = ChatController()
        ..myId = _accountId
        ..chatId = _chatId;
      addTearDown(controller.dispose);
      final latest = await controller.loadInitialFromDb(onlyVisible: true);
      controller.messages = latest.reversed.toList();

      expect(controller.latestCovered, isTrue);
      expect(controller.messages.first.time, 600);
      expect(controller.messages.last.time, 1000);

      await controller.loadMoreHistory(
        onLoadingStarted: () {},
        onLoaded: (_) {},
        onError: (_) {},
        pageSize: 30,
      );

      expect(controller.messages.first.time, 600);
      expect(controller.messages.any((m) => m.time < 600), isFalse);
      expect(controller.hasMoreHistory, isTrue);
    });
  });
}
