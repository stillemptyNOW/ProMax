import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:m3e_collection/m3e_collection.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:promax/backend/modules/messages.dart';
import 'package:promax/core/config/app_performance.dart';
import 'package:promax/core/config/promax_glass.dart';
import 'package:promax/core/config/promax_settings.dart';
import 'package:promax/core/security/app_lock.dart';
import 'package:promax/core/storage/quick_replies_store.dart';
import 'package:promax/core/translation/message_translator.dart';
import 'package:promax/frontend/screens/profile/app_icon_screen.dart';
import 'package:promax/frontend/screens/profile/promax_design_screen.dart';
import 'package:promax/frontend/screens/profile/promax_settings_screen.dart';
import 'package:promax/frontend/screens/profile/promax_transfer_card.dart';
import 'package:promax/frontend/screens/profile/quick_replies_screen.dart';
import 'package:promax/frontend/theme/promax_theme.dart';
import 'package:promax/frontend/widgets/message_bubble.dart';
import 'package:promax/frontend/widgets/connection_status.dart';
import 'package:promax/l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _translationChannel = MethodChannel(
  'io.github.stillemptynow.promax/translate',
);

CachedMessage _message(String id, String text, bool mine) => CachedMessage(
  id: id,
  accountId: 101,
  chatId: 202,
  senderId: mine ? 101 : 303,
  text: text,
  time: DateTime(2026, 11, 1, 19, 41).millisecondsSinceEpoch,
  status: 'sent',
  payload: {'text': text},
);

Widget _chat() => Scaffold(
  appBar: AppBar(
    leading: const Icon(Symbols.arrow_back),
    title: const Row(
      children: [
        CircleAvatar(radius: 18, child: Text('А')),
        SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Аня', style: TextStyle(fontSize: 17)),
            Text(
              'в сети',
              style: TextStyle(fontSize: 11, color: Color(0xffa5c980)),
            ),
          ],
        ),
      ],
    ),
    actions: const [
      Icon(Symbols.call),
      SizedBox(width: 20),
      Icon(Symbols.more_vert),
      SizedBox(width: 14),
    ],
  ),
  body: Column(
    children: [
      Expanded(
        child: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xff191722), Color(0xff252138)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(12, 34, 12, 16),
            children: [
              const Center(
                child: Text(
                  'Сегодня',
                  style: TextStyle(fontSize: 12, color: Colors.white54),
                ),
              ),
              const SizedBox(height: 30),
              for (final message in [
                _message('synthetic-1', 'Привет! Как тебе ProMax?', false),
                _message(
                  'synthetic-2',
                  'Настроил тему. Теперь всё по-моему.',
                  true,
                ),
                _message('synthetic-3', "Let's meet at seven.", false),
                _message('synthetic-4', 'Отлично! Буду вовремя.', true),
              ])
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 7),
                  child: MessageBubble(
                    message: message,
                    isMe: message.senderId == 101,
                    myId: 101,
                    chatType: 'DIALOG',
                    chatId: 202,
                  ),
                ),
            ],
          ),
        ),
      ),
      SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              const Icon(Symbols.add),
              const SizedBox(width: 14),
              const Expanded(
                child: Text(
                  'Сообщение',
                  style: TextStyle(color: Colors.white54),
                ),
              ),
              Icon(Symbols.mic, color: Colors.purple.shade100),
            ],
          ),
        ),
      ),
    ],
  ),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('capture synthetic ProMax interface for promo', (tester) async {
    final output = Directory('media/promo/assets')..createSync(recursive: true);
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    SharedPreferences.setMockInitialValues({
      'promax_ghost_mode': true,
      'promax_anti_read': true,
      'promax_no_typing': true,
    });
    PackageInfo.setMockInitialValues(
      appName: 'ProMax',
      packageName: 'test.synthetic.promax',
      version: '1.1.0',
      buildNumber: '121',
      buildSignature: '',
    );
    AppPerformance.debugOverride(mode: PerformanceMode.smooth);
    addTearDown(AppPerformance.debugOverride);
    await ProMaxSettings.load();
    AppLock.instance.locked.value = false;
    for (final entry in {
      'Inter': 'assets/fonts/Inter.ttf',
      'Roboto': 'assets/fonts/Inter.ttf',
      'Outfit': 'assets/fonts/Outfit.ttf',
      'Unbounded': 'assets/fonts/Unbounded.ttf',
      'packages/material_symbols_icons/MaterialSymbolsOutlined':
          'packages/material_symbols_icons/lib/fonts/MaterialSymbolsOutlined.ttf',
    }.entries) {
      final loader = FontLoader(entry.key)
        ..addFont(rootBundle.load(entry.value));
      await loader.load();
    }
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          _translationChannel,
          (call) async => switch (call.method) {
            'capabilities' => {
              'available': true,
              'manageModels': true,
              'wifiOnlyOption': true,
            },
            'translate' => {'text': 'Давай встретимся в семь.', 'source': 'en'},
            'models' => ['en', 'ru'],
            _ => null,
          },
        );
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_translationChannel, null),
    );
    await MessageTranslator.instance.translate(
      MessageTranslator.keyOf(101, 202, 'synthetic-3'),
      "Let's meet at seven.",
      target: 'ru',
    );
    await QuickRepliesStore.instance.load(101);
    await QuickRepliesStore.instance.add(
      101,
      title: 'Буду скоро',
      text: 'Буду через 10 минут',
    );
    await QuickRepliesStore.instance.add(
      101,
      title: 'Перезвоню',
      text: 'Сейчас занят. Перезвоню чуть позже',
    );
    await QuickRepliesStore.instance.add(
      101,
      title: 'Спасибо',
      text: 'Спасибо, всё получил!',
    );
    tester.view.physicalSize = const Size(430, 860);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final captureKey = GlobalKey();
    final scheme = proMaxDarkScheme(
      ColorScheme.fromSeed(
        seedColor: const Color(0xffb6a0ff),
        brightness: Brightness.dark,
      ),
      amoled: false,
    );
    final theme = buildProMaxTheme(
      scheme: scheme,
      fontId: 'inter',
      glass: ProMaxGlassTheme.current(),
    );
    final captureTheme = withM3ETheme(
      theme,
      override: M3ETheme.defaults(scheme).copyWith(
        typography: M3ETypography.defaultFor(
          Brightness.dark,
          brandFontFamily: 'Inter',
          plainFontFamily: 'Inter',
        ),
      ),
    );
    Future<void> capture(
      String name,
      Widget screen, {
      double scroll = 0,
    }) async {
      Widget present(Widget content) => RepaintBoundary(
        key: captureKey,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          locale: const Locale('ru'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: captureTheme,
          home: content,
        ),
      );
      await tester.pumpWidget(present(screen));
      await tester.pump(const Duration(milliseconds: 200));
      final scaffold = tester.widget<Scaffold>(find.byType(Scaffold).first);
      if (scaffold.appBar case final ConnectionTitleBar bar) {
        await tester.pumpWidget(
          present(
            Scaffold(
              backgroundColor: scaffold.backgroundColor,
              appBar: AppBarM3E(titleText: bar.titleText),
              body: scaffold.body,
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 200));
      }
      if (scroll != 0) {
        await tester.drag(find.byType(ListView).first, Offset(0, -scroll));
        await tester.pump(const Duration(seconds: 1));
      }
      await tester.runAsync(() async {
        final image =
            await (captureKey.currentContext!.findRenderObject()!
                    as RenderRepaintBoundary)
                .toImage(pixelRatio: 2);
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        await File(
          '${output.path}/$name.png',
        ).writeAsBytes(data!.buffer.asUint8List());
        image.dispose();
      });
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    }

    await capture('chat', _chat());
    await capture('themes', const ProMaxDesignScreen());
    await capture('privacy', const ProMaxSettingsScreen(), scroll: 640);
    await capture('icons', const AppIconScreen());
    await capture('quick-replies', const QuickRepliesScreen(accountId: 101));
    await capture(
      'transfer',
      Scaffold(
        appBar: AppBar(title: const Text('Перенос ProMax')),
        body: const Padding(
          padding: EdgeInsets.all(16),
          child: ProMaxTransferCard(),
        ),
      ),
    );
    debugDefaultTargetPlatformOverride = null;
  });
}
