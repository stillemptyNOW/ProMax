import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promax/backend/api.dart';
import 'package:promax/backend/modules/messages.dart' show ContactCache;
import 'package:promax/core/protocol/opcode_map.dart';
import 'package:promax/core/protocol/packet.dart';
import 'package:promax/core/storage/token_storage.dart';
import 'package:promax/frontend/screens/contacts/find_user_sheet.dart';
import 'package:promax/l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _LookupApi extends Api {
  final requests = <(int, Map<dynamic, dynamic>, bool)>[];
  Completer<Packet>? pending;

  @override
  Future<Packet> sendRequest(
    int opcode,
    Map<dynamic, dynamic> payload, {
    bool silent = false,
    void Function()? beforeSend,
  }) async {
    beforeSend?.call();
    requests.add((opcode, payload, silent));
    return pending?.future ?? Packet(cmd: CmdType.ok, payload: {});
  }
}

Future<void> _openSheet(
  WidgetTester tester, {
  Api? client,
  ValueChanged<FoundUser?>? onResult,
}) async {
  addTearDown(ContactCache.clear);
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              final result = client == null
                  ? await showFindUserSheet(
                      context,
                      title: 'Find contact',
                      actionLabel: 'Find',
                    )
                  : await showModalBottomSheet<FoundUser>(
                      context: context,
                      isScrollControlled: true,
                      builder: (_) => FindUserSheet(
                        client: client,
                        title: 'Find contact',
                        actionLabel: 'Find',
                      ),
                    );
              onResult?.call(result);
            },
            child: const Text('Open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
}

String _input(WidgetTester tester) =>
    tester.widget<TextField>(find.byType(TextField)).controller!.text;

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets(
    'does not duplicate the prefix while entering an international number',
    (tester) async {
      await _openSheet(tester);
      await tester.enterText(find.byType(TextField), '+7');
      await tester.pump();
      expect(
        tester.widget<TextField>(find.byType(TextField)).decoration!.prefixText,
        isNull,
      );
    },
  );

  testWidgets('phone and ID keep separate input when switching modes', (
    tester,
  ) async {
    await _openSheet(tester);
    await tester.tap(find.text('ID'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '12345');
    await tester.tap(find.text('Phone'));
    await tester.pumpAndSettle();
    expect(_input(tester), isEmpty);
    await tester.enterText(find.byType(TextField), '0000000000');
    await tester.tap(find.text('ID'));
    await tester.pumpAndSettle();
    expect(_input(tester), '12345');
  });

  testWidgets('the form remains scrollable above a small screen keyboard', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 480);
    tester.view.viewInsets = const FakeViewPadding(bottom: 260);
    addTearDown(tester.view.reset);
    await _openSheet(tester);
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.widgetWithText(FilledButton, 'Find'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(
      find.widgetWithText(FilledButton, 'Find').hitTestable(),
      findsOneWidget,
    );
  });

  testWidgets('an incomplete phone is rejected without a lookup', (
    tester,
  ) async {
    final client = _LookupApi();
    addTearDown(client.dispose);
    await _openSheet(tester, client: client);
    await tester.enterText(find.byType(TextField), '00000');
    await tester.tap(find.widgetWithText(FilledButton, 'Find'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(client.requests, isEmpty);
    expect(find.text('Enter a valid phone number'), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Semantics &&
            widget.properties.liveRegion == true &&
            widget.properties.label == 'Enter a valid phone number',
      ),
      findsOneWidget,
    );
  });

  testWidgets(
    'pasted international phones send one correctly normalized lookup',
    (tester) async {
      final client = _LookupApi();
      addTearDown(client.dispose);
      await _openSheet(tester, client: client);
      await tester.enterText(find.byType(TextField), '+1 (000) 000-0000');
      await tester.pump();
      expect(_input(tester), '(000) 000-0000');
      expect(
        tester.widget<TextField>(find.byType(TextField)).decoration!.prefixText,
        '+1  ',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Find'));
      await tester.pumpAndSettle();
      expect(client.requests, hasLength(1));
      expect(client.requests.single.$1, Opcode.contactInfoByPhone);
      expect(client.requests.single.$2, {'phone': '+10000000000'});
      expect(client.requests.single.$3, isTrue);
      expect(
        find.text('No contact with this number was found'),
        findsOneWidget,
      );
    },
  );

  testWidgets('keyboard submission cannot start duplicate in-flight lookups', (
    tester,
  ) async {
    final client = _LookupApi()..pending = Completer<Packet>();
    addTearDown(client.dispose);
    await _openSheet(tester, client: client);
    await tester.enterText(find.byType(TextField), '0000000000');
    final submit = tester
        .widget<TextField>(find.byType(TextField))
        .onSubmitted!;
    submit('');
    submit('');
    await tester.pump();
    expect(client.requests, hasLength(1));
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );
    await tester.tap(find.text('ID'));
    submit('');
    await tester.pump();
    expect(client.requests, hasLength(1));
    client.pending!.complete(Packet(cmd: CmdType.ok, payload: {}));
    await tester.pumpAndSettle();
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNotNull,
    );
  });

  testWidgets(
    'a result arriving after dismissal cannot pop the parent screen',
    (tester) async {
      final client = _LookupApi()..pending = Completer<Packet>();
      final results = <FoundUser?>[];
      addTearDown(client.dispose);
      await _openSheet(tester, client: client, onResult: results.add);
      await tester.enterText(find.byType(TextField), '0000000000');
      await tester.tap(find.widgetWithText(FilledButton, 'Find'));
      await tester.pump();
      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();
      client.pending!.complete(
        Packet(
          cmd: CmdType.ok,
          payload: {
            'contact': {'id': 12345},
          },
        ),
      );
      await tester.pumpAndSettle();
      expect(results, [null]);
      expect(find.text('Open'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'ID validation requires a positive integer and preserves FoundUser',
    (tester) async {
      final client = _LookupApi()..pending = Completer<Packet>();
      FoundUser? result;
      addTearDown(client.dispose);
      await _openSheet(
        tester,
        client: client,
        onResult: (value) => result = value,
      );
      await tester.tap(find.text('ID'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '-12345');
      await tester.tap(find.widgetWithText(FilledButton, 'Find'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(client.requests, isEmpty);
      expect(find.text('Enter a numeric ID'), findsOneWidget);
      await tester.enterText(find.byType(TextField), '12345');
      await tester.tap(find.widgetWithText(FilledButton, 'Find'));
      await tester.pump();
      expect(client.requests, hasLength(1));
      expect(client.requests.single.$1, Opcode.contactInfo);
      expect(client.requests.single.$2, {
        'contactIds': [12345],
      });
      expect(client.requests.single.$3, isTrue);
      client.pending!.complete(
        Packet(
          cmd: CmdType.ok,
          payload: {
            'contacts': [
              {
                'id': 12345,
                'names': [
                  {'type': 'ONEME', 'name': 'Synthetic Contact'},
                ],
              },
            ],
          },
        ),
      );
      await tester.pumpAndSettle();
      expect(result?.userId, 12345);
      expect(result?.chatId, 12345);
      expect(result?.name, 'Synthetic Contact');
      expect(result?.avatarUrl, '');
      ContactCache.clear();
    },
  );

  testWidgets('lookup failures return the form to an editable retry state', (
    tester,
  ) async {
    final client = _LookupApi()..pending = Completer<Packet>();
    addTearDown(client.dispose);
    await _openSheet(tester, client: client);
    await tester.enterText(find.byType(TextField), '0000000000');
    await tester.tap(find.widgetWithText(FilledButton, 'Find'));
    await tester.pump();
    client.pending!.completeError(TimeoutException('Synthetic timeout'));
    await tester.pumpAndSettle();
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.enabled, isTrue);
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNotNull,
    );
    expect(client.requests, hasLength(1));
    client.pending = null;
    await tester.tap(find.widgetWithText(FilledButton, 'Find'));
    await tester.pumpAndSettle();
    expect(client.requests, hasLength(2));
    expect(find.text('No contact with this number was found'), findsOneWidget);
  });

  for (final byPhone in [true, false]) {
    testWidgets(
      'an account switch discards a pending ${byPhone ? 'phone' : 'ID'} result before caching',
      (tester) async {
        final client = _LookupApi()..pending = Completer<Packet>();
        final results = <FoundUser?>[];
        final userId = byPhone ? 12346 : 12347;
        addTearDown(client.dispose);
        await _openSheet(tester, client: client, onResult: results.add);
        if (!byPhone) {
          await tester.tap(find.text('ID'));
          await tester.pumpAndSettle();
        }
        await tester.enterText(
          find.byType(TextField),
          byPhone ? '0000000000' : '$userId',
        );
        await tester.tap(find.widgetWithText(FilledButton, 'Find'));
        await tester.pump();
        expect(client.requests, hasLength(1));
        await TokenStorage.setActiveAccount(202);
        final contact = {
          'id': userId,
          'names': [
            {'type': 'ONEME', 'name': 'Stale Synthetic Contact'},
          ],
        };
        client.pending!.complete(
          Packet(
            cmd: CmdType.ok,
            payload: byPhone
                ? {'contact': contact}
                : {
                    'contacts': [contact],
                  },
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));
        expect(ContactCache.get(userId), isNull);
        expect(results, isEmpty);
        expect(find.byType(FindUserSheet), findsOneWidget);
      },
    );
  }
}
