import 'dart:convert';
import 'dart:ffi' as ffi;
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'types.dart';

typedef _Bytes = ffi.Pointer<ffi.Uint8>;
typedef _SizeOut = ffi.Pointer<ffi.Size>;

typedef _WipeNative = ffi.Void Function(ffi.Pointer<ffi.Void>, ffi.Size);
typedef _Wipe = void Function(ffi.Pointer<ffi.Void>, int);
typedef _BoundNative = ffi.Size Function(ffi.Size);
typedef _Bound = int Function(int);
typedef _LooksNative = ffi.Int32 Function(_Bytes, ffi.Size);
typedef _Looks = int Function(_Bytes, int);
typedef _DeriveKeyNative =
    ffi.Int32 Function(_Bytes, ffi.Size, _Bytes, ffi.Size);
typedef _DeriveKey = int Function(_Bytes, int, _Bytes, int);
typedef _Buf2Native =
    ffi.Int32 Function(_Bytes, ffi.Size, _Bytes, ffi.Size, _SizeOut);
typedef _Buf2 = int Function(_Bytes, int, _Bytes, int, _SizeOut);
typedef _Buf3Native =
    ffi.Int32 Function(
      _Bytes,
      ffi.Size,
      _Bytes,
      ffi.Size,
      _Bytes,
      ffi.Size,
      _SizeOut,
    );
typedef _Buf3 = int Function(_Bytes, int, _Bytes, int, _Bytes, int, _SizeOut);
typedef _Buf4Native =
    ffi.Int32 Function(
      _Bytes,
      ffi.Size,
      _Bytes,
      ffi.Size,
      _Bytes,
      ffi.Size,
      _Bytes,
      ffi.Size,
      _SizeOut,
    );
typedef _Buf4 =
    int Function(_Bytes, int, _Bytes, int, _Bytes, int, _Bytes, int, _SizeOut);
typedef _Buf5Native =
    ffi.Int32 Function(
      _Bytes,
      ffi.Size,
      _Bytes,
      ffi.Size,
      _Bytes,
      ffi.Size,
      _Bytes,
      ffi.Size,
      _Bytes,
      ffi.Size,
      _SizeOut,
    );
typedef _Buf5 =
    int Function(
      _Bytes,
      int,
      _Bytes,
      int,
      _Bytes,
      int,
      _Bytes,
      int,
      _Bytes,
      int,
      _SizeOut,
    );
typedef _Buf6Native =
    ffi.Int32 Function(
      _Bytes,
      ffi.Size,
      _Bytes,
      ffi.Size,
      _Bytes,
      ffi.Size,
      _Bytes,
      ffi.Size,
      _Bytes,
      ffi.Size,
      _Bytes,
      ffi.Size,
      _SizeOut,
    );
typedef _Buf6 =
    int Function(
      _Bytes,
      int,
      _Bytes,
      int,
      _Bytes,
      int,
      _Bytes,
      int,
      _Bytes,
      int,
      _Bytes,
      int,
      _SizeOut,
    );
typedef _FingerprintNative =
    ffi.Int32 Function(
      ffi.Int64,
      _Bytes,
      ffi.Size,
      ffi.Int64,
      _Bytes,
      ffi.Size,
      _Bytes,
      ffi.Size,
      _SizeOut,
    );
typedef _Fingerprint =
    int Function(int, _Bytes, int, int, _Bytes, int, _Bytes, int, _SizeOut);
typedef _PeekNative =
    ffi.Int32 Function(
      _Bytes,
      ffi.Size,
      _Bytes,
      _Bytes,
      ffi.Size,
      _Bytes,
      ffi.Size,
    );
typedef _Peek = int Function(_Bytes, int, _Bytes, _Bytes, int, _Bytes, int);
typedef _OfferNative =
    ffi.Int32 Function(
      _Bytes,
      ffi.Size,
      ffi.Int64,
      ffi.Int64,
      ffi.Int64,
      _Bytes,
      ffi.Size,
      _Bytes,
      ffi.Size,
      _SizeOut,
      _Bytes,
      ffi.Size,
      _SizeOut,
    );
typedef _Offer =
    int Function(
      _Bytes,
      int,
      int,
      int,
      int,
      _Bytes,
      int,
      _Bytes,
      int,
      _SizeOut,
      _Bytes,
      int,
      _SizeOut,
    );
typedef _AnswerNative =
    ffi.Int32 Function(
      _Bytes,
      ffi.Size,
      ffi.Int64,
      ffi.Int64,
      ffi.Int64,
      _Bytes,
      ffi.Size,
      _Bytes,
      ffi.Size,
      _Bytes,
      ffi.Size,
      _Bytes,
      ffi.Size,
      _SizeOut,
      _Bytes,
      ffi.Size,
      _SizeOut,
    );
typedef _Answer =
    int Function(
      _Bytes,
      int,
      int,
      int,
      int,
      _Bytes,
      int,
      _Bytes,
      int,
      _Bytes,
      int,
      _Bytes,
      int,
      _SizeOut,
      _Bytes,
      int,
      _SizeOut,
    );
typedef _EncryptNative =
    ffi.Int32 Function(
      _Bytes,
      ffi.Size,
      ffi.Uint8,
      _Bytes,
      ffi.Size,
      _Bytes,
      ffi.Size,
      _Bytes,
      ffi.Size,
      _SizeOut,
      _Bytes,
      ffi.Size,
      _SizeOut,
    );
typedef _Encrypt =
    int Function(
      _Bytes,
      int,
      int,
      _Bytes,
      int,
      _Bytes,
      int,
      _Bytes,
      int,
      _SizeOut,
      _Bytes,
      int,
      _SizeOut,
    );
typedef _DecryptNative =
    ffi.Int32 Function(
      _Bytes,
      ffi.Size,
      _Bytes,
      ffi.Size,
      _Bytes,
      _Bytes,
      ffi.Size,
      _SizeOut,
      _Bytes,
      ffi.Size,
      _SizeOut,
    );
typedef _Decrypt =
    int Function(
      _Bytes,
      int,
      _Bytes,
      int,
      _Bytes,
      _Bytes,
      int,
      _SizeOut,
      _Bytes,
      int,
      _SizeOut,
    );
typedef _FileInitNative =
    ffi.Int32 Function(_Bytes, ffi.Size, _Bytes, ffi.Size, _Bytes, ffi.Size);
typedef _FileInit = int Function(_Bytes, int, _Bytes, int, _Bytes, int);
typedef _FileChunkNative =
    ffi.Int32 Function(
      _Bytes,
      ffi.Size,
      _Bytes,
      ffi.Size,
      ffi.Int32,
      _Bytes,
      ffi.Size,
      _SizeOut,
    );
typedef _FileChunk =
    int Function(_Bytes, int, _Bytes, int, int, _Bytes, int, _SizeOut);
typedef _ExportSealNative =
    ffi.Int32 Function(
      _Bytes,
      ffi.Size,
      ffi.Uint32,
      ffi.Uint32,
      _Bytes,
      ffi.Size,
      _Bytes,
      ffi.Size,
      _Bytes,
      ffi.Size,
      _SizeOut,
    );
typedef _ExportSeal =
    int Function(
      _Bytes,
      int,
      int,
      int,
      _Bytes,
      int,
      _Bytes,
      int,
      _Bytes,
      int,
      _SizeOut,
    );

class _Lib {
  _Lib(ffi.DynamicLibrary lib)
    : wipe = lib.lookupFunction<_WipeNative, _Wipe>('kc_wipe'),
      deriveKey = lib.lookupFunction<_DeriveKeyNative, _DeriveKey>(
        'kc_derive_key',
      ),
      encryptMessageBound = lib.lookupFunction<_BoundNative, _Bound>(
        'kc_encrypt_message_bound',
      ),
      encryptMessage = lib.lookupFunction<_Buf4Native, _Buf4>(
        'kc_encrypt_message',
      ),
      decryptMessage = lib.lookupFunction<_Buf3Native, _Buf3>(
        'kc_decrypt_message',
      ),
      looksEncryptedMessage = lib.lookupFunction<_LooksNative, _Looks>(
        'kc_looks_encrypted_message',
      ),
      encryptImageBound = lib.lookupFunction<_BoundNative, _Bound>(
        'kc_encrypt_image_blob_bound',
      ),
      encryptImage = lib.lookupFunction<_Buf4Native, _Buf4>(
        'kc_encrypt_image_blob',
      ),
      decryptImageBound = lib.lookupFunction<_BoundNative, _Bound>(
        'kc_decrypt_image_blob_bound',
      ),
      decryptImage = lib.lookupFunction<_Buf3Native, _Buf3>(
        'kc_decrypt_image_blob',
      ),
      looksEncryptedImage = lib.lookupFunction<_LooksNative, _Looks>(
        'kc_looks_encrypted_image_blob',
      ),
      identityCreate = lib.lookupFunction<_Buf2Native, _Buf2>(
        'kc_identity_create',
      ),
      identityPublicKey = lib.lookupFunction<_Buf2Native, _Buf2>(
        'kc_identity_public_key',
      ),
      fingerprint = lib.lookupFunction<_FingerprintNative, _Fingerprint>(
        'kc_fingerprint',
      ),
      classifyText = lib.lookupFunction<_LooksNative, _Looks>(
        'kc_classify_text',
      ),
      handshakePeek = lib.lookupFunction<_PeekNative, _Peek>(
        'kc_handshake_peek',
      ),
      sessionOffer = lib.lookupFunction<_OfferNative, _Offer>(
        'kc_session_offer',
      ),
      sessionAnswer = lib.lookupFunction<_AnswerNative, _Answer>(
        'kc_session_answer',
      ),
      sessionAccept = lib.lookupFunction<_Buf6Native, _Buf6>(
        'kc_session_accept',
      ),
      sessionEncryptBound = lib.lookupFunction<_BoundNative, _Bound>(
        'kc_session_encrypt_bound',
      ),
      sessionEncrypt = lib.lookupFunction<_EncryptNative, _Encrypt>(
        'kc_session_encrypt',
      ),
      sessionDecrypt = lib.lookupFunction<_DecryptNative, _Decrypt>(
        'kc_session_decrypt',
      ),
      sessionPeerPublicKey = lib.lookupFunction<_Buf2Native, _Buf2>(
        'kc_session_peer_public_key',
      ),
      fileSealInit = lib.lookupFunction<_FileInitNative, _FileInit>(
        'kc_file_seal_init',
      ),
      fileSealChunk = lib.lookupFunction<_FileChunkNative, _FileChunk>(
        'kc_file_seal_chunk',
      ),
      fileOpenInit = lib.lookupFunction<_FileInitNative, _FileInit>(
        'kc_file_open_init',
      ),
      fileOpenChunk = lib.lookupFunction<_FileChunkNative, _FileChunk>(
        'kc_file_open_chunk',
      ),
      localSeal = lib.lookupFunction<_Buf5Native, _Buf5>('kc_local_seal'),
      localOpen = lib.lookupFunction<_Buf4Native, _Buf4>('kc_local_open'),
      exportSealBound = lib.lookupFunction<_BoundNative, _Bound>(
        'kc_export_seal_bound',
      ),
      exportSeal = lib.lookupFunction<_ExportSealNative, _ExportSeal>(
        'kc_export_seal',
      ),
      exportOpenBound = lib.lookupFunction<_BoundNative, _Bound>(
        'kc_export_open_bound',
      ),
      exportOpen = lib.lookupFunction<_Buf3Native, _Buf3>('kc_export_open');

  final _Wipe wipe;
  final _DeriveKey deriveKey;
  final _Bound encryptMessageBound;
  final _Buf4 encryptMessage;
  final _Buf3 decryptMessage;
  final _Looks looksEncryptedMessage;
  final _Bound encryptImageBound;
  final _Buf4 encryptImage;
  final _Bound decryptImageBound;
  final _Buf3 decryptImage;
  final _Looks looksEncryptedImage;
  final _Buf2 identityCreate;
  final _Buf2 identityPublicKey;
  final _Fingerprint fingerprint;
  final _Looks classifyText;
  final _Peek handshakePeek;
  final _Offer sessionOffer;
  final _Answer sessionAnswer;
  final _Buf6 sessionAccept;
  final _Bound sessionEncryptBound;
  final _Encrypt sessionEncrypt;
  final _Decrypt sessionDecrypt;
  final _Buf2 sessionPeerPublicKey;
  final _FileInit fileSealInit;
  final _FileChunk fileSealChunk;
  final _FileInit fileOpenInit;
  final _FileChunk fileOpenChunk;
  final _Buf5 localSeal;
  final _Buf4 localOpen;
  final _Bound exportSealBound;
  final _ExportSeal exportSeal;
  final _Bound exportOpenBound;
  final _Buf3 exportOpen;

  static _Lib? _instance;
  static String? _loadedPath;

  static ffi.DynamicLibrary _open() {
    final path = ProMaxCrypto.libraryPath;
    if (path != null) return ffi.DynamicLibrary.open(path);
    if (Platform.isIOS || Platform.isMacOS) return ffi.DynamicLibrary.process();
    if (Platform.isAndroid || Platform.isLinux) {
      return ffi.DynamicLibrary.open('libpromax_crypto.so');
    }
    if (Platform.isWindows) return ffi.DynamicLibrary.open('promax_crypto.dll');
    throw UnsupportedError(Platform.operatingSystem);
  }

  static _Lib get instance {
    final cached = _instance;
    if (cached != null && _loadedPath == ProMaxCrypto.libraryPath) return cached;
    try {
      final lib = _Lib(_open());
      _instance = lib;
      _loadedPath = ProMaxCrypto.libraryPath;
      return lib;
    } catch (_) {
      throw const ProMaxCryptoException(CryptoStatus.unavailable);
    }
  }
}

class _Scope {
  _Scope(this._lib);

  final _Lib _lib;
  final List<(_Bytes, int)> _buffers = [];
  final List<ffi.Pointer<ffi.NativeType>> _plain = [];

  _Bytes bytes(Uint8List data) {
    final pointer = calloc<ffi.Uint8>(max(1, data.length));
    if (data.isNotEmpty) pointer.asTypedList(data.length).setAll(0, data);
    _buffers.add((pointer, data.length));
    return pointer;
  }

  _Bytes text(String text) => bytes(Uint8List.fromList(utf8.encode(text)));

  _Bytes out(int length) {
    final pointer = calloc<ffi.Uint8>(max(1, length));
    _buffers.add((pointer, length));
    return pointer;
  }

  _SizeOut size() {
    final pointer = calloc<ffi.Size>();
    _plain.add(pointer);
    return pointer;
  }

  ffi.Pointer<ffi.Uint8> byte() {
    final pointer = calloc<ffi.Uint8>();
    _plain.add(pointer);
    return pointer;
  }

  Uint8List take(_Bytes pointer, int length) =>
      Uint8List.fromList(pointer.asTypedList(length));

  String takeText(_Bytes pointer, int length) =>
      utf8.decode(pointer.asTypedList(length));

  void release() {
    for (final (pointer, length) in _buffers) {
      if (length > 0) _lib.wipe(pointer.cast(), length);
      calloc.free(pointer);
    }
    for (final pointer in _plain) {
      calloc.free(pointer);
    }
  }
}

R _run<R>(R Function(_Scope scope, _Lib lib) body) {
  final lib = _Lib.instance;
  final scope = _Scope(lib);
  try {
    return body(scope, lib);
  } finally {
    scope.release();
  }
}

void _check(int status) {
  if (status != 0) throw ProMaxCryptoException(CryptoStatus.fromCode(status));
}

Uint8List _randomOr(Uint8List? random, int length) {
  if (random != null) {
    if (random.length != length) {
      throw const ProMaxCryptoException(CryptoStatus.invalidArgument);
    }
    return random;
  }
  return ProMaxCrypto.randomBytes(length);
}

class FileSealer {
  FileSealer._(this._context);

  final Uint8List _context;

  Uint8List chunk(Uint8List plaintext, {required bool last}) =>
      _run((scope, lib) {
        final context = scope.bytes(_context);
        final out = scope.out(plaintext.length + ProMaxCryptoSizes.tag);
        final outLen = scope.size();
        _check(
          lib.fileSealChunk(
            context,
            _context.length,
            scope.bytes(plaintext),
            plaintext.length,
            last ? 1 : 0,
            out,
            plaintext.length + ProMaxCryptoSizes.tag,
            outLen,
          ),
        );
        _context.setAll(0, context.asTypedList(_context.length));
        return scope.take(out, outLen.value);
      });

  void dispose() => ProMaxCrypto.wipe(_context);
}

class FileOpener {
  FileOpener._(this._context);

  final Uint8List _context;

  Uint8List chunk(Uint8List ciphertext, {required bool last}) =>
      _run((scope, lib) {
        final context = scope.bytes(_context);
        final out = scope.out(ciphertext.length);
        final outLen = scope.size();
        _check(
          lib.fileOpenChunk(
            context,
            _context.length,
            scope.bytes(ciphertext),
            ciphertext.length,
            last ? 1 : 0,
            out,
            ciphertext.length,
            outLen,
          ),
        );
        _context.setAll(0, context.asTypedList(_context.length));
        return scope.take(out, outLen.value);
      });

  void dispose() => ProMaxCrypto.wipe(_context);
}

abstract final class ProMaxCrypto {
  static String? libraryPath;

  static bool get isAvailable {
    try {
      _Lib.instance;
      return true;
    } on ProMaxCryptoException {
      return false;
    }
  }

  static final Random _secure = Random.secure();

  static Uint8List randomBytes(int length) {
    final out = Uint8List(length);
    for (var index = 0; index < length; index++) {
      out[index] = _secure.nextInt(256);
    }
    return out;
  }

  static void wipe(Uint8List bytes) => bytes.fillRange(0, bytes.length, 0);

  static Uint8List deriveKey(String password) => _run((scope, lib) {
    final bytes = utf8.encode(password);
    final out = scope.out(ProMaxCryptoSizes.key);
    _check(
      lib.deriveKey(
        scope.bytes(Uint8List.fromList(bytes)),
        bytes.length,
        out,
        ProMaxCryptoSizes.key,
      ),
    );
    return scope.take(out, ProMaxCryptoSizes.key);
  });

  static String encryptMessage(
    String plaintext,
    Uint8List key, {
    Uint8List? nonce,
  }) => _run((scope, lib) {
    final bytes = utf8.encode(plaintext);
    final cap = lib.encryptMessageBound(bytes.length);
    final out = scope.out(cap);
    final outLen = scope.size();
    final iv = _randomOr(nonce, ProMaxCryptoSizes.nonce);
    _check(
      lib.encryptMessage(
        scope.bytes(Uint8List.fromList(bytes)),
        bytes.length,
        scope.bytes(key),
        key.length,
        scope.bytes(iv),
        iv.length,
        out,
        cap,
        outLen,
      ),
    );
    return scope.takeText(out, outLen.value);
  });

  static String decryptMessage(String text, Uint8List key) =>
      _run((scope, lib) {
        final bytes = utf8.encode(text);
        final out = scope.out(bytes.length);
        final outLen = scope.size();
        _check(
          lib.decryptMessage(
            scope.bytes(Uint8List.fromList(bytes)),
            bytes.length,
            scope.bytes(key),
            key.length,
            out,
            bytes.length,
            outLen,
          ),
        );
        return scope.takeText(out, outLen.value);
      });

  static bool looksEncryptedMessage(String text) => _run((scope, lib) {
    final bytes = utf8.encode(text);
    return lib.looksEncryptedMessage(
          scope.bytes(Uint8List.fromList(bytes)),
          bytes.length,
        ) !=
        0;
  });

  static Uint8List encryptImageBlob(
    Uint8List plaintext,
    Uint8List key, {
    Uint8List? nonce,
  }) => _run((scope, lib) {
    final cap = lib.encryptImageBound(plaintext.length);
    final out = scope.out(cap);
    final outLen = scope.size();
    final iv = _randomOr(nonce, ProMaxCryptoSizes.nonce);
    _check(
      lib.encryptImage(
        scope.bytes(plaintext),
        plaintext.length,
        scope.bytes(key),
        key.length,
        scope.bytes(iv),
        iv.length,
        out,
        cap,
        outLen,
      ),
    );
    return scope.take(out, outLen.value);
  });

  static Uint8List decryptImageBlob(Uint8List blob, Uint8List key) =>
      _run((scope, lib) {
        final cap = lib.decryptImageBound(blob.length);
        final out = scope.out(cap);
        final outLen = scope.size();
        _check(
          lib.decryptImage(
            scope.bytes(blob),
            blob.length,
            scope.bytes(key),
            key.length,
            out,
            cap,
            outLen,
          ),
        );
        return scope.take(out, outLen.value);
      });

  static bool looksEncryptedImageBlob(Uint8List blob) => _run(
    (scope, lib) => lib.looksEncryptedImage(scope.bytes(blob), blob.length) != 0,
  );

  static Uint8List identityCreate({Uint8List? seed}) => _run((scope, lib) {
    final material = _randomOr(seed, ProMaxCryptoSizes.seed);
    final out = scope.out(ProMaxCryptoSizes.identity);
    final outLen = scope.size();
    _check(
      lib.identityCreate(
        scope.bytes(material),
        material.length,
        out,
        ProMaxCryptoSizes.identity,
        outLen,
      ),
    );
    return scope.take(out, outLen.value);
  });

  static Uint8List identityPublicKey(Uint8List identity) => _run((scope, lib) {
    final out = scope.out(ProMaxCryptoSizes.publicKey);
    final outLen = scope.size();
    _check(
      lib.identityPublicKey(
        scope.bytes(identity),
        identity.length,
        out,
        ProMaxCryptoSizes.publicKey,
        outLen,
      ),
    );
    return scope.take(out, outLen.value);
  });

  static String fingerprint({
    required int myId,
    required Uint8List myPublic,
    required int peerId,
    required Uint8List peerPublic,
  }) => _run((scope, lib) {
    final out = scope.out(ProMaxCryptoSizes.fingerprintDigits);
    final outLen = scope.size();
    _check(
      lib.fingerprint(
        myId,
        scope.bytes(myPublic),
        myPublic.length,
        peerId,
        scope.bytes(peerPublic),
        peerPublic.length,
        out,
        ProMaxCryptoSizes.fingerprintDigits,
        outLen,
      ),
    );
    return ascii.decode(out.asTypedList(outLen.value));
  });

  static TextClass classifyText(String text) => _run((scope, lib) {
    final bytes = utf8.encode(text);
    final code = lib.classifyText(
      scope.bytes(Uint8List.fromList(bytes)),
      bytes.length,
    );
    return TextClass.values[code];
  });

  static HandshakePeek handshakePeek(String text) => _run((scope, lib) {
    final bytes = utf8.encode(text);
    final type = scope.byte();
    final offerId = scope.out(ProMaxCryptoSizes.offerId);
    final publicKey = scope.out(ProMaxCryptoSizes.publicKey);
    _check(
      lib.handshakePeek(
        scope.bytes(Uint8List.fromList(bytes)),
        bytes.length,
        type,
        offerId,
        ProMaxCryptoSizes.offerId,
        publicKey,
        ProMaxCryptoSizes.publicKey,
      ),
    );
    return HandshakePeek(
      type: type.value == 1 ? HandshakeType.offer : HandshakeType.answer,
      offerId: scope.take(offerId, ProMaxCryptoSizes.offerId),
      publicKey: scope.take(publicKey, ProMaxCryptoSizes.publicKey),
    );
  });

  static SessionOffer sessionOffer({
    required Uint8List identity,
    required int chatId,
    required int myId,
    required int peerId,
    Uint8List? random,
  }) => _run((scope, lib) {
    final material = _randomOr(random, ProMaxCryptoSizes.offerRandom);
    final text = scope.out(ProMaxCryptoSizes.handshakeTextBound);
    final textLen = scope.size();
    final pending = scope.out(ProMaxCryptoSizes.pendingState);
    final pendingLen = scope.size();
    _check(
      lib.sessionOffer(
        scope.bytes(identity),
        identity.length,
        chatId,
        myId,
        peerId,
        scope.bytes(material),
        material.length,
        text,
        ProMaxCryptoSizes.handshakeTextBound,
        textLen,
        pending,
        ProMaxCryptoSizes.pendingState,
        pendingLen,
      ),
    );
    return SessionOffer(
      text: scope.takeText(text, textLen.value),
      pending: scope.take(pending, pendingLen.value),
    );
  });

  static SessionAnswer sessionAnswer({
    required Uint8List identity,
    required int chatId,
    required int myId,
    required int peerId,
    required String offerText,
    Uint8List? oldState,
    Uint8List? random,
  }) => _run((scope, lib) {
    final material = _randomOr(random, ProMaxCryptoSizes.answerRandom);
    final offer = utf8.encode(offerText);
    final previous = oldState ?? Uint8List(0);
    final text = scope.out(ProMaxCryptoSizes.handshakeTextBound);
    final textLen = scope.size();
    final state = scope.out(ProMaxCryptoSizes.sessionStateMax);
    final stateLen = scope.size();
    _check(
      lib.sessionAnswer(
        scope.bytes(identity),
        identity.length,
        chatId,
        myId,
        peerId,
        scope.bytes(Uint8List.fromList(offer)),
        offer.length,
        previous.isEmpty ? ffi.nullptr : scope.bytes(previous),
        previous.length,
        scope.bytes(material),
        material.length,
        text,
        ProMaxCryptoSizes.handshakeTextBound,
        textLen,
        state,
        ProMaxCryptoSizes.sessionStateMax,
        stateLen,
      ),
    );
    return SessionAnswer(
      text: scope.takeText(text, textLen.value),
      state: scope.take(state, stateLen.value),
    );
  });

  static Uint8List sessionAccept({
    required Uint8List identity,
    required Uint8List pending,
    required String answerText,
    Uint8List? expectedPeer,
    Uint8List? random,
  }) => _run((scope, lib) {
    final material = _randomOr(random, ProMaxCryptoSizes.acceptRandom);
    final answer = utf8.encode(answerText);
    final pin = expectedPeer ?? Uint8List(0);
    final state = scope.out(ProMaxCryptoSizes.sessionStateMax);
    final stateLen = scope.size();
    _check(
      lib.sessionAccept(
        scope.bytes(identity),
        identity.length,
        scope.bytes(pending),
        pending.length,
        scope.bytes(Uint8List.fromList(answer)),
        answer.length,
        pin.isEmpty ? ffi.nullptr : scope.bytes(pin),
        pin.length,
        scope.bytes(material),
        material.length,
        state,
        ProMaxCryptoSizes.sessionStateMax,
        stateLen,
      ),
    );
    return scope.take(state, stateLen.value);
  });

  static SessionEncrypted sessionEncrypt({
    required Uint8List state,
    required ContentType contentType,
    required Uint8List plaintext,
    Uint8List? random,
  }) => _run((scope, lib) {
    final material = _randomOr(random, ProMaxCryptoSizes.encryptRandom);
    final cap = lib.sessionEncryptBound(plaintext.length);
    if (cap == 0) throw const ProMaxCryptoException(CryptoStatus.tooLong);
    final text = scope.out(cap);
    final textLen = scope.size();
    final nextState = scope.out(ProMaxCryptoSizes.sessionStateMax);
    final nextLen = scope.size();
    _check(
      lib.sessionEncrypt(
        scope.bytes(state),
        state.length,
        contentType.code,
        scope.bytes(plaintext),
        plaintext.length,
        scope.bytes(material),
        material.length,
        text,
        cap,
        textLen,
        nextState,
        ProMaxCryptoSizes.sessionStateMax,
        nextLen,
      ),
    );
    return SessionEncrypted(
      text: scope.takeText(text, textLen.value),
      state: scope.take(nextState, nextLen.value),
    );
  });

  static SessionDecrypted sessionDecrypt({
    required Uint8List state,
    required String text,
  }) => _run((scope, lib) {
    final bytes = utf8.encode(text);
    final contentType = scope.byte();
    final plaintext = scope.out(bytes.length);
    final plaintextLen = scope.size();
    final nextState = scope.out(ProMaxCryptoSizes.sessionStateMax);
    final nextLen = scope.size();
    _check(
      lib.sessionDecrypt(
        scope.bytes(state),
        state.length,
        scope.bytes(Uint8List.fromList(bytes)),
        bytes.length,
        contentType,
        plaintext,
        bytes.length,
        plaintextLen,
        nextState,
        ProMaxCryptoSizes.sessionStateMax,
        nextLen,
      ),
    );
    return SessionDecrypted(
      contentType: ContentType.fromCode(contentType.value),
      plaintext: scope.take(plaintext, plaintextLen.value),
      state: scope.take(nextState, nextLen.value),
    );
  });

  static Uint8List sessionPeerPublicKey(Uint8List state) => _run((scope, lib) {
    final out = scope.out(ProMaxCryptoSizes.publicKey);
    final outLen = scope.size();
    _check(
      lib.sessionPeerPublicKey(
        scope.bytes(state),
        state.length,
        out,
        ProMaxCryptoSizes.publicKey,
        outLen,
      ),
    );
    return scope.take(out, outLen.value);
  });

  static FileSealer fileSealer(Uint8List key, Uint8List nonce) =>
      _run((scope, lib) {
        final context = scope.out(ProMaxCryptoSizes.fileContext);
        _check(
          lib.fileSealInit(
            context,
            ProMaxCryptoSizes.fileContext,
            scope.bytes(key),
            key.length,
            scope.bytes(nonce),
            nonce.length,
          ),
        );
        return FileSealer._(scope.take(context, ProMaxCryptoSizes.fileContext));
      });

  static FileOpener fileOpener(Uint8List key, Uint8List nonce) =>
      _run((scope, lib) {
        final context = scope.out(ProMaxCryptoSizes.fileContext);
        _check(
          lib.fileOpenInit(
            context,
            ProMaxCryptoSizes.fileContext,
            scope.bytes(key),
            key.length,
            scope.bytes(nonce),
            nonce.length,
          ),
        );
        return FileOpener._(scope.take(context, ProMaxCryptoSizes.fileContext));
      });

  static Uint8List localSeal({
    required Uint8List key,
    required Uint8List plaintext,
    Uint8List? nonce,
    Uint8List? aad,
  }) => _run((scope, lib) {
    final iv = _randomOr(nonce, ProMaxCryptoSizes.localNonce);
    final label = aad ?? Uint8List(0);
    final cap =
        plaintext.length + ProMaxCryptoSizes.localNonce + ProMaxCryptoSizes.tag;
    final out = scope.out(cap);
    final outLen = scope.size();
    _check(
      lib.localSeal(
        scope.bytes(key),
        key.length,
        scope.bytes(iv),
        iv.length,
        scope.bytes(label),
        label.length,
        scope.bytes(plaintext),
        plaintext.length,
        out,
        cap,
        outLen,
      ),
    );
    return scope.take(out, outLen.value);
  });

  static Uint8List localOpen({
    required Uint8List key,
    required Uint8List blob,
    Uint8List? aad,
  }) => _run((scope, lib) {
    final label = aad ?? Uint8List(0);
    final out = scope.out(blob.length);
    final outLen = scope.size();
    _check(
      lib.localOpen(
        scope.bytes(key),
        key.length,
        scope.bytes(label),
        label.length,
        scope.bytes(blob),
        blob.length,
        out,
        blob.length,
        outLen,
      ),
    );
    return scope.take(out, outLen.value);
  });

  static Uint8List exportSeal({
    required Uint8List password,
    required int memoryKib,
    required int passes,
    required Uint8List container,
    Uint8List? random,
  }) => _run((scope, lib) {
    final material = _randomOr(random, ProMaxCryptoSizes.exportRandom);
    final cap = lib.exportSealBound(container.length);
    final out = scope.out(cap);
    final outLen = scope.size();
    _check(
      lib.exportSeal(
        scope.bytes(password),
        password.length,
        memoryKib,
        passes,
        scope.bytes(material),
        material.length,
        scope.bytes(container),
        container.length,
        out,
        cap,
        outLen,
      ),
    );
    return scope.take(out, outLen.value);
  });

  static Uint8List exportOpen({
    required Uint8List password,
    required Uint8List blob,
  }) => _run((scope, lib) {
    final cap = lib.exportOpenBound(blob.length);
    final out = scope.out(cap);
    final outLen = scope.size();
    _check(
      lib.exportOpen(
        scope.bytes(password),
        password.length,
        scope.bytes(blob),
        blob.length,
        out,
        cap,
        outLen,
      ),
    );
    return scope.take(out, outLen.value);
  });
}
