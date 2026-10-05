import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:promax_crypto/promax_crypto.dart';

Uint8List hex(String text) {
  final out = Uint8List(text.length ~/ 2);
  for (var index = 0; index < out.length; index++) {
    out[index] = int.parse(text.substring(index * 2, index * 2 + 2), radix: 16);
  }
  return out;
}

String toHex(Uint8List bytes) =>
    bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();

Uint8List utf8Bytes(String text) => Uint8List.fromList(utf8.encode(text));

Uint8List pattern(int length) {
  final out = Uint8List(length);
  for (var index = 0; index < length; index++) {
    out[index] = (index * 7 + 3) & 0xff;
  }
  return out;
}

void main() {
  late Map<String, dynamic> vectors;

  setUpAll(() {
    final name = Platform.isMacOS
        ? 'libpromax_crypto.dylib'
        : Platform.isWindows
        ? 'promax_crypto.dll'
        : 'libpromax_crypto.so';
    ProMaxCrypto.libraryPath = File('../../build/$name').absolute.path;
    vectors =
        jsonDecode(File('../../tests/vectors/v3.json').readAsStringSync())
            as Map<String, dynamic>;
  });

  test('native library loads', () {
    expect(ProMaxCrypto.isAvailable, isTrue);
  });

  test('legacy key derivation vector', () {
    expect(
      toHex(ProMaxCrypto.deriveKey('fixture-password-01')),
      'a8e95a06e19c14f1d33a3d328e368ab7962cc1a7c9c00939d1ffadd871775164',
    );
  });

  test('legacy message written by the Rust build', () {
    final key = Uint8List.fromList(List.generate(32, (i) => (i * 7 + 3) & 0xff));
    const text =
        'ймау чзйыцяэ укяфмеои йцаныэшт жхсрж ярпцр щукз уугумчеб лвсхш '
        'щрше ьдзфзчк хтхыс щпыи учфххфгх жшхон с';
    expect(ProMaxCrypto.decryptMessage(text, key), 'fixture-message-from-rust');
    expect(ProMaxCrypto.looksEncryptedMessage(text), isTrue);
    expect(ProMaxCrypto.classifyText(text), TextClass.legacy);
    final other = Uint8List.fromList(key.map((b) => b ^ 0x5a).toList());
    expect(
      () => ProMaxCrypto.decryptMessage(text, other),
      throwsA(
        isA<ProMaxCryptoException>().having(
          (e) => e.status,
          'status',
          CryptoStatus.wrongKey,
        ),
      ),
    );
  });

  test('legacy round trip', () {
    final key = ProMaxCrypto.randomBytes(32);
    final text = ProMaxCrypto.encryptMessage('Привет, мир! 🙂', key);
    expect(ProMaxCrypto.decryptMessage(text, key), 'Привет, мир! 🙂');
    final image = ProMaxCrypto.encryptImageBlob(pattern(73), key);
    expect(ProMaxCrypto.looksEncryptedImageBlob(image), isTrue);
    expect(ProMaxCrypto.decryptImageBlob(image, key), pattern(73));
  });

  test('identity vectors', () {
    final a = vectors['identity_a'] as Map<String, dynamic>;
    final identity = ProMaxCrypto.identityCreate(seed: hex(a['seed'] as String));
    expect(toHex(identity), a['identity']);
    expect(toHex(ProMaxCrypto.identityPublicKey(identity)), a['public']);
    final b = vectors['identity_b'] as Map<String, dynamic>;
    expect(
      ProMaxCrypto.fingerprint(
        myId: 1001,
        myPublic: hex(a['public'] as String),
        peerId: 2002,
        peerPublic: hex(b['public'] as String),
      ),
      vectors['fingerprint'],
    );
    expect(
      ProMaxCrypto.fingerprint(
        myId: 2002,
        myPublic: hex(b['public'] as String),
        peerId: 1001,
        peerPublic: hex(a['public'] as String),
      ),
      vectors['fingerprint'],
    );
  });

  test('handshake and message vectors', () {
    final a = hex((vectors['identity_a'] as Map)['identity'] as String);
    final b = hex((vectors['identity_b'] as Map)['identity'] as String);
    final hs = vectors['handshake'] as Map<String, dynamic>;
    final offer = ProMaxCrypto.sessionOffer(
      identity: a,
      chatId: hs['chat_id'] as int,
      myId: hs['a_id'] as int,
      peerId: hs['b_id'] as int,
      random: hex(hs['offer_random'] as String),
    );
    expect(offer.text, hs['offer_text']);
    expect(toHex(offer.pending), hs['pending']);
    expect(ProMaxCrypto.classifyText(offer.text), TextClass.offer);
    final peek = ProMaxCrypto.handshakePeek('🔐 ProMax\n${offer.text}');
    expect(peek.type, HandshakeType.offer);
    expect(toHex(peek.publicKey), (vectors['identity_a'] as Map)['public']);

    final answer = ProMaxCrypto.sessionAnswer(
      identity: b,
      chatId: hs['chat_id'] as int,
      myId: hs['b_id'] as int,
      peerId: hs['a_id'] as int,
      offerText: offer.text,
      random: hex(hs['answer_random'] as String),
    );
    expect(answer.text, hs['answer_text']);
    expect(toHex(answer.state), hs['b_state_after_answer']);
    var stateA = ProMaxCrypto.sessionAccept(
      identity: a,
      pending: offer.pending,
      answerText: answer.text,
      expectedPeer: hex((vectors['identity_b'] as Map)['public'] as String),
      random: hex(hs['accept_random'] as String),
    );
    expect(
      () => ProMaxCrypto.sessionAccept(
        identity: a,
        pending: offer.pending,
        answerText: answer.text,
        expectedPeer: hex((vectors['identity_a'] as Map)['public'] as String),
        random: hex(hs['accept_random'] as String),
      ),
      throwsA(
        isA<ProMaxCryptoException>().having(
          (e) => e.status,
          'status',
          CryptoStatus.badPeer,
        ),
      ),
      reason: 'a pinned peer must reject a substituted responder',
    );
    expect(toHex(stateA), hs['a_state_after_accept']);
    var stateB = answer.state;
    expect(
      toHex(ProMaxCrypto.sessionPeerPublicKey(stateA)),
      (vectors['identity_b'] as Map)['public'],
    );

    String? delayed;
    for (final entry in vectors['messages'] as List) {
      final message = entry as Map<String, dynamic>;
      if (message.containsKey('replay_of')) {
        final decrypted = ProMaxCrypto.sessionDecrypt(
          state: stateB,
          text: delayed!,
        );
        expect(utf8.decode(decrypted.plaintext), 'пропущенное');
        stateB = decrypted.state;
        expect(toHex(stateB), message['receiver_state_after']);
        continue;
      }
      final fromA = message['from'] == 'a';
      final encrypted = ProMaxCrypto.sessionEncrypt(
        state: fromA ? stateA : stateB,
        contentType: ContentType.text,
        plaintext: utf8Bytes(message['plaintext'] as String),
        random: hex(message['random'] as String),
      );
      expect(encrypted.text, message['text']);
      expect(toHex(encrypted.state), message['sender_state_after']);
      expect(ProMaxCrypto.classifyText(encrypted.text), TextClass.session);
      if (fromA) {
        stateA = encrypted.state;
      } else {
        stateB = encrypted.state;
      }
      if (message['delivered_later'] == true) {
        delayed = encrypted.text;
        continue;
      }
      final decrypted = ProMaxCrypto.sessionDecrypt(
        state: fromA ? stateB : stateA,
        text: encrypted.text,
      );
      expect(decrypted.contentType, ContentType.text);
      expect(utf8.decode(decrypted.plaintext), message['plaintext']);
      expect(toHex(decrypted.state), message['receiver_state_after']);
      if (fromA) {
        stateB = decrypted.state;
      } else {
        stateA = decrypted.state;
      }
    }

    expect(
      () => ProMaxCrypto.sessionDecrypt(state: stateB, text: delayed!),
      throwsA(
        isA<ProMaxCryptoException>().having(
          (e) => e.status,
          'status',
          CryptoStatus.replay,
        ),
      ),
    );
    expect(
      () => ProMaxCrypto.sessionDecrypt(state: stateB, text: offer.text),
      throwsA(
        isA<ProMaxCryptoException>().having(
          (e) => e.status,
          'status',
          CryptoStatus.handshakeMessage,
        ),
      ),
    );
    expect(
      () => ProMaxCrypto.sessionDecrypt(state: stateB, text: 'просто текст'),
      throwsA(
        isA<ProMaxCryptoException>().having(
          (e) => e.status,
          'status',
          CryptoStatus.notEncrypted,
        ),
      ),
    );
  });

  test('local seal vector', () {
    final local = vectors['local'] as Map<String, dynamic>;
    final key = hex(local['key'] as String);
    final aad = utf8Bytes(local['aad'] as String);
    final blob = ProMaxCrypto.localSeal(
      key: key,
      nonce: hex(local['nonce'] as String),
      aad: aad,
      plaintext: utf8Bytes(local['plaintext'] as String),
    );
    expect(toHex(blob), local['blob']);
    expect(
      utf8.decode(ProMaxCrypto.localOpen(key: key, blob: blob, aad: aad)),
      local['plaintext'],
    );
    expect(
      () => ProMaxCrypto.localOpen(key: key, blob: blob),
      throwsA(isA<ProMaxCryptoException>()),
    );
  });

  test('file vector and round trip', () {
    final file = vectors['file'] as Map<String, dynamic>;
    final key = hex(file['key'] as String);
    final nonce = hex(file['nonce'] as String);
    final plain = pattern(file['plaintext_len'] as int);
    final sealer = ProMaxCrypto.fileSealer(key, nonce);
    final cipher = BytesBuilder(copy: false);
    var offset = 0;
    while (true) {
      final last = plain.length - offset <= ProMaxCryptoSizes.fileChunk;
      final end = last ? plain.length : offset + ProMaxCryptoSizes.fileChunk;
      cipher.add(sealer.chunk(plain.sublist(offset, end), last: last));
      offset = end;
      if (last) break;
    }
    sealer.dispose();
    final bytes = cipher.toBytes();
    expect(bytes.length, file['ciphertext_len']);
    expect(toHex(bytes.sublist(0, 64)), file['ciphertext_head']);

    final opener = ProMaxCrypto.fileOpener(key, nonce);
    final opened = BytesBuilder(copy: false);
    offset = 0;
    const step = ProMaxCryptoSizes.fileChunk + ProMaxCryptoSizes.tag;
    while (true) {
      final last = bytes.length - offset <= step;
      final end = last ? bytes.length : offset + step;
      opened.add(opener.chunk(bytes.sublist(offset, end), last: last));
      offset = end;
      if (last) break;
    }
    opener.dispose();
    expect(opened.toBytes(), plain);
  });

  test('export vector', () {
    final export = vectors['export'] as Map<String, dynamic>;
    final password = utf8Bytes(export['password'] as String);
    final blob = ProMaxCrypto.exportSeal(
      password: password,
      memoryKib: export['memory_kib'] as int,
      passes: export['passes'] as int,
      random: hex(export['random'] as String),
      container: hex(export['container'] as String),
    );
    expect(toHex(blob), export['blob']);
    expect(
      toHex(ProMaxCrypto.exportOpen(password: password, blob: blob)),
      export['opened_container'],
    );
    expect(
      () => ProMaxCrypto.exportOpen(password: utf8Bytes('wrong'), blob: blob),
      throwsA(
        isA<ProMaxCryptoException>().having(
          (e) => e.status,
          'status',
          CryptoStatus.wrongKey,
        ),
      ),
    );
  });

  test('two live parties', () {
    final a = ProMaxCrypto.identityCreate();
    final b = ProMaxCrypto.identityCreate();
    final offer = ProMaxCrypto.sessionOffer(
      identity: a,
      chatId: 7,
      myId: 1,
      peerId: 2,
    );
    final answer = ProMaxCrypto.sessionAnswer(
      identity: b,
      chatId: 7,
      myId: 2,
      peerId: 1,
      offerText: offer.text,
    );
    var stateA = ProMaxCrypto.sessionAccept(
      identity: a,
      pending: offer.pending,
      answerText: answer.text,
    );
    var stateB = answer.state;
    for (var round = 0; round < 5; round++) {
      final toB = ProMaxCrypto.sessionEncrypt(
        state: stateA,
        contentType: ContentType.text,
        plaintext: utf8Bytes('раунд $round'),
      );
      stateA = toB.state;
      final atB = ProMaxCrypto.sessionDecrypt(state: stateB, text: toB.text);
      stateB = atB.state;
      expect(utf8.decode(atB.plaintext), 'раунд $round');
      final toA = ProMaxCrypto.sessionEncrypt(
        state: stateB,
        contentType: ContentType.control,
        plaintext: Uint8List(0),
      );
      stateB = toA.state;
      final atA = ProMaxCrypto.sessionDecrypt(state: stateA, text: toA.text);
      stateA = atA.state;
      expect(atA.contentType, ContentType.control);
      expect(atA.plaintext, isEmpty);
    }
    expect(
      ProMaxCrypto.fingerprint(
        myId: 1,
        myPublic: ProMaxCrypto.identityPublicKey(a),
        peerId: 2,
        peerPublic: ProMaxCrypto.sessionPeerPublicKey(stateA),
      ),
      hasLength(60),
    );
  });
}
