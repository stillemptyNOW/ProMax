import 'package:flutter_test/flutter_test.dart';
import 'package:promax/core/calls/call_kit.dart';
import 'package:promax/core/utils/ids.dart';

const _conversation = '00000000-0000-4000-8000-000000000001';
const _otherConversation = '00000000-0000-4000-8000-000000000002';

Map<String, String> _callData({
  String conversationId = _conversation,
  String callerId = '101',
  String? name = 'Синтетический абонент',
  String iv = 'false',
  String vcp = '10:c3ludGhldGlj',
}) => {
  'type': 'InboundCall',
  'vcp': vcp,
  'conversationId': conversationId,
  'callerId': callerId,
  'suid': callerId,
  'userName': ?name,
  'title': ?name,
  'c': '1',
  'iv': iv,
};

Map<String, Object?> _messagePush(
  Map<String, Object?> attach, {
  String? status,
}) => {
  'chatId': 7,
  'message': {
    'id': 1,
    'sender': 101,
    'status': ?status,
    'attaches': [attach],
  },
};

void main() {
  group('uuidV5', () {
    test('matches the RFC 4122 reference vector', () {
      expect(
        uuidV5('6ba7b810-9dad-11d1-80b4-00c04fd430c8', 'www.example.com'),
        '2ed6657d-e927-568b-95e1-2665a8aea6a2',
      );
    });

    test('rejects a malformed namespace', () {
      expect(() => uuidV5('not-a-uuid', 'name'), throwsFormatException);
    });
  });

  group('callKitUuid', () {
    test(
      'is stable for one conversation and distinct across conversations',
      () {
        expect(callKitUuid(_conversation), callKitUuid(_conversation));
        expect(
          callKitUuid(_conversation),
          isNot(callKitUuid(_otherConversation)),
        );
      },
    );

    test('is a version 5 RFC 4122 UUID', () {
      expect(
        callKitUuid(_conversation),
        matches(
          RegExp(
            r'^[0-9a-f]{8}-[0-9a-f]{4}-5[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
          ),
        ),
      );
    });
  });

  group('CallKitIncoming', () {
    test('reads the live connection call payload', () {
      final incoming = CallKitIncoming.fromData(_callData())!;

      expect(incoming.conversationId, _conversation);
      expect(incoming.handle, '101');
      expect(incoming.callerName, 'Синтетический абонент');
      expect(incoming.isVideo, isFalse);
      expect(incoming.uuid, callKitUuid(_conversation));
    });

    test('detects video calls', () {
      expect(CallKitIncoming.fromData(_callData(iv: 'true'))!.isVideo, isTrue);
      expect(CallKitIncoming.fromData(_callData(iv: '1'))!.isVideo, isTrue);
      expect(
        CallKitIncoming.fromData({..._callData(), 'type': 'VIDEO'})!.isVideo,
        isTrue,
      );
    });

    test('falls back to the caller id when there is no name', () {
      final incoming = CallKitIncoming.fromData(_callData(name: null))!;

      expect(incoming.callerName, '101');
    });

    test('rejects payloads that cannot be answered', () {
      expect(CallKitIncoming.fromData(_callData(vcp: '')), isNull);
      expect(CallKitIncoming.fromData(_callData(conversationId: ' ')), isNull);
      expect(
        CallKitIncoming.fromData(
          Map.of(_callData())
            ..remove('callerId')
            ..remove('suid'),
        ),
        isNull,
      );
    });

    test('hands the original payload to the native side', () {
      final args = CallKitIncoming.fromData(
        _callData(iv: 'true'),
      )!.toArguments();

      expect(args['uuid'], callKitUuid(_conversation));
      expect(args['conversationId'], _conversation);
      expect(args['handle'], '101');
      expect(args['name'], 'Синтетический абонент');
      expect(args['video'], isTrue);
      expect(args['data'], _callData(iv: 'true'));
    });
  });

  group('FinishedCallRecord', () {
    Map<String, Object?> callAttach({
      String? hangupType = 'CANCELED',
      Object? duration = 0,
      String? conversationId = _conversation,
    }) => {
      '_type': 'CALL',
      'callType': 'AUDIO',
      'conversationId': ?conversationId,
      'hangupType': ?hangupType,
      'duration': duration,
    };

    test('reads the call record of a finished conversation', () {
      final record = FinishedCallRecord.fromPush(_messagePush(callAttach()))!;

      expect(record.conversationId, _conversation);
      expect(record.hangupType, 'CANCELED');
      expect(record.durationMs, 0);
    });

    test('ignores records without an outcome', () {
      expect(
        FinishedCallRecord.fromPush(_messagePush(callAttach(hangupType: null))),
        isNull,
      );
      expect(
        FinishedCallRecord.fromPush(
          _messagePush(callAttach(conversationId: null)),
        ),
        isNull,
      );
    });

    test('ignores ordinary and removed messages', () {
      expect(
        FinishedCallRecord.fromPush(
          _messagePush({'_type': 'PHOTO', 'photoId': 1}),
        ),
        isNull,
      );
      expect(
        FinishedCallRecord.fromPush(
          _messagePush(callAttach(), status: 'REMOVED'),
        ),
        isNull,
      );
      expect(FinishedCallRecord.fromPush('not a map'), isNull);
      expect(FinishedCallRecord.fromPush({'chatId': 7}), isNull);
    });

    test('maps the outcome to the CallKit end reason', () {
      CallKitEndReason reason(String type, {int duration = 0}) =>
          FinishedCallRecord.fromPush(
            _messagePush(callAttach(hangupType: type, duration: duration)),
          )!.endReason;

      expect(reason('CANCELED'), CallKitEndReason.remoteEnded);
      expect(reason('MISSED'), CallKitEndReason.unanswered);
      expect(reason('REJECTED'), CallKitEndReason.declinedElsewhere);
      expect(
        reason('HUNGUP', duration: 4200),
        CallKitEndReason.answeredElsewhere,
      );
      expect(reason('HUNGUP'), CallKitEndReason.remoteEnded);
    });
  });

  group('CallKitEvent', () {
    test('parses an answer with the call payload', () {
      final event = CallKitEvent.parse({
        'action': 'answer',
        'conversationId': _conversation,
        'data': {'vcp': '10:c3ludGhldGlj', 'callerId': 101, 'skip': null},
      })!;

      expect(event.action, CallKitAction.answer);
      expect(event.conversationId, _conversation);
      expect(event.data, {'vcp': '10:c3ludGhldGlj', 'callerId': '101'});
    });

    test('parses mute and hold flags', () {
      final mute = CallKitEvent.parse({
        'action': 'mute',
        'conversationId': _conversation,
        'muted': true,
      })!;
      final hold = CallKitEvent.parse({
        'action': 'hold',
        'conversationId': _conversation,
        'onHold': true,
      })!;

      expect(mute.action, CallKitAction.mute);
      expect(mute.muted, isTrue);
      expect(mute.onHold, isFalse);
      expect(hold.action, CallKitAction.hold);
      expect(hold.onHold, isTrue);
    });

    test('rejects unknown actions and missing conversations', () {
      expect(
        CallKitEvent.parse({'action': 'dial', 'conversationId': _conversation}),
        isNull,
      );
      expect(CallKitEvent.parse({'action': 'answer'}), isNull);
      expect(
        CallKitEvent.parse({'action': 'answer', 'conversationId': ''}),
        isNull,
      );
      expect(CallKitEvent.parse('answer'), isNull);
    });
  });

  group('CallKitRegistry', () {
    test('tracks a ringing call until it settles', () {
      final registry = CallKitRegistry();

      expect(registry.isKnown(_conversation), isFalse);
      registry.ring(_conversation);
      expect(registry.isKnown(_conversation), isTrue);
      expect(registry.settle(_conversation), isTrue);
      expect(registry.settle(_conversation), isFalse);
      expect(registry.isKnown(_conversation), isTrue);
    });

    test('forgets a call that was never shown', () {
      final registry = CallKitRegistry()..ring(_conversation);

      registry.forget(_conversation);

      expect(registry.isKnown(_conversation), isFalse);
      expect(registry.settle(_conversation), isFalse);
    });

    test('remembers only the latest settled calls', () {
      final registry = CallKitRegistry(memory: 2);

      registry
        ..settle('first')
        ..settle('second')
        ..settle('third');

      expect(registry.isKnown('first'), isFalse);
      expect(registry.isKnown('second'), isTrue);
      expect(registry.isKnown('third'), isTrue);
    });
  });
}
