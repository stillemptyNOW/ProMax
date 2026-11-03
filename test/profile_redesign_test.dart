import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promax/core/config/app_design.dart';
import 'package:promax/core/storage/app_database.dart';
import 'package:promax/frontend/screens/chats/chat_info_screen.dart';
import 'package:promax/frontend/screens/profile/self_profile_preview_screen.dart';
import 'package:promax/frontend/widgets/person_profile_scroll_view.dart';
import 'package:promax/l10n/app_localizations.dart';

void main() {
  Widget host(Widget child) => MaterialApp(
    locale: const Locale('en'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: child,
  );

  tearDown(() => AppDesign.classic.value = false);

  testWidgets('profile avatar collapses into a pinned title when scrolling', (
    tester,
  ) async {
    const avatar = ValueKey('synthetic-avatar');
    await tester.pumpWidget(
      host(
        Scaffold(
          body: PersonProfileScrollView(
            name: 'Synthetic profile',
            subtitle: 'Synthetic status',
            avatarBuilder: (_) =>
                const ColoredBox(key: avatar, color: Colors.blue),
            body: const SizedBox(
              height: 1200,
              child: Text('Synthetic information'),
            ),
          ),
        ),
      ),
    );
    expect(tester.getSize(find.byKey(avatar)).width, 156);
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -450));
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byKey(avatar)).width, 34);
    expect(find.text('Synthetic profile'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'self preview uses the real profile renderer without contact actions',
    (tester) async {
      final profile = ProfileData(
        id: 8101,
        firstName: 'Synthetic',
        lastName: 'Profile',
        phone: 0,
        country: 'RU',
        accountStatus: 0,
        updateTime: 1,
        description: 'Synthetic public description',
      );
      await tester.pumpWidget(host(SelfProfilePreviewScreen(profile: profile)));
      await tester.pumpAndSettle();
      expect(find.byType(ChatInfoScreen), findsOneWidget);
      expect(find.byType(PersonProfileScrollView), findsOneWidget);
      expect(find.text('Synthetic public description'), findsOneWidget);
      expect(find.text('8101'), findsOneWidget);
      expect(find.text('Call'), findsNothing);
      expect(find.text('Message'), findsNothing);
      expect(tester.takeException(), isNull);
      AppDesign.classic.value = true;
      await tester.pumpAndSettle();
      expect(find.byType(PersonProfileScrollView), findsNothing);
      expect(find.byType(ChatInfoScreen), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('profile header fits narrow screens with larger text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      host(
        MediaQuery(
          data: const MediaQueryData(
            size: Size(320, 640),
            textScaler: TextScaler.linear(1.6),
          ),
          child: Scaffold(
            body: PersonProfileScrollView(
              name: 'Synthetic long public profile name',
              subtitle: 'Synthetic status',
              avatarBuilder: (_) => const ColoredBox(color: Colors.blue),
              body: const SizedBox(height: 1200),
            ),
          ),
        ),
      ),
    );
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -400));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
