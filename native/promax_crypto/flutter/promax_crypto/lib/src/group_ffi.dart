part of 'promax_crypto_ffi.dart';

typedef _GroupDigestNative = ffi.Int32 Function(ffi.Int64, _Bytes,
    ffi.Size, _Bytes, ffi.Size, _SizeOut);
typedef _GroupDigest = int Function(int, _Bytes, int, _Bytes, int, _SizeOut);

typedef _GroupMembersNative = ffi.Int32 Function(
    ffi.Pointer<ffi.Int64>, _Bytes, ffi.Size, _Bytes, ffi.Size, _SizeOut);
typedef _GroupMembers = int Function(
    ffi.Pointer<ffi.Int64>, _Bytes, int, _Bytes, int, _SizeOut);
typedef _GroupSenderNative = ffi.Int32 Function(
    _Bytes,
    ffi.Size,
    ffi.Int64,
    ffi.Int64,
    ffi.Uint64,
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
    _SizeOut);
typedef _GroupSender = int Function(_Bytes, int, int, int, int, _Bytes, int,
    _Bytes, int, _Bytes, int, _Bytes, int, _SizeOut, _Bytes, int, _SizeOut);
typedef _GroupImportNative = ffi.Int32 Function(ffi.Int64, ffi.Int64, _Bytes,
    ffi.Size, _Bytes, ffi.Size, _Bytes, ffi.Size, _Bytes, ffi.Size, _SizeOut);
typedef _GroupImport = int Function(
    int, int, _Bytes, int, _Bytes, int, _Bytes, int, _Bytes, int, _SizeOut);
typedef _GroupEncryptNative = ffi.Int32 Function(_Bytes, ffi.Size, ffi.Uint8,
    _Bytes, ffi.Size, _Bytes, ffi.Size, _SizeOut, _Bytes, ffi.Size, _SizeOut);
typedef _GroupEncrypt = int Function(_Bytes, int, int, _Bytes, int, _Bytes, int,
    _SizeOut, _Bytes, int, _SizeOut);

class _GroupBindings {
  _GroupBindings(_Lib owner)
      : digest = owner.library.lookupFunction<_GroupDigestNative, _GroupDigest>(
            'kc_group_members_digest'),
        members = owner.library
            .lookupFunction<_GroupMembersNative, _GroupMembers>(
                'kc_group_members_build'),
        sender = owner.library.lookupFunction<_GroupSenderNative, _GroupSender>(
            'kc_group_sender_create'),
        receiver = owner.library
            .lookupFunction<_GroupImportNative, _GroupImport>(
                'kc_group_receiver_import'),
        encryptBound = owner.library
            .lookupFunction<_BoundNative, _Bound>('kc_group_encrypt_bound'),
        encrypt = owner.library
            .lookupFunction<_GroupEncryptNative, _GroupEncrypt>(
                'kc_group_encrypt'),
        decryptBound = owner.library
            .lookupFunction<_BoundNative, _Bound>('kc_group_decrypt_bound'),
        decrypt = owner.library
            .lookupFunction<_DecryptNative, _Decrypt>('kc_group_decrypt');

  final _GroupMembers members;
  final _GroupDigest digest;
  final _GroupSender sender;
  final _GroupImport receiver;
  final _Bound encryptBound;
  final _GroupEncrypt encrypt;
  final _Bound decryptBound;
  final _Decrypt decrypt;

  static _Lib? _owner;
  static _GroupBindings? _cached;

  static _GroupBindings forLibrary(_Lib owner) {
    if (identical(_owner, owner)) return _cached!;
    try {
      final bindings = _GroupBindings(owner);
      _owner = owner;
      _cached = bindings;
      return bindings;
    } catch (_) {
      throw const ProMaxCryptoException(CryptoStatus.unavailable);
    }
  }
}

abstract final class ProMaxGroupCrypto {
  static Uint8List membersDigest(int groupId, Uint8List members) =>
      _run((scope, lib) {
        final out = scope.out(ProMaxCryptoSizes.key);
        final length = scope.size();
        _check(_GroupBindings.forLibrary(lib).digest(groupId,
            scope.bytes(members), members.length, out, ProMaxCryptoSizes.key,
            length));
        return scope.take(out, length.value);
      });

  static bool get isAvailable {
    try {
      _GroupBindings.forLibrary(_Lib.instance);
      return true;
    } on ProMaxCryptoException {
      return false;
    }
  }

  static Uint8List membersBuild(List<GroupMember> members) =>
      _run((scope, lib) {
        if (members.length < 2 ||
            members.length > ProMaxCryptoSizes.groupMembersMax ||
            members.any((member) =>
                member.id <= 0 ||
                member.publicKey.length != ProMaxCryptoSizes.publicKey)) {
          throw const ProMaxCryptoException(CryptoStatus.invalidArgument);
        }
        final ids = calloc<ffi.Int64>(members.length);
        scope._plain.add(ids);
        final keys = Uint8List(members.length * ProMaxCryptoSizes.publicKey);
        for (var index = 0; index < members.length; index++) {
          ids[index] = members[index].id;
          keys.setRange(
              index * ProMaxCryptoSizes.publicKey,
              (index + 1) * ProMaxCryptoSizes.publicKey,
              members[index].publicKey);
        }
        final cap = members.length * ProMaxCryptoSizes.groupMember;
        final out = scope.out(cap);
        final length = scope.size();
        _check(_GroupBindings.forLibrary(lib)
            .members(ids, scope.bytes(keys), members.length, out, cap, length));
        return scope.take(out, length.value);
      });

  static GroupSenderKey senderCreate({
    required Uint8List identity,
    required int groupId,
    required int senderId,
    required int epoch,
    required Uint8List members,
    Uint8List? oldState,
    Uint8List? random,
  }) =>
      _run((scope, lib) {
        if (epoch <= 0) {
          throw const ProMaxCryptoException(CryptoStatus.invalidArgument);
        }
        final material = _randomOr(random, ProMaxCryptoSizes.groupRandom);
        try {
          final previous = oldState ?? Uint8List(0);
          final distribution = scope.out(ProMaxCryptoSizes.groupDistribution);
          final distributionLen = scope.size();
          final state = scope.out(ProMaxCryptoSizes.groupStateMax);
          final stateLen = scope.size();
          _check(_GroupBindings.forLibrary(lib).sender(
              scope.bytes(identity),
              identity.length,
              groupId,
              senderId,
              epoch,
              scope.bytes(members),
              members.length,
              scope.bytes(material),
              material.length,
              previous.isEmpty ? ffi.nullptr : scope.bytes(previous),
              previous.length,
              distribution,
              ProMaxCryptoSizes.groupDistribution,
              distributionLen,
              state,
              ProMaxCryptoSizes.groupStateMax,
              stateLen));
          return GroupSenderKey(
              distribution: scope.take(distribution, distributionLen.value),
              state: scope.take(state, stateLen.value));
        } finally {
          if (random == null) ProMaxCrypto.wipe(material);
        }
      });

  static Uint8List receiverImport({
    required int groupId,
    required int senderId,
    required Uint8List members,
    required Uint8List distribution,
    Uint8List? oldState,
  }) =>
      _run((scope, lib) {
        final previous = oldState ?? Uint8List(0);
        final state = scope.out(ProMaxCryptoSizes.groupStateMax);
        final stateLen = scope.size();
        _check(_GroupBindings.forLibrary(lib).receiver(
            groupId,
            senderId,
            scope.bytes(members),
            members.length,
            scope.bytes(distribution),
            distribution.length,
            previous.isEmpty ? ffi.nullptr : scope.bytes(previous),
            previous.length,
            state,
            ProMaxCryptoSizes.groupStateMax,
            stateLen));
        return scope.take(state, stateLen.value);
      });

  static GroupEncrypted encrypt({
    required Uint8List state,
    required ContentType contentType,
    required Uint8List plaintext,
  }) =>
      _run((scope, lib) {
        final bindings = _GroupBindings.forLibrary(lib);
        final cap = bindings.encryptBound(plaintext.length);
        if (cap == 0) {
          throw const ProMaxCryptoException(CryptoStatus.tooLong);
        }
        final envelope = scope.out(cap);
        final envelopeLen = scope.size();
        final nextState = scope.out(ProMaxCryptoSizes.groupStateMax);
        final nextLen = scope.size();
        _check(bindings.encrypt(
            scope.bytes(state),
            state.length,
            contentType.code,
            scope.bytes(plaintext),
            plaintext.length,
            envelope,
            cap,
            envelopeLen,
            nextState,
            ProMaxCryptoSizes.groupStateMax,
            nextLen));
        return GroupEncrypted(
            envelope: scope.take(envelope, envelopeLen.value),
            state: scope.take(nextState, nextLen.value));
      });

  static SessionDecrypted decrypt({
    required Uint8List state,
    required Uint8List envelope,
  }) =>
      _run((scope, lib) {
        if (envelope.length > ProMaxCryptoSizes.groupPlaintextMax + 145) {
          throw const ProMaxCryptoException(CryptoStatus.tooLong);
        }
        final bindings = _GroupBindings.forLibrary(lib);
        final cap = bindings.decryptBound(envelope.length);
        final contentType = scope.byte();
        final plaintext = scope.out(cap);
        final plaintextLen = scope.size();
        final nextState = scope.out(ProMaxCryptoSizes.groupStateMax);
        final nextLen = scope.size();
        _check(bindings.decrypt(
            scope.bytes(state),
            state.length,
            scope.bytes(envelope),
            envelope.length,
            contentType,
            plaintext,
            cap,
            plaintextLen,
            nextState,
            ProMaxCryptoSizes.groupStateMax,
            nextLen));
        return SessionDecrypted(
            contentType: ContentType.fromCode(contentType.value),
            plaintext: scope.take(plaintext, plaintextLen.value),
            state: scope.take(nextState, nextLen.value));
      });
}
