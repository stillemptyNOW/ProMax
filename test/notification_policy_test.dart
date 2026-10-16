import 'package:flutter_test/flutter_test.dart';
import 'package:promax/backend/modules/account/account_models.dart';
import 'package:promax/backend/modules/chats.dart';
import 'package:promax/core/push/notification_policy.dart';

const int _me = 4242;
const int _peer = 5151;
const int _dialogId = 9000001;
const int _groupId = -1000000000077;

CachedChat _chat({
  required int id,
  String type = 'DIALOG',
  String? title,
  int dontDisturbUntil = 0,
}) => CachedChat(
  id: id,
  accountId: _me,
  type: type,
  title: title,
  unreadCount: 1,
  lastEventTime: 1700000000000,
  cachedAt: 0,
  dontDisturbUntil: dontDisturbUntil,
  isOnline: false,
  seenTime: 0,
  participants: const {_me: 1700000000000, _peer: 1700000000000},
);

PrivacyConfig _privacy({
  String chats = 'ON',
  bool details = true,
  String sound = 'oki.aiff',
  String calls = 'ON',
}) => PrivacyConfig.fromMap({
  'CHATS_PUSH_NOTIFICATION': chats,
  'PUSH_DETAILS': details,
  'CHATS_PUSH_SOUND': sound,
  'M_CALL_PUSH_NOTIFICATION': calls,
});

Map<String, Object?> _payload({
  int chatId = _dialogId,
  int sender = _peer,
  String text = 'synthetic hello',
  String? status,
  Object? postId,
}) => {
  'chatId': chatId,
  'postId': ?postId,
  'message': {
    'id': 77001,
    'sender': sender,
    'text': text,
    'time': 1700000000123,
    'status': ?status,
  },
};

MessagePush _push([Map<String, Object?>? payload]) =>
    NotificationPolicy.parseMessage(
      payload ?? _payload(),
      isHiddenChat: (_) => false,
    )!;

void main() {
  group('parseMessage', () {
    test('reads the kind from the message status', () {
      expect(_push().kind, MessagePushKind.created);
      expect(_push(_payload(status: 'EDITED')).kind, MessagePushKind.edited);
      expect(_push(_payload(status: 'REMOVED')).kind, MessagePushKind.removed);
      expect(_push().messageId, '77001');
      expect(_push().senderId, _peer);
    });

    test('drops hidden chats, channel posts and malformed payloads', () {
      expect(
        NotificationPolicy.parseMessage(
          _payload(),
          isHiddenChat: (id) => id == _dialogId,
        ),
        isNull,
      );
      expect(
        NotificationPolicy.parseMessage(
          _payload(postId: 12),
          isHiddenChat: (_) => false,
        ),
        isNull,
      );
      expect(
        NotificationPolicy.parseMessage({
          'chatId': '1',
          'message': {},
        }, isHiddenChat: (_) => false),
        isNull,
      );
      expect(
        NotificationPolicy.parseMessage(null, isHiddenChat: (_) => false),
        isNull,
      );
    });
  });

  test('parseDeletion accepts both chat shapes and skips empty ids', () {
    final nested = NotificationPolicy.parseDeletion({
      'chat': {'id': _groupId},
      'messageIds': [1, '', null, 'abc'],
    })!;
    expect(nested.chatId, _groupId);
    expect(nested.messageIds, ['1', 'abc']);

    final flat = NotificationPolicy.parseDeletion({
      'chatId': _dialogId,
      'messageIds': [5],
    })!;
    expect(flat.chatId, _dialogId);
    expect(NotificationPolicy.parseDeletion({'chatId': _dialogId}), isNull);
  });

  test('own messages are recognised by the active account', () {
    expect(NotificationPolicy.isOwn(_push(_payload(sender: _me)), _me), isTrue);
    expect(NotificationPolicy.isOwn(_push(), _me), isFalse);
    expect(NotificationPolicy.isOwn(_push(), null), isFalse);
  });

  group('compose', () {
    test('a dialog shows the sender and the text', () {
      final n = NotificationPolicy.compose(
        _push(),
        NotificationFacts(
          accountId: _me,
          privacy: _privacy(),
          chat: _chat(id: _dialogId, title: 'Dialog title'),
          senderName: 'Synthetic Peer',
        ),
      )!;
      expect(n.title, 'Synthetic Peer');
      expect(n.senderName, 'Synthetic Peer');
      expect(n.text, 'synthetic hello');
      expect(n.textVisible, isTrue);
      expect(n.isGroup, isFalse);
      expect(n.sound, isTrue);
      expect(n.toFkmData(), {
        'mc': '$_dialogId',
        'c': '$_me',
        'suid': '$_peer',
        'userName': 'Synthetic Peer',
        'title': 'Synthetic Peer',
        'msg': 'synthetic hello',
        'ctime': '1700000000123',
        'msgid': '77001',
      });
    });

    test('a group is titled by the chat', () {
      final n = NotificationPolicy.compose(
        _push(_payload(chatId: _groupId)),
        NotificationFacts(
          accountId: _me,
          chat: _chat(id: _groupId, type: 'CHAT', title: 'Synthetic group'),
          senderName: 'Synthetic Peer',
        ),
      )!;
      expect(n.title, 'Synthetic group');
      expect(n.senderName, 'Synthetic Peer');
      expect(n.isGroup, isTrue);
    });

    test('falls back to the chat title and then to MAX', () {
      final named = NotificationPolicy.compose(
        _push(),
        NotificationFacts(
          accountId: _me,
          chat: _chat(id: _dialogId, title: 'Dialog title'),
        ),
      )!;
      expect(named.title, 'Dialog title');
      final anonymous = NotificationPolicy.compose(
        _push(),
        const NotificationFacts(accountId: _me),
      )!;
      expect(anonymous.title, NotificationPolicy.fallbackSender);
    });

    test('muted chats, disabled notifications and own messages are silent', () {
      expect(
        NotificationPolicy.compose(
          _push(),
          NotificationFacts(
            accountId: _me,
            chat: _chat(id: _dialogId, dontDisturbUntil: -1),
          ),
        ),
        isNull,
      );
      expect(
        NotificationPolicy.compose(
          _push(),
          NotificationFacts(
            accountId: _me,
            privacy: _privacy(chats: 'OFF'),
          ),
        ),
        isNull,
      );
      expect(
        NotificationPolicy.compose(
          _push(_payload(sender: _me)),
          const NotificationFacts(accountId: _me),
        ),
        isNull,
      );
    });

    test('the text hides for privacy, streamer mode and encryption', () {
      for (final facts in [
        NotificationFacts(accountId: _me, privacy: _privacy(details: false)),
        const NotificationFacts(accountId: _me, streamerMode: true),
        const NotificationFacts(accountId: _me, encrypted: true),
      ]) {
        final n = NotificationPolicy.compose(_push(), facts)!;
        expect(n.text, NotificationPolicy.hiddenPreview);
        expect(n.textVisible, isFalse);
      }
    });

    test('sound follows the chats sound setting', () {
      final n = NotificationPolicy.compose(
        _push(),
        NotificationFacts(
          accountId: _me,
          privacy: _privacy(sound: ''),
        ),
      )!;
      expect(n.sound, isFalse);
    });

    test('a missing time is filled from the clock', () {
      final payload = _payload();
      (payload['message'] as Map).remove('time');
      final n = NotificationPolicy.compose(
        _push(payload),
        const NotificationFacts(accountId: _me),
        now: () => 1234,
      )!;
      expect(n.time, 1234);
    });
  });

  test('editedText respects the push privacy settings', () {
    final msg = {'text': ' edited text '};
    expect(NotificationPolicy.editedText(msg, null), 'edited text');
    expect(
      NotificationPolicy.editedText(msg, _privacy(details: false)),
      isNull,
    );
    expect(NotificationPolicy.editedText(msg, _privacy(chats: 'OFF')), isNull);
    expect(NotificationPolicy.editedText({'text': ''}, null), isNull);
  });

  test('calls follow the call notification setting', () {
    expect(NotificationPolicy.callsEnabled(null), isTrue);
    expect(NotificationPolicy.callsEnabled(_privacy(calls: 'OFF')), isFalse);
  });

  group('desktopAlert', () {
    const attended = WindowPresence(
      visible: true,
      minimized: false,
      focused: true,
    );

    test('an unattended window gets a toast', () {
      for (final presence in const [
        WindowPresence(visible: false, minimized: false, focused: false),
        WindowPresence(visible: true, minimized: true, focused: false),
        WindowPresence(visible: true, minimized: false, focused: false),
      ]) {
        expect(
          NotificationPolicy.desktopAlert(
            presence: presence,
            activeChatId: _dialogId,
            chatId: _dialogId,
          ),
          DesktopAlert.toast,
        );
      }
    });

    test('a focused window banners other chats and skips the open one', () {
      expect(
        NotificationPolicy.desktopAlert(
          presence: attended,
          activeChatId: _dialogId,
          chatId: _dialogId,
        ),
        DesktopAlert.none,
      );
      expect(
        NotificationPolicy.desktopAlert(
          presence: attended,
          activeChatId: _dialogId,
          chatId: _groupId,
        ),
        DesktopAlert.banner,
      );
      expect(
        NotificationPolicy.desktopAlert(
          presence: attended,
          activeChatId: 0,
          chatId: _groupId,
        ),
        DesktopAlert.banner,
      );
    });
  });
}
