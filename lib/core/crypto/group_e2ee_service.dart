import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:promax_crypto/promax_crypto.dart';

import '../../backend/modules/chats.dart';
import '../../backend/modules/messages.dart';
import '../../main.dart' show api, messagesModule;
import '../storage/app_database.dart';
import '../storage/token_storage.dart';
import 'e2ee_service.dart';

enum GroupEncryptionBlock {
  unavailable,
  membership,
  verification,
  consent,
  keys,
  changed,
  transport,
}

class GroupEncryptionException implements Exception {
  const GroupEncryptionException(this.reason);

  final GroupEncryptionBlock reason;
}

class GroupEncryptionPeer {
  const GroupEncryptionPeer({
    required this.id,
    required this.publicKey,
    required this.dialogId,
  });

  final int id;
  final Uint8List publicKey;
  final int dialogId;
}

class GroupEncryptionRoster {
  const GroupEncryptionRoster(this.peers, this.manifest, this.digest);

  final List<GroupEncryptionPeer> peers;
  final Uint8List manifest;
  final String digest;

  List<int> get ids => peers.map((peer) => peer.id).toList();
  int get coordinator => peers.first.id;
}

class GroupEncryptionInfo {
  const GroupEncryptionInfo({
    this.required = false,
    this.epoch = 0,
    this.memberCount = 0,
    this.consentCount = 0,
    this.keyCount = 0,
    this.consented = false,
    this.ready = false,
    this.proposalReceived = false,
    this.canRetry = false,
    this.block,
    this.coordinator = 0,
  });

  final bool required;
  final int epoch;
  final int memberCount;
  final int consentCount;
  final int keyCount;
  final bool consented;
  final bool ready;
  final bool proposalReceived;
  final bool canRetry;
  final int coordinator;
  final GroupEncryptionBlock? block;
}

abstract interface class GroupEncryptionEnvironment {
  bool get available;
  Future<GroupEncryptionRoster> roster(int accountId, int groupId);
  Future<Uint8List> identity(int accountId);
  Future<String?> load(int accountId, int groupId);
  Future<void> save(
    int accountId,
    int groupId,
    String state,
    CachedMessage? message,
  );
  Future<void> send(
    int accountId,
    GroupEncryptionPeer peer,
    Uint8List payload, {
    void Function()? beforeSend,
  });
  Future<Uint8List> sealMessage(
    int accountId,
    int groupId,
    Uint8List plaintext,
  );
}

abstract interface class GroupEncryptionNative {
  GroupSenderKey create(
    Uint8List identity,
    int groupId,
    int senderId,
    int epoch,
    Uint8List manifest,
    Uint8List? oldState,
  );
  Uint8List import(
    int groupId,
    int senderId,
    Uint8List manifest,
    Uint8List distribution,
    Uint8List? oldState,
  );
  GroupEncrypted encrypt(
    Uint8List state,
    ContentType type,
    Uint8List plaintext,
  );
  SessionDecrypted decrypt(Uint8List state, Uint8List envelope);
}

class _GroupNative implements GroupEncryptionNative {
  const _GroupNative();

  @override
  GroupSenderKey create(
    Uint8List identity,
    int groupId,
    int senderId,
    int epoch,
    Uint8List manifest,
    Uint8List? oldState,
  ) => ProMaxGroupCrypto.senderCreate(
    identity: identity,
    groupId: groupId,
    senderId: senderId,
    epoch: epoch,
    members: manifest,
    oldState: oldState,
  );

  @override
  Uint8List import(
    int groupId,
    int senderId,
    Uint8List manifest,
    Uint8List distribution,
    Uint8List? oldState,
  ) => ProMaxGroupCrypto.receiverImport(
    groupId: groupId,
    senderId: senderId,
    members: manifest,
    distribution: distribution,
    oldState: oldState,
  );

  @override
  GroupEncrypted encrypt(
    Uint8List state,
    ContentType type,
    Uint8List plaintext,
  ) => ProMaxGroupCrypto.encrypt(
    state: state,
    contentType: type,
    plaintext: plaintext,
  );

  @override
  SessionDecrypted decrypt(Uint8List state, Uint8List envelope) =>
      ProMaxGroupCrypto.decrypt(state: state, envelope: envelope);
}

class _GroupState {
  _GroupState({
    required this.epoch,
    required this.digest,
    required this.members,
    required this.coordinator,
    this.required = false,
    this.block,
  });

  final int epoch;
  final String digest;
  final List<int> members;
  final int coordinator;
  bool required;
  bool pendingInitiation = false;
  bool proposalReceived = true;
  GroupEncryptionBlock? block;
  int generation = 0;
  final Set<int> consent = {};
  final Map<int, Uint8List> receivers = {};
  Uint8List? sender;
  Uint8List? pendingDistribution;
  final Set<int> pendingRecipients = {};
  final Map<String, Set<int>> pendingControls = {};
  final List<String> seen = [];
  final List<String> outbound = [];

  bool ready(int accountId) =>
      required &&
      block == null &&
      sender != null &&
      pendingDistribution == null &&
      pendingControls.isEmpty &&
      members.every(consent.contains) &&
      members.where((id) => id != accountId).every(receivers.containsKey);

  GroupEncryptionInfo info(int accountId) => GroupEncryptionInfo(
    required: required,
    epoch: epoch,
    memberCount: members.length,
    consentCount: consent.length,
    keyCount: receivers.length + (sender == null ? 0 : 1),
    consented: consent.contains(accountId),
    ready: ready(accountId),
    proposalReceived: proposalReceived,
    canRetry:
        (pendingDistribution != null || pendingControls.isNotEmpty) &&
        (block == null || block == GroupEncryptionBlock.transport),
    block: block,
    coordinator: coordinator,
  );

  Map<String, Object?> toJson() => {
    'v': 1,
    'e': epoch,
    'd': digest,
    'm': members,
    'c': coordinator,
    'required': required,
    'pendingInitiation': pendingInitiation,
    'proposalReceived': proposalReceived,
    'block': block?.name,
    'consent': consent.toList(),
    'sender': sender == null ? null : base64Encode(sender!),
    'pendingDistribution': pendingDistribution == null
        ? null
        : base64Encode(pendingDistribution!),
    'pendingRecipients': pendingRecipients.toList(),
    'pendingControls': pendingControls.map(
      (type, ids) => MapEntry(type, ids.toList()),
    ),
    'receivers': receivers.map(
      (id, state) => MapEntry('$id', base64Encode(state)),
    ),
    'seen': seen,
    'outbound': outbound,
  };

  static _GroupState parse(String encoded, int accountId) {
    if (encoded.length > 4 * 1024 * 1024) {
      throw const FormatException('Group state too large');
    }
    final json = jsonDecode(encoded) as Map<String, dynamic>;
    final members = (json['m'] as List).cast<int>();
    final epoch = json['e'] as int;
    final digest = json['d'] as String;
    if (json['v'] != 1 ||
        epoch <= 0 ||
        members.length < 2 ||
        members.length > ProMaxCryptoSizes.groupMembersMax ||
        !members.contains(accountId) ||
        base64Decode(digest).length != 32 ||
        members.toSet().length != members.length ||
        members.any((id) => id <= 0) ||
        !listEquals(members, [...members]..sort()) ||
        json['c'] != members.first) {
      throw const FormatException('Invalid group state');
    }
    final state = _GroupState(
      epoch: epoch,
      digest: digest,
      members: members,
      coordinator: members.first,
      required: json['required'] == true,
      block: json['block'] == null
          ? null
          : GroupEncryptionBlock.values.byName(json['block'] as String),
    );
    state.pendingInitiation = json['pendingInitiation'] == true;
    state.proposalReceived = json['proposalReceived'] != false;
    state.consent.addAll((json['consent'] as List).cast<int>());
    if (!state.consent.every(members.contains)) {
      throw const FormatException('Invalid group consent');
    }
    Uint8List decodeState(String text) {
      final bytes = base64Decode(text);
      if (bytes.isEmpty || bytes.length > ProMaxCryptoSizes.groupStateMax) {
        throw const FormatException('Invalid sender state');
      }
      return bytes;
    }

    if (json['sender'] is String) {
      state.sender = decodeState(json['sender'] as String);
    }
    if (json['pendingDistribution'] is String) {
      state.pendingDistribution = base64Decode(
        json['pendingDistribution'] as String,
      );
      if (state.pendingDistribution!.length !=
              ProMaxCryptoSizes.groupDistribution ||
          state.sender == null) {
        throw const FormatException('Invalid pending group key');
      }
    }
    state.pendingRecipients.addAll(
      (json['pendingRecipients'] as List? ?? const []).cast<int>(),
    );
    if (!state.pendingRecipients.every(
          (id) => id != accountId && members.contains(id),
        ) ||
        (state.pendingRecipients.isNotEmpty &&
            state.pendingDistribution == null)) {
      throw const FormatException('Invalid pending group recipients');
    }
    final controls = json['pendingControls'] as Map<String, dynamic>? ?? {};
    for (final entry in controls.entries) {
      if (!const {'invite', 'proposal', 'consent'}.contains(entry.key)) {
        throw const FormatException('Invalid pending group control');
      }
      final ids = (entry.value as List).cast<int>().toSet();
      if (ids.isEmpty ||
          !ids.every((id) => id != accountId && members.contains(id)) ||
          (entry.key == 'invite' &&
              (accountId == state.coordinator ||
                  ids.length != 1 ||
                  !ids.contains(state.coordinator))) ||
          (entry.key == 'invite' &&
              (!state.pendingInitiation ||
                  state.consent.contains(accountId))) ||
          (entry.key == 'proposal' &&
              (accountId != state.coordinator ||
                  !state.consent.contains(accountId))) ||
          (entry.key == 'consent' && !state.consent.contains(accountId)) ||
          !state.required) {
        throw const FormatException('Invalid pending group control');
      }
      state.pendingControls[entry.key] = ids;
    }
    for (final entry in (json['receivers'] as Map<String, dynamic>).entries) {
      final id = int.parse(entry.key);
      if (id == accountId || !members.contains(id)) {
        throw const FormatException('Invalid receiver');
      }
      state.receivers[id] = decodeState(entry.value as String);
    }
    state.seen.addAll((json['seen'] as List).cast<String>().take(512));
    state.outbound.addAll(
      (json['outbound'] as List? ?? const [])
          .cast<String>()
          .where(
            (wire) =>
                wire.startsWith(GroupE2eeService.wirePrefix) &&
                wire.length <= ProMaxCryptoSizes.textTransportMax,
          )
          .take(64),
    );
    return state;
  }

  void wipe() {
    if (sender != null) ProMaxCrypto.wipe(sender!);
    if (pendingDistribution != null) ProMaxCrypto.wipe(pendingDistribution!);
    pendingDistribution = null;
    pendingRecipients.clear();
    pendingControls.clear();
    for (final state in receivers.values) {
      ProMaxCrypto.wipe(state);
    }
    receivers.clear();
    sender = null;
  }
}

class GroupE2eeService {
  GroupE2eeService({
    required GroupEncryptionEnvironment environment,
    GroupEncryptionNative native = const _GroupNative(),
  }) : _environment = environment,
       _native = native;

  static final instance = GroupE2eeService(environment: _GroupEnvironment());
  static const wirePrefix = 'PMXG1:';
  static const controlKind = 'promax-group-v1';
  final GroupEncryptionEnvironment _environment;
  final GroupEncryptionNative _native;
  final ValueNotifier<int> revision = ValueNotifier(0);
  final Map<String, _GroupState?> _states = {};
  final Map<String, Future<void>> _chains = {};
  final Object _generationKey = Object();
  int _generation = 0;
  int get _operationGeneration =>
      Zone.current[_generationKey] as int? ?? _generation;

  bool get available => _environment.available;
  E2eeControlHandler? _controlHandler;

  void attach() {
    if (_controlHandler != null) return;
    Future<void> handler(E2eeControlMessage message) async {
      if (!message.verified) return;
      await handleControl(
        message.accountId,
        message.peerId,
        message.messageId,
        message.plaintext,
      );
    }

    _controlHandler = handler;
    E2eeService.instance.registerControlHandler(controlKind, handler);
  }

  String _key(int accountId, int groupId) => '$accountId/$groupId';
  GroupEncryptionInfo info(int accountId, int groupId) =>
      _states[_key(accountId, groupId)]?.info(accountId) ??
      const GroupEncryptionInfo();
  bool isOn(int accountId, int groupId) => info(accountId, groupId).required;

  Future<void> assertSendAllowed(
    int accountId,
    int groupId,
    String text, {
    bool hasAttachments = false,
  }) async {
    await ensureLoaded(accountId, groupId);
    assertPrepared(accountId, groupId, text, hasAttachments: hasAttachments);
  }

  void assertPrepared(
    int accountId,
    int groupId,
    String text, {
    bool hasAttachments = false,
  }) {
    final state = _states[_key(accountId, groupId)];
    if (!(state?.required ?? false) && !text.startsWith(wirePrefix)) return;
    if (hasAttachments) {
      throw const GroupEncryptionException(GroupEncryptionBlock.transport);
    }
    if (state == null ||
        !state.ready(accountId) ||
        !state.outbound.contains(text)) {
      throw GroupEncryptionException(state?.block ?? GroupEncryptionBlock.keys);
    }
  }

  Future<T> _serial<T>(int accountId, int groupId, Future<T> Function() body) {
    final key = _key(accountId, groupId);
    final previous = _chains[key] ?? Future<void>.value();
    final generation = _generation;
    final next = previous.then((_) {
      if (generation != _generation) {
        throw const GroupEncryptionException(GroupEncryptionBlock.unavailable);
      }
      return runZoned(body, zoneValues: {_generationKey: generation});
    });
    final tail = next.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    _chains[key] = tail;
    unawaited(
      tail.then((_) {
        if (identical(_chains[key], tail)) _chains.remove(key);
      }),
    );
    return next;
  }

  Future<void> ensureLoaded(int accountId, int groupId) =>
      _serial(accountId, groupId, () => _load(accountId, groupId));

  Future<void> _load(int accountId, int groupId) async {
    final key = _key(accountId, groupId);
    if (_states.containsKey(key)) return;
    final generation = _operationGeneration;
    final encoded = await _environment.load(accountId, groupId);
    if (generation != _generation) {
      throw const GroupEncryptionException(GroupEncryptionBlock.unavailable);
    }
    final loaded = encoded == null
        ? null
        : _GroupState.parse(encoded, accountId);
    loaded?.generation = generation;
    _states[key] = loaded;
    revision.value++;
  }

  Future<void> _save(
    int accountId,
    int groupId,
    _GroupState state, {
    CachedMessage? message,
  }) async {
    final generation = state.generation;
    if (generation != _generation) {
      state.wipe();
      throw const GroupEncryptionException(GroupEncryptionBlock.unavailable);
    }
    try {
      await _environment.save(
        accountId,
        groupId,
        jsonEncode(state.toJson()),
        message,
      );
    } catch (_) {
      state.block = GroupEncryptionBlock.transport;
      if (generation == _generation) {
        _states[_key(accountId, groupId)] = state;
        revision.value++;
      }
      rethrow;
    }
    if (generation != _generation) {
      throw const GroupEncryptionException(GroupEncryptionBlock.unavailable);
    }
    _states[_key(accountId, groupId)] = state;
    revision.value++;
  }

  Future<GroupEncryptionRoster> _check(
    int accountId,
    int groupId,
    _GroupState state,
  ) async {
    final GroupEncryptionRoster roster;
    try {
      roster = await _environment.roster(accountId, groupId);
    } on GroupEncryptionException catch (error) {
      state.block = error.reason;
      await _save(accountId, groupId, state);
      rethrow;
    }
    if (roster.digest != state.digest ||
        !listEquals(roster.ids, state.members)) {
      state.block = GroupEncryptionBlock.changed;
      await _save(accountId, groupId, state);
      throw const GroupEncryptionException(GroupEncryptionBlock.changed);
    }
    return roster;
  }

  Uint8List _control(
    String type,
    int groupId,
    _GroupState state, {
    Uint8List? distribution,
  }) => Uint8List.fromList(
    utf8.encode(
      jsonEncode({
        'p': controlKind,
        't': type,
        'g': groupId,
        'e': state.epoch,
        'd': state.digest,
        if (distribution != null) 'k': base64Encode(distribution),
      }),
    ),
  );

  Future<void> _broadcast(
    int accountId,
    int groupId,
    _GroupState state,
    GroupEncryptionRoster roster,
    String type, {
    Uint8List? distribution,
  }) async {
    final payload = _control(type, groupId, state, distribution: distribution);
    try {
      if (payload.length > ProMaxCryptoSizes.sessionPlaintextMax) {
        throw const GroupEncryptionException(GroupEncryptionBlock.transport);
      }
      for (final peer in roster.peers.where((peer) => peer.id != accountId)) {
        await _environment.send(accountId, peer, payload);
      }
    } finally {
      ProMaxCrypto.wipe(payload);
    }
  }

  Future<void> begin(int accountId, int groupId) => _serial(
    accountId,
    groupId,
    () async {
      if (!available) {
        throw const GroupEncryptionException(GroupEncryptionBlock.unavailable);
      }
      await _load(accountId, groupId);
      final roster = await _environment.roster(accountId, groupId);
      final previous = _states[_key(accountId, groupId)];
      if (previous != null && previous.epoch >= 0x7ffffffffffffffe) {
        throw const GroupEncryptionException(GroupEncryptionBlock.unavailable);
      }
      final state = _GroupState(
        epoch: (previous?.epoch ?? 0) + 1,
        digest: roster.digest,
        members: roster.ids,
        coordinator: roster.coordinator,
        required: true,
      );
      state.pendingInitiation = accountId != roster.coordinator;
      state.proposalReceived = accountId == roster.coordinator;
      state.generation = _operationGeneration;
      previous?.wipe();
      if (accountId != roster.coordinator) {
        state.pendingControls['invite'] = {roster.coordinator};
        await _save(accountId, groupId, state);
        await _sendPendingControls(accountId, groupId, state);
        return;
      }
      await _accept(accountId, groupId, state, roster, announce: true);
    },
  );

  Future<void> accept(int accountId, int groupId) =>
      _serial(accountId, groupId, () async {
        await _load(accountId, groupId);
        final state = _states[_key(accountId, groupId)];
        if (state == null ||
            state.block != null ||
            (!state.proposalReceived && accountId != state.coordinator)) {
          throw const GroupEncryptionException(GroupEncryptionBlock.changed);
        }
        final roster = await _check(accountId, groupId, state);
        await _accept(
          accountId,
          groupId,
          state,
          roster,
          announce: accountId == state.coordinator,
        );
      });

  Future<void> _accept(
    int accountId,
    int groupId,
    _GroupState state,
    GroupEncryptionRoster roster, {
    required bool announce,
  }) async {
    state.required = true;
    state.proposalReceived = true;
    state.consent.add(accountId);
    final recipients = state.members.where((id) => id != accountId).toSet();
    if (announce) state.pendingControls['proposal'] = {...recipients};
    state.pendingControls['consent'] = {...recipients};
    await _save(accountId, groupId, state);
    await _sendPendingControls(accountId, groupId, state);
    await _finish(accountId, groupId, state, roster);
  }

  Future<void> _sendPendingControls(
    int accountId,
    int groupId,
    _GroupState state,
  ) async {
    try {
      for (final type in state.pendingControls.keys.toList()) {
        for (final id in state.pendingControls[type]!.toList()) {
          final roster = await _check(accountId, groupId, state);
          if (state.block != null) {
            throw GroupEncryptionException(state.block!);
          }
          final payload = _control(type, groupId, state);
          try {
            await _environment.send(
              accountId,
              roster.peers.firstWhere((peer) => peer.id == id),
              payload,
              beforeSend: () {
                if (state.generation != _generation || state.block != null) {
                  throw GroupEncryptionException(
                    state.block ?? GroupEncryptionBlock.unavailable,
                  );
                }
              },
            );
          } finally {
            ProMaxCrypto.wipe(payload);
          }
          state.pendingControls[type]!.remove(id);
          if (state.pendingControls[type]!.isEmpty) {
            state.pendingControls.remove(type);
          }
          try {
            await _save(accountId, groupId, state);
          } catch (_) {
            state.pendingControls.putIfAbsent(type, () => {}).add(id);
            rethrow;
          }
        }
      }
    } catch (_) {
      state.block ??= GroupEncryptionBlock.transport;
      await _save(accountId, groupId, state);
      rethrow;
    }
  }

  Future<void> _finish(
    int accountId,
    int groupId,
    _GroupState state,
    GroupEncryptionRoster roster,
  ) async {
    if (!state.required ||
        state.block != null ||
        state.pendingControls.isNotEmpty ||
        !state.members.every(state.consent.contains)) {
      return;
    }
    if (state.sender == null) {
      final identity = await _environment.identity(accountId);
      final GroupSenderKey result;
      try {
        result = _native.create(
          identity,
          groupId,
          accountId,
          state.epoch,
          roster.manifest,
          null,
        );
      } finally {
        ProMaxCrypto.wipe(identity);
      }
      state.sender = result.state;
      state.pendingDistribution = result.distribution;
      state.pendingRecipients.addAll(
        state.members.where((id) => id != accountId),
      );
      await _save(accountId, groupId, state);
    }
    final distribution = state.pendingDistribution;
    if (distribution == null) return;
    try {
      for (final id in state.pendingRecipients.toList()) {
        final current = await _check(accountId, groupId, state);
        if (state.block != null) {
          throw GroupEncryptionException(state.block!);
        }
        final peer = current.peers.firstWhere((peer) => peer.id == id);
        final payload = _control(
          'key',
          groupId,
          state,
          distribution: distribution,
        );
        try {
          await _environment.send(
            accountId,
            peer,
            payload,
            beforeSend: () {
              if (state.generation != _generation || state.block != null) {
                throw GroupEncryptionException(
                  state.block ?? GroupEncryptionBlock.unavailable,
                );
              }
            },
          );
        } finally {
          ProMaxCrypto.wipe(payload);
        }
        state.pendingRecipients.remove(id);
        await _save(accountId, groupId, state);
      }
    } catch (_) {
      state.block ??= GroupEncryptionBlock.transport;
      await _save(accountId, groupId, state);
      rethrow;
    }
    state.pendingDistribution = null;
    ProMaxCrypto.wipe(distribution);
    await _save(accountId, groupId, state);
  }

  Future<void> retry(
    int accountId,
    int groupId,
  ) => _serial(accountId, groupId, () async {
    await _load(accountId, groupId);
    final state = _states[_key(accountId, groupId)];
    if (state == null ||
        (state.pendingDistribution == null && state.pendingControls.isEmpty) ||
        (state.block != null &&
            state.block != GroupEncryptionBlock.transport)) {
      throw const GroupEncryptionException(GroupEncryptionBlock.unavailable);
    }
    final roster = await _check(accountId, groupId, state);
    state.block = null;
    await _save(accountId, groupId, state);
    await _sendPendingControls(accountId, groupId, state);
    await _finish(accountId, groupId, state, roster);
  });

  Future<void> handleControl(
    int accountId,
    int senderId,
    String messageId,
    Uint8List plaintext,
  ) async {
    if (!available ||
        plaintext.length > ProMaxCryptoSizes.sessionPlaintextMax) {
      return;
    }
    final Object? decoded;
    try {
      decoded = jsonDecode(utf8.decode(plaintext));
    } on FormatException {
      return;
    }
    if (decoded is! Map<String, dynamic> || decoded['p'] != controlKind) return;
    final groupId = decoded['g'];
    final epoch = decoded['e'];
    final digest = decoded['d'];
    final type = decoded['t'];
    if (groupId is! int ||
        groupId == 0 ||
        epoch is! int ||
        epoch <= 0 ||
        epoch > 0x7ffffffffffffffe ||
        digest is! String ||
        digest.length != 44 ||
        !const {
          'invite',
          'proposal',
          'consent',
          'key',
          'stop',
        }.contains(type)) {
      return;
    }
    final control = decoded;
    await _serial(accountId, groupId, () async {
      await _load(accountId, groupId);
      final roster = await _environment.roster(accountId, groupId);
      if (!roster.ids.contains(senderId) ||
          senderId == accountId ||
          digest != roster.digest) {
        return;
      }
      var state = _states[_key(accountId, groupId)];
      var acceptInitiatedProposal = false;
      final marker = '$senderId/$messageId';
      if (state?.seen.contains(marker) ?? false) return;
      if (state == null && (type == 'consent' || type == 'key')) {
        state = _GroupState(
          epoch: epoch,
          digest: digest,
          members: roster.ids,
          coordinator: roster.coordinator,
        );
        state.proposalReceived = false;
        state.generation = _operationGeneration;
      }
      if (type == 'invite') {
        if (accountId != roster.coordinator ||
            (state != null && state.block == null && state.epoch >= epoch)) {
          return;
        }
        state?.wipe();
        state = _GroupState(
          epoch: (state?.epoch ?? 0) + 1,
          digest: digest,
          members: roster.ids,
          coordinator: roster.coordinator,
        );
        state.generation = _operationGeneration;
      } else if (type == 'proposal') {
        if (senderId != roster.coordinator ||
            (state != null && state.proposalReceived && epoch < state.epoch)) {
          return;
        }
        if (state == null ||
            epoch > state.epoch ||
            (!state.proposalReceived && epoch != state.epoch)) {
          final required = state?.required ?? false;
          state?.wipe();
          state = _GroupState(
            epoch: epoch,
            digest: digest,
            members: roster.ids,
            coordinator: roster.coordinator,
            required: required,
          );
          state.generation = _operationGeneration;
        } else if (state.digest != digest) {
          state.block = GroupEncryptionBlock.changed;
        } else if (state.pendingInitiation && state.required) {
          state.pendingInitiation = false;
          state.pendingControls.remove('invite');
          acceptInitiatedProposal = true;
        }
        state.proposalReceived = true;
      } else {
        if (state == null ||
            state.epoch != epoch ||
            state.digest != digest ||
            (state.block != null &&
                state.block != GroupEncryptionBlock.transport)) {
          return;
        }
        if (type == 'stop') {
          state.block = GroupEncryptionBlock.consent;
          state.wipe();
        } else if (type == 'consent') {
          state.consent.add(senderId);
        } else if (type == 'key') {
          if (control['k'] is! String ||
              state.receivers.containsKey(senderId)) {
            return;
          }
          final encoded = control['k'] as String;
          if (encoded.length !=
              ((ProMaxCryptoSizes.groupDistribution + 2) ~/ 3) * 4) {
            return;
          }
          final Uint8List distribution;
          try {
            distribution = base64Decode(encoded);
          } on FormatException {
            return;
          }
          try {
            if (distribution.length != ProMaxCryptoSizes.groupDistribution) {
              return;
            }
            if (ByteData.sublistView(distribution).getUint64(12, Endian.big) !=
                epoch) {
              return;
            }
            try {
              state.receivers[senderId] = _native.import(
                groupId,
                senderId,
                roster.manifest,
                distribution,
                null,
              );
            } on ProMaxCryptoException {
              return;
            }
            state.consent.add(senderId);
          } finally {
            ProMaxCrypto.wipe(distribution);
          }
        }
      }
      state.seen.add(marker);
      if (state.seen.length > 512) state.seen.removeAt(0);
      await _save(accountId, groupId, state);
      if (acceptInitiatedProposal) {
        await _accept(accountId, groupId, state, roster, announce: false);
        return;
      }
      await _finish(accountId, groupId, state, roster);
    });
  }

  Future<void> disable(int accountId, int groupId) =>
      _serial(accountId, groupId, () async {
        await _load(accountId, groupId);
        final state = _states[_key(accountId, groupId)];
        if (state == null) return;
        state.required = false;
        state.block = GroupEncryptionBlock.consent;
        state.wipe();
        await _save(accountId, groupId, state);
        final roster = await _environment.roster(accountId, groupId);
        if (roster.digest == state.digest) {
          await _broadcast(accountId, groupId, state, roster, 'stop');
        }
      });

  void membershipChanged(int accountId, int groupId) {
    final state = _states[_key(accountId, groupId)];
    if (state == null) return;
    state.block = GroupEncryptionBlock.changed;
    revision.value++;
    unawaited(
      _serial(
        accountId,
        groupId,
        () => _save(accountId, groupId, state),
      ).catchError((Object _) {}),
    );
  }

  Future<String> encryptText(int accountId, int groupId, String text) =>
      encryptBytes(
        accountId,
        groupId,
        ContentType.text,
        Uint8List.fromList(utf8.encode(text)),
      );

  Future<String> encryptBytes(
    int accountId,
    int groupId,
    ContentType type,
    Uint8List plaintext,
  ) => _serial(accountId, groupId, () async {
    await _load(accountId, groupId);
    final state = _states[_key(accountId, groupId)];
    if (state == null || !state.required) {
      throw const GroupEncryptionException(GroupEncryptionBlock.consent);
    }
    await _check(accountId, groupId, state);
    if (!state.ready(accountId)) {
      throw GroupEncryptionException(
        state.block ??
            (state.members.every(state.consent.contains)
                ? GroupEncryptionBlock.keys
                : GroupEncryptionBlock.consent),
      );
    }
    final bytes = Uint8List.fromList(plaintext);
    try {
      final result = _native.encrypt(state.sender!, type, bytes);
      final wire = '$wirePrefix${base64Encode(result.envelope)}';
      if (wire.length > ProMaxCryptoSizes.textTransportMax) {
        ProMaxCrypto.wipe(result.state);
        throw const GroupEncryptionException(GroupEncryptionBlock.transport);
      }
      final old = state.sender;
      state.sender = result.state;
      state.outbound.add(wire);
      if (state.outbound.length > 64) state.outbound.removeAt(0);
      try {
        await _save(accountId, groupId, state);
      } catch (_) {
        state.block = GroupEncryptionBlock.transport;
        rethrow;
      } finally {
        if (old != null) ProMaxCrypto.wipe(old);
      }
      if (!state.ready(accountId)) {
        throw const GroupEncryptionException(GroupEncryptionBlock.changed);
      }
      return wire;
    } finally {
      ProMaxCrypto.wipe(bytes);
    }
  });

  Future<CachedMessage> inspect(CachedMessage message) =>
      _serial(message.accountId, message.chatId, () async {
        final text = message.text;
        if (text == null ||
            !text.startsWith(wirePrefix) ||
            text.length > ProMaxCryptoSizes.textTransportMax) {
          return message;
        }
        await _load(message.accountId, message.chatId);
        final stored = await AppDatabase.loadMessage(
          message.accountId,
          message.chatId,
          message.id,
        );
        if (stored != null &&
            stored['text'] == text &&
            stored['e2ee'] == CachedMessage.e2eeText &&
            stored['text_sealed'] is Uint8List) {
          return message.copyWith(
            e2ee: CachedMessage.e2eeText,
            sealedText: stored['text_sealed'] as Uint8List,
          );
        }
        final state = _states[_key(message.accountId, message.chatId)];
        final receiveState = state?.receivers[message.senderId];
        if (state == null || receiveState == null) {
          return message.copyWith(e2ee: CachedMessage.e2eeFailed);
        }
        Uint8List? plaintext;
        try {
          final envelope = base64Decode(text.substring(wirePrefix.length));
          final result = _native.decrypt(receiveState, envelope);
          plaintext = result.plaintext;
          if (result.contentType != ContentType.text &&
              result.contentType != ContentType.file) {
            ProMaxCrypto.wipe(result.state);
            return message.copyWith(e2ee: CachedMessage.e2eeFailed);
          }
          final sealed = await _environment.sealMessage(
            message.accountId,
            message.chatId,
            plaintext,
          );
          final decrypted = message.copyWith(
            e2ee: result.contentType == ContentType.file
                ? CachedMessage.e2eeFile
                : CachedMessage.e2eeText,
            sealedText: sealed,
          );
          state.receivers[message.senderId] = result.state;
          await _save(
            message.accountId,
            message.chatId,
            state,
            message: decrypted,
          );
          ProMaxCrypto.wipe(receiveState);
          return decrypted;
        } on ProMaxCryptoException {
          return message.copyWith(e2ee: CachedMessage.e2eeFailed);
        } on FormatException {
          return message.copyWith(e2ee: CachedMessage.e2eeFailed);
        } finally {
          if (plaintext != null) ProMaxCrypto.wipe(plaintext);
        }
      });

  void lock() {
    _generation++;
    for (final state in _states.values) {
      state?.wipe();
    }
    _states.clear();
    revision.value++;
  }

  void dispose() {
    final handler = _controlHandler;
    if (handler != null) {
      E2eeService.instance.unregisterControlHandler(controlKind, handler);
      _controlHandler = null;
    }
    lock();
    revision.dispose();
  }
}

class _GroupEnvironment implements GroupEncryptionEnvironment {
  @override
  bool get available => ProMaxGroupCrypto.isAvailable;

  Future<void> _active(int accountId) async {
    if (await TokenStorage.getActiveAccountId() != accountId) {
      throw const GroupEncryptionException(GroupEncryptionBlock.unavailable);
    }
  }

  @override
  Future<GroupEncryptionRoster> roster(int accountId, int groupId) async {
    await _active(accountId);
    final epoch = api.sessionEpoch;
    final info = await chats.getChatInfo(api, groupId);
    final count = info?['participantsCount'];
    if (info == null ||
        !const ['CHAT', 'GROUP'].contains(info['type']) ||
        count is! int ||
        count < 2 ||
        count > ProMaxCryptoSizes.groupMembersMax) {
      throw const GroupEncryptionException(GroupEncryptionBlock.membership);
    }
    final ids = <int>{};
    final markers = <int>{};
    var marker = 0;
    while (ids.length < count) {
      if (!markers.add(marker)) {
        throw const GroupEncryptionException(GroupEncryptionBlock.membership);
      }
      final page = await chats.getChatMembers(
        api,
        groupId,
        marker: marker,
        count: 50,
      );
      if (page == null || page.members.isEmpty) {
        throw const GroupEncryptionException(GroupEncryptionBlock.membership);
      }
      ids.addAll(page.members.map((member) => member.id));
      marker = page.marker;
      if (ids.length > count || markers.length > 6) {
        throw const GroupEncryptionException(GroupEncryptionBlock.membership);
      }
    }
    if (!ids.contains(accountId)) {
      throw const GroupEncryptionException(GroupEncryptionBlock.membership);
    }
    await E2eeService.instance.ensureLoaded(accountId);
    final cached = await AppDatabase.loadChats(accountId, includeHidden: true);
    final peers = <GroupEncryptionPeer>[];
    for (final id in ids.toList()..sort()) {
      if (id == accountId) {
        peers.add(
          GroupEncryptionPeer(
            id: id,
            publicKey: await E2eeService.instance.identityPublic(accountId),
            dialogId: 0,
          ),
        );
        continue;
      }
      GroupEncryptionPeer? peer;
      for (final row in cached.where((row) => row['type'] == 'DIALOG')) {
        final chatId = row['id'] as int;
        final session = E2eeService.instance.info(accountId, chatId);
        if (session?.peerId == id &&
            session?.phase == E2eePhase.established &&
            session?.verified == true &&
            session?.peerPublic != null) {
          peer = GroupEncryptionPeer(
            id: id,
            publicKey: session!.peerPublic!,
            dialogId: chatId,
          );
          break;
        }
      }
      if (peer == null) {
        throw const GroupEncryptionException(GroupEncryptionBlock.verification);
      }
      peers.add(peer);
    }
    await _active(accountId);
    if (api.sessionEpoch != epoch) {
      throw const GroupEncryptionException(GroupEncryptionBlock.unavailable);
    }
    final manifest = ProMaxGroupCrypto.membersBuild([
      for (final peer in peers)
        GroupMember(id: peer.id, publicKey: peer.publicKey),
    ]);
    return GroupEncryptionRoster(
      peers,
      manifest,
      base64Encode(ProMaxGroupCrypto.membersDigest(groupId, manifest)),
    );
  }

  @override
  Future<Uint8List> identity(int accountId) =>
      E2eeService.instance.identity(accountId);

  String _storageKey(int groupId) => 'group_e2ee_v1:$groupId';

  @override
  Future<String?> load(int accountId, int groupId) async {
    final encoded = await AppDatabase.getSyncValue(
      accountId,
      _storageKey(groupId),
    );
    if (encoded == null) return null;
    final plaintext = await E2eeService.instance.openGroupState(
      accountId,
      groupId,
      base64Decode(encoded),
    );
    try {
      return utf8.decode(plaintext);
    } finally {
      ProMaxCrypto.wipe(plaintext);
    }
  }

  @override
  Future<void> save(
    int accountId,
    int groupId,
    String state,
    CachedMessage? message,
  ) async {
    final plaintext = Uint8List.fromList(utf8.encode(state));
    try {
      final sealed = await E2eeService.instance.sealGroupState(
        accountId,
        groupId,
        plaintext,
      );
      await AppDatabase.saveGroupEncryptionState(
        accountId,
        _storageKey(groupId),
        base64Encode(sealed),
        message?.toDbRow(),
      );
    } finally {
      ProMaxCrypto.wipe(plaintext);
    }
  }

  @override
  Future<void> send(
    int accountId,
    GroupEncryptionPeer peer,
    Uint8List payload, {
    void Function()? beforeSend,
  }) async {
    await _active(accountId);
    final epoch = messagesModule.sessionEpoch;
    void check() {
      beforeSend?.call();
      final session = E2eeService.instance.info(accountId, peer.dialogId);
      if (messagesModule.sessionEpoch != epoch ||
          session?.verified != true ||
          session?.phase != E2eePhase.established ||
          session?.peerId != peer.id ||
          !listEquals(session?.peerPublic, peer.publicKey)) {
        throw const GroupEncryptionException(GroupEncryptionBlock.verification);
      }
    }

    check();
    final wire = await E2eeService.instance.encryptBytes(
      accountId,
      peer.dialogId,
      ContentType.control,
      payload,
    );
    if (wire == null) {
      throw const GroupEncryptionException(GroupEncryptionBlock.transport);
    }
    await _active(accountId);
    await messagesModule.sendMessage(
      accountId,
      peer.dialogId,
      wire,
      notify: false,
      beforeSend: check,
    );
  }

  @override
  Future<Uint8List> sealMessage(
    int accountId,
    int groupId,
    Uint8List plaintext,
  ) => E2eeService.instance.sealBytes(accountId, groupId, plaintext);
}
