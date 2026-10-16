import 'package:flutter_test/flutter_test.dart';
import 'package:promax/backend/modules/chat_activity_sender.dart';
import 'package:promax/core/storage/chat_activity_store.dart';

void main() {
  group('ChatActivitySender', () {
    late List<ChatActivity> sent;
    late int clock;
    late bool allowed;
    late ChatActivitySender sender;

    setUp(() {
      sent = [];
      clock = 0;
      allowed = true;
      sender = ChatActivitySender(
        sent.add,
        allowed: () => allowed,
        now: () => clock,
      );
    });

    tearDown(() => sender.dispose());

    test('typing goes out at most once per interval', () {
      sender.pulse(ChatActivity.typing);
      clock = 1000;
      sender.pulse(ChatActivity.typing);
      clock = 3999;
      sender.pulse(ChatActivity.typing);
      expect(sent, [ChatActivity.typing]);
      clock = 4000;
      sender.pulse(ChatActivity.typing);
      expect(sent, [ChatActivity.typing, ChatActivity.typing]);
    });

    test('reset lets the next keystroke announce typing again', () {
      sender.pulse(ChatActivity.typing);
      sender.reset();
      clock = 10;
      sender.pulse(ChatActivity.typing);
      expect(sent, [ChatActivity.typing, ChatActivity.typing]);
    });

    test('nothing leaves when typing status is turned off', () {
      allowed = false;
      sender.pulse(ChatActivity.typing);
      sender.hold(ChatActivity.recordingVoice);
      expect(sent, isEmpty);
    });

    testWidgets('a held recording repeats until released', (tester) async {
      sender.hold(ChatActivity.recordingVoice);
      sender.pulse(ChatActivity.typing);
      expect(sent, [ChatActivity.recordingVoice]);
      await tester.pump(const Duration(seconds: 4));
      await tester.pump(const Duration(seconds: 4));
      expect(sent, List.filled(3, ChatActivity.recordingVoice));
      sender.release(ChatActivity.recordingVoice);
      await tester.pump(const Duration(seconds: 8));
      expect(sent, hasLength(3));
    });
  });

  test('peer activity types map to their labels, unknown means typing', () {
    expect(chatActivityFromType('STICKER'), ChatActivity.sticker);
    expect(chatActivityFromType('AUDIO'), ChatActivity.recordingVoice);
    expect(chatActivityFromType('VIDEO'), ChatActivity.recordingVideoNote);
    expect(chatActivityFromType('FILE'), ChatActivity.sendingFile);
    expect(chatActivityFromType('PHOTO'), ChatActivity.sendingPhoto);
    expect(chatActivityFromType('TEXT'), ChatActivity.typing);
    expect(chatActivityFromType('SOMETHING_NEW'), ChatActivity.typing);
    expect(chatActivityFromType(null), ChatActivity.typing);
  });

  test('typing outranks other activities, voice outranks stickers', () {
    final store = ChatActivityStore.withClock(() => 0);
    store.mark(1, 10, ChatActivity.sticker);
    store.mark(1, 11, ChatActivity.recordingVoice);
    expect(store.activity(1), ChatActivity.recordingVoice);
    store.mark(1, 12, ChatActivity.typing);
    expect(store.snapshot(1)!.userIds, [12]);
    store.clearChat(1);
  });
}
