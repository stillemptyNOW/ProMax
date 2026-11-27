import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:promax/backend/modules/messages.dart';
import 'package:promax/core/crypto/group_e2ee_service.dart';
import 'package:promax_crypto/promax_crypto.dart';

class SyntheticGroupNative implements GroupEncryptionNative {
  bool imported = false;

  @override
  Uint8List import(
    int groupId,
    int senderId,
    Uint8List manifest,
    Uint8List distribution,
    Uint8List? oldState,
  ) {
    imported = true;
    return Uint8List.fromList([1]);
  }

  @override
  GroupSenderKey create(
    Uint8List identity,
    int groupId,
    int senderId,
    int epoch,
    Uint8List manifest,
    Uint8List? oldState,
  ) {
    final distribution = Uint8List(ProMaxCryptoSizes.groupDistribution);
    ByteData.sublistView(distribution).setUint64(12, epoch, Endian.big);
    return GroupSenderKey(
      distribution: distribution,
      state: Uint8List.fromList([1]),
    );
  }

  @override
  GroupEncrypted encrypt(
    Uint8List state,
    ContentType type,
    Uint8List plaintext,
  ) => GroupEncrypted(
    state: Uint8List.fromList([2]),
    envelope: Uint8List.fromList([3]),
  );

  @override
  SessionDecrypted decrypt(Uint8List state, Uint8List envelope) =>
      throw UnimplementedError();
}

class SyntheticGroupEnvironment implements GroupEncryptionEnvironment {
  SyntheticGroupEnvironment({this.members = const [1, 2]});

  final List<int> members;
  String digest = base64Encode(Uint8List(32));
  String? stored;
  bool failKeyDelivery = false;
  bool Function(Map<String, dynamic>)? failSave;
  String? failControlDelivery;
  GroupEncryptionBlock? rosterBlock;
  void Function()? onKeyDelivery;
  void Function()? onRoster;
  final List<({int sender, int recipient, Uint8List payload})> outgoing = [];

  @override
  bool get available => true;

  @override
  Future<GroupEncryptionRoster> roster(int accountId, int groupId) async {
    onRoster?.call();
    if (rosterBlock case final block?) throw GroupEncryptionException(block);
    return GroupEncryptionRoster(
      [
        for (final id in members)
          GroupEncryptionPeer(
            id: id,
            publicKey: Uint8List(32),
            dialogId: id * 10,
          ),
      ],
      Uint8List(members.length * 40),
      digest,
    );
  }

  @override
  Future<Uint8List> identity(int accountId) async => Uint8List(64);

  @override
  Future<String?> load(int accountId, int groupId) async => stored;

  @override
  Future<void> save(
    int accountId,
    int groupId,
    String state,
    CachedMessage? message,
  ) async {
    if (failSave?.call(jsonDecode(state) as Map<String, dynamic>) ?? false) {
      throw StateError('synthetic save failure');
    }
    stored = state;
  }

  @override
  Future<void> send(
    int accountId,
    GroupEncryptionPeer peer,
    Uint8List payload, {
    void Function()? beforeSend,
  }) async {
    final type = jsonDecode(utf8.decode(payload))['t'];
    final isKey = type == 'key';
    if (isKey) onKeyDelivery?.call();
    beforeSend?.call();
    if ((failKeyDelivery && isKey) || type == failControlDelivery) {
      throw StateError('synthetic delivery failure');
    }
    outgoing.add((
      sender: accountId,
      recipient: peer.id,
      payload: Uint8List.fromList(payload),
    ));
  }

  @override
  Future<Uint8List> sealMessage(
    int accountId,
    int groupId,
    Uint8List plaintext,
  ) async => Uint8List.fromList(plaintext);
}

void main() {
  test('membership persistence does not replace an in-flight rekey', () async {
    final environment = SyntheticGroupEnvironment();
    final service = GroupE2eeService(
      environment: environment,
      native: SyntheticGroupNative(),
    );
    addTearDown(service.dispose);
    await service.begin(1, -10);
    environment.digest = base64Encode(Uint8List.fromList(List.filled(32, 1)));
    environment.onRoster = () {
      environment.onRoster = null;
      service.membershipChanged(1, -10);
    };

    await service.begin(1, -10);
    await service.ensureLoaded(1, -10);

    expect(service.info(1, -10).epoch, 2);
    expect(service.info(1, -10).block, isNull);
    expect(jsonDecode(environment.stored!)['e'], 2);
  });

  test('can retry after a failed sender-key completion save', () async {
    final environment = SyntheticGroupEnvironment();
    final service = GroupE2eeService(
      environment: environment,
      native: SyntheticGroupNative(),
    );
    addTearDown(service.dispose);
    await service.begin(1, -10);
    environment.failSave = (state) =>
        state['sender'] != null && state['pendingDistribution'] == null;
    final consent = Uint8List.fromList(
      utf8.encode(
        jsonEncode({
          'p': GroupE2eeService.controlKind,
          't': 'consent',
          'g': -10,
          'e': 1,
          'd': environment.digest,
        }),
      ),
    );
    await expectLater(
      service.handleControl(1, 2, 'synthetic-consent', consent),
      throwsStateError,
    );

    expect(service.info(1, -10).canRetry, isTrue);
    environment.failSave = null;
    await service.retry(1, -10);
    expect(service.info(1, -10).block, isNull);
    expect(service.info(1, -10).canRetry, isFalse);
    expect(
      environment.outgoing.where(
        (message) => jsonDecode(utf8.decode(message.payload))['t'] == 'key',
      ),
      hasLength(1),
    );
  });

  test('carries initiation consent into the coordinator rekey epoch', () async {
    final coordinatorEnvironment = SyntheticGroupEnvironment();
    final joiningEnvironment = SyntheticGroupEnvironment();
    final coordinator = GroupE2eeService(
      environment: coordinatorEnvironment,
      native: SyntheticGroupNative(),
    );
    final joining = GroupE2eeService(
      environment: joiningEnvironment,
      native: SyntheticGroupNative(),
    );
    addTearDown(coordinator.dispose);
    addTearDown(joining.dispose);
    await coordinator.begin(1, -10);
    coordinatorEnvironment.outgoing.clear();
    final newDigest = base64Encode(Uint8List.fromList(List.filled(32, 1)));
    coordinatorEnvironment.digest = joiningEnvironment.digest = newDigest;
    coordinator.membershipChanged(1, -10);

    await joining.begin(2, -10);
    await coordinator.handleControl(
      1,
      2,
      'synthetic-invite',
      joiningEnvironment.outgoing.single.payload,
    );
    expect(
      () => coordinator.assertPrepared(1, -10, 'synthetic plaintext'),
      throwsA(isA<GroupEncryptionException>()),
    );
    await coordinator.accept(1, -10);
    final proposal = coordinatorEnvironment.outgoing.first.payload;
    await joining.handleControl(2, 1, 'synthetic-proposal', proposal);

    expect(joining.info(2, -10).epoch, 2);
    expect(joining.info(2, -10).consented, isTrue);
  });

  test(
    'does not send a key if membership changes at the send boundary',
    () async {
      final firstEnvironment = SyntheticGroupEnvironment();
      final secondEnvironment = SyntheticGroupEnvironment();
      final first = GroupE2eeService(
        environment: firstEnvironment,
        native: SyntheticGroupNative(),
      );
      final second = GroupE2eeService(
        environment: secondEnvironment,
        native: SyntheticGroupNative(),
      );
      addTearDown(first.dispose);
      addTearDown(second.dispose);
      await first.begin(1, -10);
      var serial = 0;
      while (firstEnvironment.outgoing.isNotEmpty) {
        final message = firstEnvironment.outgoing.removeAt(0);
        await second.handleControl(2, 1, 'first-${serial++}', message.payload);
      }
      await second.accept(2, -10);
      firstEnvironment.onKeyDelivery = () => first.membershipChanged(1, -10);
      final consent = secondEnvironment.outgoing.removeAt(0);
      await expectLater(
        first.handleControl(1, 2, 'consent', consent.payload),
        throwsA(isA<GroupEncryptionException>()),
      );
      expect(firstEnvironment.outgoing, isEmpty);
      expect(first.info(1, -10).block, GroupEncryptionBlock.changed);
    },
  );

  for (final type in ['proposal', 'consent', 'invite']) {
    test('retries $type after delivery failure and restart', () async {
      final environment = SyntheticGroupEnvironment();
      environment.failControlDelivery = type;
      var service = GroupE2eeService(
        environment: environment,
        native: SyntheticGroupNative(),
      );
      addTearDown(() => service.dispose());
      final account = type == 'invite' ? 2 : 1;
      await expectLater(service.begin(account, -10), throwsStateError);
      expect(service.info(account, -10).ready, isFalse);
      service.dispose();
      service = GroupE2eeService(
        environment: environment,
        native: SyntheticGroupNative(),
      );
      environment.failControlDelivery = null;
      await service.ensureLoaded(account, -10);
      expect(service.info(account, -10).canRetry, isTrue);
      if (type == 'invite') {
        expect(service.info(account, -10).consented, isFalse);
      }
      await service.retry(account, -10);
      expect(
        environment.outgoing.any(
          (message) => jsonDecode(utf8.decode(message.payload))['t'] == type,
        ),
        isTrue,
      );
      if (type == 'invite') {
        expect(service.info(account, -10).consented, isFalse);
      }
    });
  }

  test('refuses to retry control messages after membership changes', () async {
    final environment = SyntheticGroupEnvironment();
    environment.failControlDelivery = 'proposal';
    final service = GroupE2eeService(
      environment: environment,
      native: SyntheticGroupNative(),
    );
    addTearDown(service.dispose);
    await expectLater(service.begin(1, -10), throwsStateError);
    environment.failControlDelivery = null;
    environment.digest = base64Encode(Uint8List.fromList(List.filled(32, 1)));
    await expectLater(
      service.retry(1, -10),
      throwsA(isA<GroupEncryptionException>()),
    );
    expect(environment.outgoing, isEmpty);
    expect(service.info(1, -10).ready, isFalse);
    expect(service.info(1, -10).block, GroupEncryptionBlock.changed);
  });

  test('retains verified consent received before the group proposal', () async {
    final environment = SyntheticGroupEnvironment();
    final service = GroupE2eeService(
      environment: environment,
      native: SyntheticGroupNative(),
    );
    addTearDown(service.dispose);
    Uint8List control(String type) => Uint8List.fromList(
      utf8.encode(
        jsonEncode({
          'p': GroupE2eeService.controlKind,
          't': type,
          'g': -10,
          'e': 1,
          'd': environment.digest,
        }),
      ),
    );

    await service.handleControl(2, 1, 'early-consent', control('consent'));
    await expectLater(
      service.accept(2, -10),
      throwsA(isA<GroupEncryptionException>()),
    );
    await service.handleControl(2, 1, 'proposal', control('proposal'));
    await service.accept(2, -10);
    expect(service.info(2, -10).consentCount, 2);
  });

  for (final interrupted in [false, true]) {
    test(
      'retries unsent group keys after restart (interrupted: $interrupted)',
      () async {
        final firstEnvironment = SyntheticGroupEnvironment();
        final secondEnvironment = SyntheticGroupEnvironment();
        var first = GroupE2eeService(
          environment: firstEnvironment,
          native: SyntheticGroupNative(),
        );
        final second = GroupE2eeService(
          environment: secondEnvironment,
          native: SyntheticGroupNative(),
        );
        addTearDown(() => first.dispose());
        addTearDown(second.dispose);
        var serial = 0;
        Future<void> deliver() async {
          while (firstEnvironment.outgoing.isNotEmpty ||
              secondEnvironment.outgoing.isNotEmpty) {
            final source = firstEnvironment.outgoing.isNotEmpty
                ? firstEnvironment.outgoing
                : secondEnvironment.outgoing;
            final message = source.removeAt(0);
            await (message.recipient == 1 ? first : second).handleControl(
              message.recipient,
              message.sender,
              'message-${serial++}',
              message.payload,
            );
          }
        }

        await first.begin(1, -10);
        await deliver();
        await second.accept(2, -10);
        firstEnvironment.failKeyDelivery = true;
        await expectLater(deliver(), throwsStateError);
        first.dispose();
        if (interrupted) {
          final persisted =
              jsonDecode(firstEnvironment.stored!) as Map<String, dynamic>;
          persisted['block'] = null;
          firstEnvironment.stored = jsonEncode(persisted);
        }
        first = GroupE2eeService(
          environment: firstEnvironment,
          native: SyntheticGroupNative(),
        );
        firstEnvironment.failKeyDelivery = false;
        await first.retry(1, -10);
        await deliver();
        expect(first.info(1, -10).ready, isTrue);
        expect(second.info(2, -10).ready, isTrue);
      },
    );
  }

  test(
    'a non-coordinator can initiate with one consent per participant',
    () async {
      final firstEnvironment = SyntheticGroupEnvironment();
      final secondEnvironment = SyntheticGroupEnvironment();
      final first = GroupE2eeService(
        environment: firstEnvironment,
        native: SyntheticGroupNative(),
      );
      final second = GroupE2eeService(
        environment: secondEnvironment,
        native: SyntheticGroupNative(),
      );
      addTearDown(first.dispose);
      addTearDown(second.dispose);
      var serial = 0;
      Future<void> deliver() async {
        while (firstEnvironment.outgoing.isNotEmpty ||
            secondEnvironment.outgoing.isNotEmpty) {
          final source = firstEnvironment.outgoing.isNotEmpty
              ? firstEnvironment.outgoing
              : secondEnvironment.outgoing;
          final message = source.removeAt(0);
          await (message.recipient == 1 ? first : second).handleControl(
            message.recipient,
            message.sender,
            'message-${serial++}',
            message.payload,
          );
        }
      }

      await second.begin(2, -10);
      await deliver();
      await first.accept(1, -10);
      await deliver();
      expect(first.info(1, -10).ready, isTrue);
      expect(second.info(2, -10).ready, isTrue);
    },
  );

  test('two members require consent and exchange sender keys', () async {
    final firstEnvironment = SyntheticGroupEnvironment();
    final secondEnvironment = SyntheticGroupEnvironment();
    final first = GroupE2eeService(
      environment: firstEnvironment,
      native: SyntheticGroupNative(),
    );
    final second = GroupE2eeService(
      environment: secondEnvironment,
      native: SyntheticGroupNative(),
    );
    addTearDown(first.dispose);
    addTearDown(second.dispose);
    var nextMessageId = 0;
    Future<void> deliver() async {
      while (firstEnvironment.outgoing.isNotEmpty ||
          secondEnvironment.outgoing.isNotEmpty) {
        final source = firstEnvironment.outgoing.isNotEmpty
            ? firstEnvironment.outgoing
            : secondEnvironment.outgoing;
        final message = source.removeAt(0);
        final target = message.recipient == 1 ? first : second;
        await target.handleControl(
          message.recipient,
          message.sender,
          'synthetic-${nextMessageId++}',
          message.payload,
        );
      }
    }

    await first.begin(1, -10);
    await deliver();
    expect(first.info(1, -10).ready, isFalse);
    expect(second.info(2, -10).consented, isFalse);
    await second.accept(2, -10);
    await deliver();
    expect(first.info(1, -10).ready, isTrue);
    expect(second.info(2, -10).ready, isTrue);
    final queuedWire = await first.encryptText(1, -10, 'synthetic queued text');
    final queued = CachedMessage(
      id: 'synthetic-queued',
      accountId: 1,
      chatId: -10,
      senderId: 1,
      text: queuedWire,
      time: 0,
    );
    await first.assertSendAllowed(1, -10, queuedWire);
    firstEnvironment.rosterBlock = GroupEncryptionBlock.verification;
    await expectLater(
      first.assertSendAllowed(1, -10, queuedWire),
      throwsA(
        isA<GroupEncryptionException>().having(
          (error) => error.reason,
          'reason',
          GroupEncryptionBlock.verification,
        ),
      ),
    );
    expect(first.info(1, -10).canRetry, isTrue);
    firstEnvironment.rosterBlock = null;
    await first.retry(1, -10);
    await first.assertSendAllowed(1, -10, queuedWire);
    firstEnvironment.digest = base64Encode(
      Uint8List.fromList(List.filled(32, 1)),
    );
    await expectLater(
      first.assertSendAllowed(1, -10, queuedWire),
      throwsA(
        isA<GroupEncryptionException>()
            .having(
              (error) => error.reason,
              'reason',
              GroupEncryptionBlock.changed,
            )
            .having(
              (error) => queued.withSendFailure(error).status,
              'status',
              'pending',
            ),
      ),
    );
    await expectLater(
      first.encryptText(1, -10, 'synthetic text'),
      throwsA(
        isA<GroupEncryptionException>().having(
          (error) => error.reason,
          'reason',
          GroupEncryptionBlock.changed,
        ),
      ),
    );
    expect(first.info(1, -10).ready, isFalse);
    await first.begin(1, -10);
    await expectLater(
      first.assertSendAllowed(1, -10, queuedWire),
      throwsA(
        isA<ObsoleteGroupCiphertextException>().having(
          (error) => queued.withSendFailure(error).status,
          'status',
          'error',
        ),
      ),
    );
  });

  test('blocks unencrypted attachments in a protected group', () async {
    final environment = SyntheticGroupEnvironment();
    final service = GroupE2eeService(environment: environment);
    addTearDown(service.dispose);
    await service.begin(1, -10);

    expect(
      () => service.assertPrepared(
        1,
        -10,
        'PMXG1:synthetic',
        hasAttachments: true,
      ),
      throwsA(
        isA<GroupEncryptionException>().having(
          (error) => error.reason,
          'reason',
          GroupEncryptionBlock.transport,
        ),
      ),
    );
  });

  test('rejects a key distribution for a different group epoch', () async {
    final environment = SyntheticGroupEnvironment();
    final native = SyntheticGroupNative();
    final service = GroupE2eeService(environment: environment, native: native);
    addTearDown(service.dispose);
    await service.begin(1, -10);
    final before = environment.stored;
    final distribution = Uint8List(ProMaxCryptoSizes.groupDistribution);
    ByteData.sublistView(distribution).setUint64(12, 2, Endian.big);
    final payload = Uint8List.fromList(
      utf8.encode(
        jsonEncode({
          'p': GroupE2eeService.controlKind,
          't': 'key',
          'g': -10,
          'e': 1,
          'd': environment.digest,
          'k': base64Encode(distribution),
        }),
      ),
    );

    await service.handleControl(1, 2, 'synthetic-key', payload);

    expect(native.imported, isFalse);
    expect(environment.stored, before);
  });

  test(
    'ignores malformed key distribution without changing group state',
    () async {
      final environment = SyntheticGroupEnvironment();
      final service = GroupE2eeService(environment: environment);
      addTearDown(service.dispose);
      await service.begin(1, -10);
      final before = environment.stored;
      final payload = Uint8List.fromList(
        utf8.encode(
          jsonEncode({
            'p': GroupE2eeService.controlKind,
            't': 'key',
            'g': -10,
            'e': 1,
            'd': environment.digest,
            'k': '${'A' * 251}!',
          }),
        ),
      );

      await service.handleControl(1, 2, 'synthetic-message', payload);

      expect(environment.stored, before);
      expect(service.info(1, -10).ready, isFalse);
    },
  );
}
