import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promax/core/hub/hub_client.dart';
import 'package:promax/core/hub/hub_inbox.dart';
import 'package:promax/core/storage/token_storage.dart';
import 'package:promax/frontend/screens/promax_hub/service_chat_screen.dart';
import 'package:promax/frontend/widgets/confirm_dialog.dart';
import 'package:promax/l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _AdminClient extends HubClient {
  HubDraft serverDraft = const HubDraft(
    text: 'Synthetic original',
    revision: 1,
    publishedRevision: 0,
  );
  Completer<HubDraft>? pendingDraft;
  bool failDraft = false;
  int activations = 0;
  int saves = 0;
  final published = <int>[];

  @override
  Future<List<HubMessage>> messages({int after = 0}) async => [];

  @override
  Future<String> activate(String code, int accountId) async {
    activations++;
    return 'synthetic-new-token';
  }

  @override
  Future<HubDraft> draft(String token) async {
    if (failDraft) throw const HubException(503);
    final pending = pendingDraft;
    pendingDraft = null;
    return pending == null ? serverDraft : pending.future;
  }

  @override
  Future<HubDraft> saveDraft(String token, String text, int revision) async {
    saves++;
    if (serverDraft.revision != revision) throw const HubException(409);
    return serverDraft = HubDraft(
      text: text.trim(),
      revision: revision + 1,
      publishedRevision: serverDraft.publishedRevision,
    );
  }

  @override
  Future<void> publish(String token, int revision) async {
    published.add(revision);
    if (serverDraft.revision != revision) throw const HubException(409);
    serverDraft = HubDraft(
      text: serverDraft.text,
      revision: revision,
      publishedRevision: revision,
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _AdminClient client;
  late HubInbox inbox;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({
      'promax_hub_admin_101': 'synthetic-token',
    });
    await TokenStorage.setActiveAccount(101);
    client = _AdminClient();
    inbox = HubInbox(
      accountId: 101,
      phone: 70000000000,
      adminIdentity: const HubAdminIdentity(accountId: 101, phone: 70000000000),
      client: client,
    );
    await inbox.init();
    await inbox.refreshDraft();
  });

  tearDown(() => inbox.dispose());

  Widget host(ServiceChat kind) => MaterialApp(
    locale: const Locale('en'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: ServiceChatScreen(inbox: inbox, kind: kind),
  );

  test(
    'a save conflict loads the current revision for an explicit retry',
    () async {
      client.serverDraft = const HubDraft(
        text: 'Synthetic remote edit',
        revision: 2,
        publishedRevision: 0,
      );
      await expectLater(
        inbox.saveDraft('Synthetic local edit'),
        throwsA(isA<HubException>()),
      );
      expect(inbox.draft?.revision, 2);
      await inbox.saveDraft('Synthetic local edit');
      expect(inbox.draft?.text, 'Synthetic local edit');
      expect(inbox.draft?.revision, 3);
    },
  );

  test('an unchanged saved draft keeps its published revision', () async {
    client.serverDraft = const HubDraft(
      text: 'Synthetic original',
      revision: 1,
      publishedRevision: 1,
    );
    await inbox.refreshDraft();
    await inbox.saveDraft('  Synthetic original  ');
    expect(client.saves, 0);
    expect(inbox.draft?.publishedRevision, 1);
    expect(inbox.draft?.revision, 1);
  });

  test(
    'a successful publish remains successful if draft refresh fails',
    () async {
      client.failDraft = true;
      await inbox.publish();
      expect(client.published, [1]);
      expect(inbox.draft?.publishedRevision, 1);
    },
  );

  test('a late draft refresh cannot replace a newer saved revision', () async {
    final pending = Completer<HubDraft>();
    client.pendingDraft = pending;
    final refresh = inbox.refreshDraft();
    await Future<void>.delayed(Duration.zero);
    await inbox.saveDraft('Synthetic saved edit');
    pending.complete(
      const HubDraft(text: 'Synthetic old', revision: 1, publishedRevision: 0),
    );
    await refresh;
    expect(inbox.draft?.revision, 2);
    expect(inbox.draft?.text, 'Synthetic saved edit');
  });

  test(
    'switching accounts blocks activation before consuming a code',
    () async {
      await TokenStorage.setActiveAccount(202);
      await expectLater(
        inbox.activate('synthetic-code'),
        throwsA(isA<HubException>()),
      );
      expect(client.activations, 0);
      expect(
        await TokenStorage.readSecure('promax_hub_admin_101'),
        'synthetic-token',
      );
    },
  );

  test(
    'a completed request for an old account cannot update its draft',
    () async {
      final pending = Completer<HubDraft>();
      client.pendingDraft = pending;
      final refresh = inbox.refreshDraft();
      await Future<void>.delayed(Duration.zero);
      await TokenStorage.setActiveAccount(202);
      final result = expectLater(refresh, throwsA(isA<HubException>()));
      pending.complete(
        const HubDraft(
          text: 'Synthetic stale account',
          revision: 2,
          publishedRevision: 0,
        ),
      );
      await result;
      expect(inbox.draft?.text, 'Synthetic original');
      expect(
        await TokenStorage.readSecure('promax_hub_admin_101'),
        'synthetic-token',
      );
    },
  );

  testWidgets('refresh preserves unsaved editor text', (tester) async {
    await tester.pumpWidget(host(ServiceChat.admin));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Synthetic unsaved edit');
    await tester.tap(find.byTooltip('Refresh'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller?.text,
      'Synthetic unsaved edit',
    );
  });

  testWidgets('reopening the editor preserves unsaved text in this account', (
    tester,
  ) async {
    await tester.pumpWidget(host(ServiceChat.admin));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Synthetic unsaved edit');
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(host(ServiceChat.admin));
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller?.text,
      'Synthetic unsaved edit',
    );
  });

  testWidgets('the editor disables preview for whitespace-only text', (
    tester,
  ) async {
    await tester.pumpWidget(host(ServiceChat.admin));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '   ');
    await tester.pump();
    expect(
      tester
          .widget<IconButton>(
            find.byWidgetPredicate(
              (widget) =>
                  widget is IconButton && widget.tooltip == 'Send to preview',
            ),
          )
          .onPressed,
      isNull,
    );
  });

  testWidgets('confirmation cannot publish a revision changed after preview', (
    tester,
  ) async {
    await tester.pumpWidget(host(ServiceChat.preview));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Publish to everyone'));
    await tester.pumpAndSettle();
    client.serverDraft = const HubDraft(
      text: 'Synthetic unreviewed',
      revision: 2,
      publishedRevision: 0,
    );
    await inbox.refreshDraft();
    await tester.pump();
    await tester.tap(
      find
          .descendant(
            of: find.byType(ChromeAlertDialog),
            matching: find.text('Publish to everyone'),
          )
          .last,
    );
    await tester.pumpAndSettle();
    expect(client.published, isEmpty);
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
  });
}
