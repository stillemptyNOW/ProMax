import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promax/frontend/screens/chats/native/native_chat_list_bridge.dart';

NativeChatRow row(String id, {String title = 'Chat', int unread = 0}) =>
    NativeChatRow(
      id: id,
      title: title,
      preview: 'hello',
      time: '10:00',
    ).copyUnread(unread);

extension on NativeChatRow {
  NativeChatRow copyUnread(int value) => NativeChatRow(
    id: id,
    title: title,
    preview: preview,
    time: time,
    unread: value,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('NativeChatRow', () {
    test('serialises only the fields the native side needs', () {
      final json = const NativeChatRow(
        id: '1',
        title: 'Alice',
        preview: 'hi',
        time: '12:00',
        pinned: true,
        unread: 3,
      ).toJson();
      expect(json['id'], '1');
      expect(json['pinned'], true);
      expect(json['unread'], 3);
      expect(json['ownStatus'], isNull);
      expect(json.keys, hasLength(18));
    });

    test('equal rows compare equal', () {
      expect(row('1'), row('1'));
      expect(row('1'), isNot(row('1', unread: 1)));
    });
  });

  group('NativeChatListDiff', () {
    test('identical lists produce an empty diff', () {
      final diff = NativeChatListDiff.between(
        [row('1'), row('2')],
        [row('1'), row('2')],
      );
      expect(diff.isEmpty, isTrue);
    });

    test('changed row is upserted without reordering', () {
      final diff = NativeChatListDiff.between(
        [row('1'), row('2')],
        [row('1'), row('2', unread: 4)],
      );
      expect(diff.order, isNull);
      expect(diff.upsert.map((r) => r.id), ['2']);
      expect(diff.remove, isEmpty);
    });

    test('removed row is listed and order stays untouched', () {
      final diff = NativeChatListDiff.between(
        [row('1'), row('2'), row('3')],
        [row('1'), row('3')],
      );
      expect(diff.remove, ['2']);
      expect(diff.order, isNull);
      expect(diff.upsert, isEmpty);
    });

    test('new row sends the full order', () {
      final diff = NativeChatListDiff.between([row('1')], [row('9'), row('1')]);
      expect(diff.order, ['9', '1']);
      expect(diff.upsert.map((r) => r.id), ['9']);
    });

    test('moved row sends the order only', () {
      final diff = NativeChatListDiff.between(
        [row('1'), row('2')],
        [row('2'), row('1')],
      );
      expect(diff.order, ['2', '1']);
      expect(diff.upsert, isEmpty);
    });
  });

  group('NativeChatListAction', () {
    test('parses valid actions', () {
      final action = NativeChatListAction.parse({
        'type': 'pin',
        'ids': ['1', '2'],
      });
      expect(action!.type, NativeChatListActionType.pin);
      expect(action.ids, ['1', '2']);
    });

    test('search needs no ids', () {
      expect(
        NativeChatListAction.parse({'type': 'search'})!.type,
        NativeChatListActionType.search,
      );
    });

    test('rejects unknown types and missing ids', () {
      expect(NativeChatListAction.parse({'type': 'explode'}), isNull);
      expect(NativeChatListAction.parse({'type': 'open', 'ids': []}), isNull);
      expect(NativeChatListAction.parse('open'), isNull);
    });
  });

  group('NativeChatListBridge', () {
    const channel = MethodChannel('promax/native_chat_list/test');
    final calls = <MethodCall>[];
    final opened = <String>[];
    final pinned = <List<String>>[];
    var searched = 0;
    late NativeChatListBridge bridge;

    NativeChatListHandlers handlers() => NativeChatListHandlers(
      open: opened.add,
      select: (_) {},
      pin: pinned.add,
      mute: (_) {},
      archive: (_) {},
      delete: (_) {},
      search: () => searched++,
    );

    setUp(() {
      calls.clear();
      opened.clear();
      pinned.clear();
      searched = 0;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call);
            return null;
          });
      bridge = NativeChatListBridge(channel: channel, handlers: handlers());
    });

    tearDown(() {
      bridge.dispose();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    Future<void> receive(String method, Object? args) async {
      await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .handlePlatformMessage(
            channel.name,
            channel.codec.encodeMethodCall(MethodCall(method, args)),
            (_) {},
          );
    }

    test('first sync replaces, later syncs send diffs', () async {
      await bridge.sync([row('1'), row('2')]);
      await bridge.sync([row('1'), row('2')]);
      await bridge.sync([row('1'), row('2', unread: 1)]);
      expect(calls.map((c) => c.method), ['replace', 'apply']);
      final apply = calls.last.arguments as Map;
      expect((apply['upsert'] as List).single['id'], '2');
      expect(apply['order'], isNull);
    });

    test('selection change alone triggers an apply', () async {
      await bridge.sync([row('1')]);
      await bridge.sync([row('1')], selecting: true);
      expect(calls.map((c) => c.method), ['replace', 'apply']);
      expect((calls.last.arguments as Map)['selecting'], true);
    });

    test('ready from native forces a full resend', () async {
      var readyCalls = 0;
      bridge.dispose();
      bridge = NativeChatListBridge(
        channel: channel,
        handlers: handlers(),
        onReady: () => readyCalls++,
      );
      await bridge.sync([row('1')]);
      await receive('ready', null);
      expect(readyCalls, 1);
      expect(bridge.isSynced, isFalse);
      await bridge.sync([row('1')]);
      expect(calls.map((c) => c.method), ['replace', 'replace']);
    });

    test('actions are routed to the handlers', () async {
      await receive('action', {
        'type': 'open',
        'ids': ['42'],
      });
      await receive('action', {
        'type': 'pin',
        'ids': ['1', '2'],
      });
      await receive('action', {'type': 'search'});
      await receive('action', {'type': 'bogus'});
      expect(opened, ['42']);
      expect(pinned, [
        ['1', '2'],
      ]);
      expect(searched, 1);
    });
  });
}
