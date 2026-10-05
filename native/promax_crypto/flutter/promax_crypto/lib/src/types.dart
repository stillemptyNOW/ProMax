import 'dart:typed_data';

enum CryptoStatus {
  ok(0, 'ok'),
  emptyPassword(-1, 'empty_password'),
  badKeyLength(-2, 'bad_key_length'),
  notEncrypted(-3, 'not_encrypted'),
  malformed(-4, 'malformed'),
  wrongKey(-5, 'wrong_key'),
  internal(-6, 'internal'),
  bufferTooSmall(-7, 'buffer_too_small'),
  invalidArgument(-8, 'invalid_argument'),
  outOfMemory(-9, 'out_of_memory'),
  badSignature(-10, 'bad_signature'),
  badState(-11, 'bad_state'),
  tooManySkipped(-12, 'too_many_skipped'),
  replay(-13, 'replay'),
  badPeer(-14, 'bad_peer'),
  unsupportedVersion(-15, 'unsupported_version'),
  handshakeMessage(-16, 'handshake_message'),
  tooLong(-17, 'too_long'),
  awaitingPeer(-18, 'awaiting_peer'),
  unavailable(-100, 'unavailable');

  const CryptoStatus(this.code, this.name_);

  final int code;
  final String name_;

  static CryptoStatus fromCode(int code) => CryptoStatus.values.firstWhere(
    (status) => status.code == code,
    orElse: () => CryptoStatus.internal,
  );
}

class ProMaxCryptoException implements Exception {
  const ProMaxCryptoException(this.status);

  final CryptoStatus status;

  @override
  String toString() => 'ProMaxCryptoException(${status.name_})';
}

enum TextClass { none, legacy, offer, answer, session }

enum ContentType {
  text(1),
  file(2),
  control(3);

  const ContentType(this.code);

  final int code;

  static ContentType fromCode(int code) =>
      ContentType.values.firstWhere((type) => type.code == code);
}

enum HandshakeType { offer, answer }

class HandshakePeek {
  const HandshakePeek({
    required this.type,
    required this.offerId,
    required this.publicKey,
  });

  final HandshakeType type;
  final Uint8List offerId;
  final Uint8List publicKey;
}

class SessionOffer {
  const SessionOffer({required this.text, required this.pending});

  final String text;
  final Uint8List pending;
}

class SessionAnswer {
  const SessionAnswer({required this.text, required this.state});

  final String text;
  final Uint8List state;
}

class SessionEncrypted {
  const SessionEncrypted({required this.text, required this.state});

  final String text;
  final Uint8List state;
}

class SessionDecrypted {
  const SessionDecrypted({
    required this.contentType,
    required this.plaintext,
    required this.state,
  });

  final ContentType contentType;
  final Uint8List plaintext;
  final Uint8List state;
}

abstract final class ProMaxCryptoSizes {
  static const int key = 32;
  static const int nonce = 12;
  static const int tag = 16;
  static const int seed = 32;
  static const int publicKey = 32;
  static const int identity = 64;
  static const int fingerprintDigits = 60;
  static const int offerId = 8;
  static const int handshakeTextBound = 497;
  static const int pendingState = 203;
  static const int sessionStateMax = 17712;
  static const int sessionPlaintextMax = 414;
  static const int textTransportMax = 1000;
  static const int identityRandom = 32;
  static const int offerRandom = 40;
  static const int answerRandom = 32;
  static const int acceptRandom = 32;
  static const int encryptRandom = 32;
  static const int exportRandom = 40;
  static const int fileKey = 32;
  static const int fileNonce = 12;
  static const int fileChunk = 65536;
  static const int fileContext = 96;
  static const int localKey = 32;
  static const int localNonce = 24;
}
