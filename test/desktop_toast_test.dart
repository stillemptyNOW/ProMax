import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:promax/core/calls/camera_devices.dart';
import 'package:promax/core/desktop/desktop_toast.dart';

const int _chatId = 9000002;
const int _accountId = 4243;
const String _conversation = 'synthetic-conversation-1';

void main() {
  test('a toast body click opens the chat on Windows', () {
    final payload = DesktopToastIntent.chatPayload(
      _chatId,
      accountId: _accountId,
      messageId: 31,
    );
    final intent = DesktopToastIntent.parse(
      payload: payload,
      actionId: payload,
    )!;
    expect(intent.action, DesktopToastAction.open);
    expect(intent.chatId, _chatId);
    expect(intent.accountId, _accountId);
    expect(intent.messageId, 31);
    expect(intent.isCall, isFalse);
  });

  test('a Windows button carries its action in the arguments', () {
    final arguments = DesktopToastIntent.callPayload(
      _conversation,
      action: DesktopToastAction.accept,
    );
    final intent = DesktopToastIntent.parse(
      payload: arguments,
      actionId: arguments,
    )!;
    expect(intent.action, DesktopToastAction.accept);
    expect(intent.conversationId, _conversation);
    expect(intent.isCall, isTrue);
  });

  test('a Linux button carries its action in the action id', () {
    final intent = DesktopToastIntent.parse(
      payload: DesktopToastIntent.callPayload(_conversation),
      actionId: DesktopToastAction.decline.name,
    )!;
    expect(intent.action, DesktopToastAction.decline);
    expect(intent.conversationId, _conversation);
  });

  test('the reply action keeps the replied message', () {
    final intent = DesktopToastIntent.parse(
      payload: DesktopToastIntent.chatPayload(
        _chatId,
        accountId: _accountId,
        messageId: 99,
        action: DesktopToastAction.reply,
      ),
    )!;
    expect(intent.action, DesktopToastAction.reply);
    expect(intent.messageId, 99);
  });

  test('foreign or broken payloads are ignored', () {
    expect(DesktopToastIntent.parse(payload: null), isNull);
    expect(DesktopToastIntent.parse(payload: ''), isNull);
    expect(DesktopToastIntent.parse(payload: 'not json'), isNull);
    expect(DesktopToastIntent.parse(payload: '{"chat":1}'), isNull);
    expect(
      DesktopToastIntent.parse(payload: jsonEncode({'t': 'chat', 'chat': 0})),
      isNull,
    );
    expect(
      DesktopToastIntent.parse(
        payload: DesktopToastIntent.callPayload(_conversation),
        actionId: 'unknown',
      ),
      isNull,
    );
    expect(
      DesktopToastIntent.parse(payload: jsonEncode({'chat': 1, 'c': 2})),
      isNull,
    );
  });

  test('the camera switch cycles through every video input', () {
    expect(CameraDevices.nextId(const ['a'], 'a'), isNull);
    expect(CameraDevices.nextId(const [], null), isNull);
    expect(CameraDevices.nextId(const ['a', 'b', 'c'], null), 'b');
    expect(CameraDevices.nextId(const ['a', 'b', 'c'], 'b'), 'c');
    expect(CameraDevices.nextId(const ['a', 'b', 'c'], 'c'), 'a');
    expect(CameraDevices.nextId(const ['a', 'b'], 'gone'), 'a');
  });
}
