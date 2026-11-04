import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:promax_crypto/promax_crypto.dart';

void main() {
  setUpAll(() {
    final configured = Platform.environment['PROMAX_CRYPTO_TEST_LIB'];
    final name = Platform.isMacOS
        ? 'libpromax_crypto.dylib'
        : Platform.isWindows
            ? 'promax_crypto.dll'
            : 'libpromax_crypto.so';
    ProMaxCrypto.libraryPath =
        configured ?? File('../../build/$name').absolute.path;
  });

  List<Uint8List> identities() => List.generate(
      3,
      (index) => ProMaxCrypto.identityCreate(
          seed: Uint8List.fromList(
              List.generate(32, (offset) => 17 + index * 37 + offset))));

  Uint8List members(List<Uint8List> identities, int count) =>
      ProMaxGroupCrypto.membersBuild(List.generate(
          count,
          (index) => GroupMember(
              id: 10001 + index,
              publicKey: ProMaxCrypto.identityPublicKey(identities[index]))));

  test('group native symbols and membership codec load', () {
    expect(ProMaxGroupCrypto.isAvailable, isTrue);
    final keys = identities();
    final manifest = members(keys, 2);
    expect(manifest.length, 2 * ProMaxCryptoSizes.groupMember);
    expect(
        () => ProMaxGroupCrypto.membersBuild([
              GroupMember(
                  id: 10002,
                  publicKey: ProMaxCrypto.identityPublicKey(keys[1])),
              GroupMember(
                  id: 10001,
                  publicKey: ProMaxCrypto.identityPublicKey(keys[0])),
            ]),
        throwsA(isA<ProMaxCryptoException>()));
  });

  test('FFI group envelope roundtrip, skipped messages and replay', () {
    final keys = identities();
    final manifest = members(keys, 2);
    final sender = ProMaxGroupCrypto.senderCreate(
        identity: keys[0],
        groupId: -20001,
        senderId: 10001,
        epoch: 1,
        members: manifest);
    var receiveState = ProMaxGroupCrypto.receiverImport(
        groupId: -20001,
        senderId: 10001,
        members: manifest,
        distribution: sender.distribution);
    final payload = Uint8List.fromList([0, 128, 255, 4]);
    final first = ProMaxGroupCrypto.encrypt(
        state: sender.state, contentType: ContentType.file, plaintext: payload);
    final second = ProMaxGroupCrypto.encrypt(
        state: first.state,
        contentType: ContentType.control,
        plaintext: Uint8List(0));
    final receivedSecond = ProMaxGroupCrypto.decrypt(
        state: receiveState, envelope: second.envelope);
    receiveState = receivedSecond.state;
    expect(receivedSecond.contentType, ContentType.control);
    expect(receivedSecond.plaintext, isEmpty);
    final receivedFirst = ProMaxGroupCrypto.decrypt(
        state: receiveState, envelope: first.envelope);
    expect(receivedFirst.plaintext, payload);
    expect(receivedFirst.contentType, ContentType.file);
    expect(
        () => ProMaxGroupCrypto.decrypt(
            state: receivedFirst.state, envelope: first.envelope),
        throwsA(isA<ProMaxCryptoException>()
            .having((error) => error.status, 'status', CryptoStatus.replay)));
  });

  test('sender distribution travels inside authenticated v3 control payload',
      () {
    final keys = identities();
    final manifest = members(keys, 2);
    final sender = ProMaxGroupCrypto.senderCreate(
        identity: keys[0],
        groupId: -20001,
        senderId: 10001,
        epoch: 1,
        members: manifest);
    final offer = ProMaxCrypto.sessionOffer(
        identity: keys[0], chatId: 20002, myId: 10001, peerId: 10002);
    final answer = ProMaxCrypto.sessionAnswer(
        identity: keys[1],
        chatId: 20002,
        myId: 10002,
        peerId: 10001,
        offerText: offer.text);
    final sendState = ProMaxCrypto.sessionAccept(
        identity: keys[0],
        pending: offer.pending,
        answerText: answer.text,
        expectedPeer: ProMaxCrypto.identityPublicKey(keys[1]));
    final sealed = ProMaxCrypto.sessionEncrypt(
        state: sendState,
        contentType: ContentType.control,
        plaintext: sender.distribution);
    final opened =
        ProMaxCrypto.sessionDecrypt(state: answer.state, text: sealed.text);
    expect(sealed.text.length,
        lessThanOrEqualTo(ProMaxCryptoSizes.textTransportMax));
    expect(opened.contentType, ContentType.control);
    expect(opened.plaintext, sender.distribution);
    expect(
        ProMaxGroupCrypto.receiverImport(
            groupId: -20001,
            senderId: 10001,
            members: manifest,
            distribution: opened.plaintext),
        isNotEmpty);
  });

  test('join rotation rejects previous epoch and stale distributions', () {
    final keys = identities();
    final initialMembers = members(keys, 2);
    final joinedMembers = members(keys, 3);
    final initial = ProMaxGroupCrypto.senderCreate(
        identity: keys[0],
        groupId: -20001,
        senderId: 10001,
        epoch: 1,
        members: initialMembers);
    final initialReceiver = ProMaxGroupCrypto.receiverImport(
        groupId: -20001,
        senderId: 10001,
        members: initialMembers,
        distribution: initial.distribution);
    final next = ProMaxGroupCrypto.senderCreate(
        identity: keys[0],
        groupId: -20001,
        senderId: 10001,
        epoch: 2,
        members: joinedMembers,
        oldState: initial.state);
    final nextReceiver = ProMaxGroupCrypto.receiverImport(
        groupId: -20001,
        senderId: 10001,
        members: joinedMembers,
        distribution: next.distribution,
        oldState: initialReceiver);
    final encrypted = ProMaxGroupCrypto.encrypt(
        state: next.state,
        contentType: ContentType.text,
        plaintext: Uint8List.fromList([65]));
    expect(
        () => ProMaxGroupCrypto.decrypt(
            state: initialReceiver, envelope: encrypted.envelope),
        throwsA(isA<ProMaxCryptoException>()
            .having((error) => error.status, 'status', CryptoStatus.badPeer)));
    expect(
        ProMaxGroupCrypto.decrypt(
                state: nextReceiver, envelope: encrypted.envelope)
            .plaintext,
        [65]);
    expect(
        () => ProMaxGroupCrypto.receiverImport(
            groupId: -20001,
            senderId: 10001,
            members: initialMembers,
            distribution: initial.distribution,
            oldState: nextReceiver),
        throwsA(isA<ProMaxCryptoException>()
            .having((error) => error.status, 'status', CryptoStatus.replay)));
  });
}
