import 'dart:typed_data';

import 'types.dart';

Never _unavailable() =>
    throw const ProMaxCryptoException(CryptoStatus.unavailable);

class FileSealer {
  Uint8List chunk(Uint8List plaintext, {required bool last}) => _unavailable();

  void dispose() {}
}

class FileOpener {
  Uint8List chunk(Uint8List ciphertext, {required bool last}) =>
      _unavailable();

  void dispose() {}
}

abstract final class ProMaxCrypto {
  static String? libraryPath;

  static bool get isAvailable => false;

  static Uint8List randomBytes(int length) => _unavailable();

  static void wipe(Uint8List bytes) => bytes.fillRange(0, bytes.length, 0);

  static Uint8List deriveKey(String password) => _unavailable();

  static String encryptMessage(
    String plaintext,
    Uint8List key, {
    Uint8List? nonce,
  }) => _unavailable();

  static String decryptMessage(String text, Uint8List key) => _unavailable();

  static bool looksEncryptedMessage(String text) => false;

  static Uint8List encryptImageBlob(
    Uint8List plaintext,
    Uint8List key, {
    Uint8List? nonce,
  }) => _unavailable();

  static Uint8List decryptImageBlob(Uint8List blob, Uint8List key) =>
      _unavailable();

  static bool looksEncryptedImageBlob(Uint8List blob) => false;

  static Uint8List identityCreate({Uint8List? seed}) => _unavailable();

  static Uint8List identityPublicKey(Uint8List identity) => _unavailable();

  static String fingerprint({
    required int myId,
    required Uint8List myPublic,
    required int peerId,
    required Uint8List peerPublic,
  }) => _unavailable();

  static TextClass classifyText(String text) => TextClass.none;

  static HandshakePeek handshakePeek(String text) => _unavailable();

  static SessionOffer sessionOffer({
    required Uint8List identity,
    required int chatId,
    required int myId,
    required int peerId,
    Uint8List? random,
  }) => _unavailable();

  static SessionAnswer sessionAnswer({
    required Uint8List identity,
    required int chatId,
    required int myId,
    required int peerId,
    required String offerText,
    Uint8List? oldState,
    Uint8List? random,
  }) => _unavailable();

  static Uint8List sessionAccept({
    required Uint8List identity,
    required Uint8List pending,
    required String answerText,
    Uint8List? expectedPeer,
    Uint8List? random,
  }) => _unavailable();

  static SessionEncrypted sessionEncrypt({
    required Uint8List state,
    required ContentType contentType,
    required Uint8List plaintext,
    Uint8List? random,
  }) => _unavailable();

  static SessionDecrypted sessionDecrypt({
    required Uint8List state,
    required String text,
  }) => _unavailable();

  static Uint8List sessionPeerPublicKey(Uint8List state) => _unavailable();

  static FileSealer fileSealer(Uint8List key, Uint8List nonce) =>
      _unavailable();

  static FileOpener fileOpener(Uint8List key, Uint8List nonce) =>
      _unavailable();

  static Uint8List localSeal({
    required Uint8List key,
    required Uint8List plaintext,
    Uint8List? nonce,
    Uint8List? aad,
  }) => _unavailable();

  static Uint8List localOpen({
    required Uint8List key,
    required Uint8List blob,
    Uint8List? aad,
  }) => _unavailable();

  static Uint8List exportSeal({
    required Uint8List password,
    required int memoryKib,
    required int passes,
    required Uint8List container,
    Uint8List? random,
  }) => _unavailable();

  static Uint8List exportOpen({
    required Uint8List password,
    required Uint8List blob,
  }) => _unavailable();
}
