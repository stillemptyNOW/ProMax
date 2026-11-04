import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promax/core/crypto/group_e2ee_service.dart';
import 'package:promax/frontend/screens/chats/group_encryption_screen.dart';
import 'package:promax/l10n/app_localizations.dart';

class SyntheticGroupService implements GroupE2eeService {
  @override
  final revision = ValueNotifier<int>(0);

  GroupEncryptionInfo state = const GroupEncryptionInfo();
  int starts = 0;
  int accepts = 0;

  @override
  bool get available => true;

  @override
  Future<void> ensureLoaded(int accountId, int groupId) async {}

  @override
  GroupEncryptionInfo info(int accountId, int groupId) => state;

  @override
  Future<void> begin(int accountId, int groupId) async {
    starts++;
    state = const GroupEncryptionInfo(
      required: true,
      epoch: 1,
      memberCount: 2,
      consentCount: 1,
      consented: true,
    );
    revision.value++;
  }

  @override
  Future<void> accept(int accountId, int groupId) async {
    accepts++;
    state = const GroupEncryptionInfo(
      required: true,
      epoch: 1,
      memberCount: 2,
      consentCount: 1,
      consented: true,
    );
    revision.value++;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  Widget host(SyntheticGroupService service) => MaterialApp(
    locale: const Locale('en'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: GroupEncryptionScreen(accountId: 1, groupId: 10, service: service),
  );

  testWidgets('starting requires confirmation and shows waiting state', (
    tester,
  ) async {
    final service = SyntheticGroupService();
    addTearDown(service.revision.dispose);
    await tester.pumpWidget(host(service));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Enable group encryption'));
    await tester.pumpAndSettle();
    expect(service.starts, 0);
    await tester.tap(find.text('I agree'));
    await tester.pumpAndSettle();
    expect(service.starts, 1);
    expect(find.textContaining('Waiting for participants'), findsOneWidget);
    expect(find.text('1/2'), findsOneWidget);
  });

  testWidgets('changed membership stays blocked without plaintext action', (
    tester,
  ) async {
    final service = SyntheticGroupService()
      ..state = const GroupEncryptionInfo(
        required: true,
        epoch: 1,
        memberCount: 2,
        block: GroupEncryptionBlock.changed,
      );
    addTearDown(service.revision.dispose);
    await tester.pumpWidget(host(service));
    await tester.pumpAndSettle();
    expect(find.textContaining('group members changed'), findsOneWidget);
    expect(find.textContaining('Send unencrypted'), findsNothing);
    expect(service.starts, 0);
  });

  testWidgets('early control messages do not create a consent button', (
    tester,
  ) async {
    final service = SyntheticGroupService()
      ..state = const GroupEncryptionInfo(epoch: 1, memberCount: 2);
    addTearDown(service.revision.dispose);
    await tester.pumpWidget(host(service));
    await tester.pumpAndSettle();
    expect(find.text('Accept group encryption'), findsNothing);
    expect(service.accepts, 0);
  });
}
