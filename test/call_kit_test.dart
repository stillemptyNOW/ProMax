import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promax/core/calls/call_controller.dart';
import 'package:promax/core/calls/call_kit.dart';
import 'package:promax/core/calls/call_session.dart';
import 'package:promax/core/calls/ws2_signaling.dart';
import 'package:promax/core/utils/ids.dart';

const _conversation = '00000000-0000-4000-8000-000000000001';
const _otherConversation = '00000000-0000-4000-8000-000000000002';
const _callerName = 'Синтетический абонент';

Map<String, String> _callData({
  String conversationId = _conversation,
  String callerId = '101',
  String? name = _callerName,
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

CallSession _session() => CallSession(
  ws2Config: Ws2Config(uri: Uri.parse('wss://calls.invalid/ws2'), userId: 42),
  role: CallRole.callee,
);

class _FakeCalls extends Fake implements CallController {
  bool busy = false;
  CallSession? Function(Map<dynamic, dynamic> data) onAnswer = (_) => null;
  final List<Map<dynamic, dynamic>> rejected = [];

  @override
  bool get isBusy => busy;

  @override
  CallSession? get activeSession => null;

  @override
  CallSession? answerFromSystem(Map<dynamic, dynamic> data) => onAnswer(data);

  @override
  Future<void> rejectFromSystem(Map<dynamic, dynamic> data) async =>
      rejected.add(data);
}

class _NativeCallKit {
  static const _method = MethodChannel(
    'io.github.stillemptynow.promax/callkit',
  );
  static const _events = EventChannel(
    'io.github.stillemptynow.promax/callkit_events',
  );

  final List<MethodCall> calls = [];
  bool showsIncoming = true;
  MockStreamHandlerEventSink? _sink;

  TestDefaultBinaryMessenger get _messenger =>
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  void install() {
    _messenger.setMockMethodCallHandler(_method, (call) async {
      calls.add(call);
      return call.method == 'reportIncoming' ? showsIncoming : null;
    });
    _messenger.setMockStreamHandler(
      _events,
      MockStreamHandler.inline(onListen: (_, sink) => _sink = sink),
    );
  }

  void uninstall() {
    _messenger.setMockMethodCallHandler(_method, null);
    _messenger.setMockStreamHandler(_events, null);
  }

  Future<void> emit(Map<String, Object?> event) async {
    _sink!.success(event);
    await pumpEventQueue();
  }

  List<Object?> argumentsOf(String method) => [
    for (final call in calls)
      if (call.method == method) call.arguments,
  ];
}

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
  TestWidgetsFlutterBinding.ensureInitialized();

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
      expect(incoming.callerName, _callerName);
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

    test('leaves the name empty when the caller is unknown', () {
      final incoming = CallKitIncoming.fromData(_callData(name: null))!;

      expect(incoming.callerName, isEmpty);
      expect(incoming.toArguments()['name'], isEmpty);
      expect(incoming.toArguments()['handle'], '101');
    });

    test('takes the title when the user name is blank', () {
      final incoming = CallKitIncoming.fromData({
        ..._callData(name: null),
        'userName': ' ',
        'title': _callerName,
      })!;

      expect(incoming.callerName, _callerName);
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
      expect(args['name'], _callerName);
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

  group('CallEndCause', () {
    test('a hang-up is local and an aborted launch is a failure', () async {
      final hungUp = _session();
      final aborted = _session();

      await hungUp.hangup();
      await aborted.abort();

      expect(hungUp.endCause, CallEndCause.local);
      expect(aborted.endCause, CallEndCause.failed);
    });

    test('the first cause wins', () async {
      final session = _session();

      await session.hangup();
      await session.abort();

      expect(session.endCause, CallEndCause.local);
    });
  });

  group('CallKitBridge', () {
    late _NativeCallKit native;
    late _FakeCalls calls;
    late List<int> lookups;
    late String? resolvedName;
    late CallKitBridge bridge;

    setUp(() {
      native = _NativeCallKit()..install();
      calls = _FakeCalls();
      lookups = [];
      resolvedName = null;
      bridge = CallKitBridge.withCalls(
        calls,
        callerName: (userId) async {
          lookups.add(userId);
          return resolvedName;
        },
      )..init();
    });

    tearDown(() => native.uninstall());

    Future<void> answer() => native.emit({
      'action': 'answer',
      'conversationId': _conversation,
      'data': _callData(),
    });

    test('a repeated push for an answered call does not ring again', () async {
      expect(await bridge.reportIncoming(_callData()), isTrue);
      calls.onAnswer = (_) {
        calls.busy = true;
        return _session();
      };
      await answer();

      expect(await bridge.reportIncoming(_callData()), isTrue);
      expect(native.argumentsOf('reportIncoming'), hasLength(1));
    });

    test('another call while busy is left to the notification', () async {
      calls.busy = true;

      expect(
        await bridge.reportIncoming(
          _callData(conversationId: _otherConversation),
        ),
        isFalse,
      );
      expect(native.argumentsOf('reportIncoming'), isEmpty);
    });

    test(
      'an answer that cannot start ends the system call as failed',
      () async {
        await bridge.reportIncoming(_callData());
        calls.onAnswer = (_) => throw const FormatException('synthetic');

        await answer();

        expect(native.argumentsOf('endCall'), [
          {'conversationId': _conversation, 'reason': 'failed'},
        ]);
      },
    );

    test('a launch that fails after the answer ends as failed', () async {
      final session = _session();
      calls.onAnswer = (_) => session;
      await bridge.reportIncoming(_callData());
      await answer();

      await session.abort();
      await pumpEventQueue();

      expect(native.argumentsOf('endCall'), [
        {'conversationId': _conversation, 'reason': 'failed'},
      ]);
    });

    test('a hang-up in the app ends the system call locally', () async {
      final session = _session();
      calls.onAnswer = (_) => session;
      await bridge.reportIncoming(_callData());
      await answer();

      await session.hangup();
      await pumpEventQueue();

      expect(native.argumentsOf('endCall'), [
        {'conversationId': _conversation, 'reason': 'local'},
      ]);
    });

    test('a decline from the system screen rejects the call', () async {
      await bridge.reportIncoming(_callData());

      await native.emit({
        'action': 'decline',
        'conversationId': _conversation,
        'data': _callData(),
      });

      expect(calls.rejected, [_callData()]);
    });

    test(
      'an unknown caller rings with the handle, then shows the name',
      () async {
        resolvedName = _callerName;

        expect(await bridge.reportIncoming(_callData(name: null)), isTrue);
        await pumpEventQueue();

        expect(
          native.argumentsOf('reportIncoming').single,
          containsPair('name', ''),
        );
        expect(lookups, [101]);
        expect(native.argumentsOf('updateCall'), [
          {'conversationId': _conversation, 'name': _callerName},
        ]);
      },
    );

    test('an unresolved caller keeps the handle', () async {
      expect(await bridge.reportIncoming(_callData(name: null)), isTrue);
      await pumpEventQueue();

      expect(lookups, [101]);
      expect(native.argumentsOf('updateCall'), isEmpty);
    });

    test('a known caller is not looked up', () async {
      expect(await bridge.reportIncoming(_callData()), isTrue);
      await pumpEventQueue();

      expect(lookups, isEmpty);
      expect(native.argumentsOf('updateCall'), isEmpty);
    });

    test('a call the system did not show is not renamed', () async {
      native.showsIncoming = false;
      resolvedName = _callerName;

      expect(await bridge.reportIncoming(_callData(name: null)), isFalse);
      await pumpEventQueue();

      expect(lookups, isEmpty);
      expect(native.argumentsOf('updateCall'), isEmpty);
    });
  });
}
