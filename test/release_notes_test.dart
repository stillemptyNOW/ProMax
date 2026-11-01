import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promax/core/utils/release_notes_markdown.dart';
import 'package:promax/core/utils/update_checker.dart';
import 'package:promax/frontend/widgets/release_notes_view.dart';
import 'package:promax/l10n/app_localizations.dart';

Map<String, Object?> _release(
  String tag, {
  String body = '',
  String? name,
  bool draft = false,
}) => {
  'tag_name': tag,
  'name': ?name,
  'body': body,
  'draft': draft,
  'html_url': 'https://example.com/releases/$tag',
  'assets': const [],
};

void main() {
  group('releaseNotesNewerThan', () {
    final releases = [
      _release('v1.1.0-beta.11+121', body: 'eleven'),
      _release('v1.1.0-beta.13+123', body: 'thirteen', name: 'Beta 13'),
      _release('v1.1.0-beta.12+122', body: 'twelve\r\nline'),
      _release('v1.1.0-beta.14+124', body: 'draft', draft: true),
      _release('nightly', body: 'nightly'),
      _release('v1.1.0-beta.10+120', body: 'ten'),
    ];

    test('keeps every newer release, newest first', () {
      final notes = releaseNotesNewerThan(
        releases,
        currentVersion: '1.1.0',
        currentBuild: 121,
      );
      expect(notes.map((n) => n.tag), [
        'v1.1.0-beta.13+123',
        'v1.1.0-beta.12+122',
      ]);
      expect(notes.first.title, 'Beta 13');
      expect(notes.last.title, 'v1.1.0-beta.12+122');
      expect(notes.last.body, 'twelve\nline');
    });

    test('is empty when the app is current', () {
      expect(
        releaseNotesNewerThan(
          releases,
          currentVersion: '1.1.0',
          currentBuild: 123,
        ),
        isEmpty,
      );
    });

    test('the update carries notes of all skipped releases', () {
      final update = updateFromReleases(
        releases,
        currentVersion: '1.1.0',
        currentBuild: 120,
      )!;
      expect(update.tag, 'v1.1.0-beta.13+123');
      expect(update.releaseNotes.map((n) => n.body), [
        'thirteen',
        'twelve\nline',
        'eleven',
      ]);
      expect(
        updateFromReleases(
          releases,
          currentVersion: '1.1.0',
          currentBuild: 123,
        ),
        isNull,
      );
    });
  });

  group('parseReleaseNotes', () {
    test('splits headings, bullets, numbers and paragraphs', () {
      final blocks = parseReleaseNotes(
        '## Что нового\n'
        '<!-- hidden -->\n'
        '- Первый пункт\n'
        '  продолжение\n'
        '  * вложенный\n'
        '1. Нумерованный\n'
        '\n'
        'Абзац\nв две строки\n'
        '---\n'
        '```\ncode line\n```',
      );
      expect(blocks.map((b) => b.kind), [
        NotesBlockKind.heading,
        NotesBlockKind.bullet,
        NotesBlockKind.bullet,
        NotesBlockKind.numbered,
        NotesBlockKind.paragraph,
        NotesBlockKind.paragraph,
      ]);
      expect(blocks[0].level, 2);
      expect(blocks[0].plainText, 'Что нового');
      expect(blocks[1].plainText, 'Первый пункт продолжение');
      expect(blocks[2].level, 1);
      expect(blocks[3].number, 1);
      expect(blocks[4].plainText, 'Абзац в две строки');
      expect(blocks[5].spans.single, const NotesSpan('code line', code: true));
    });

    test('parses bold, italic, code and links', () {
      expect(
        parseInlineMarkdown(
          'Это **жирный** и *курсив*, `код` и [сайт](https://example.com/a)',
        ),
        const [
          NotesSpan('Это '),
          NotesSpan('жирный', bold: true),
          NotesSpan(' и '),
          NotesSpan('курсив', italic: true),
          NotesSpan(', '),
          NotesSpan('код', code: true),
          NotesSpan(' и '),
          NotesSpan('сайт', link: 'https://example.com/a'),
        ],
      );
    });

    test('links bare and angle urls but drops unsafe schemes', () {
      expect(
        parseInlineMarkdown(
          'См. https://example.com/x. и <https://example.org>',
        ),
        const [
          NotesSpan('См. '),
          NotesSpan('https://example.com/x', link: 'https://example.com/x'),
          NotesSpan('. и '),
          NotesSpan('https://example.org', link: 'https://example.org'),
        ],
      );
      expect(
        parseInlineMarkdown('[жми](javascript:alert(1))').first.link,
        isNull,
      );
      expect(parseInlineMarkdown(r'\*не курсив\*'), const [
        NotesSpan('*не курсив*'),
      ]);
      expect(parseInlineMarkdown('2 * 3'), const [NotesSpan('2 * 3')]);
    });
  });

  testWidgets('renders notes and asks before opening a link', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: Locale('ru'),
        home: Scaffold(
          body: ReleaseNotesView(
            releases: [
              ReleaseNotes(
                tag: 'v2',
                version: '2.0.0',
                build: 2,
                title: 'Версия 2',
                body: '## Главное\n- **Новое** [ссылка](https://example.com)',
              ),
              ReleaseNotes(
                tag: 'v1',
                version: '1.0.0',
                build: 1,
                title: 'Версия 1',
                body: 'Старое',
              ),
            ],
          ),
        ),
      ),
    );
    expect(find.text('Версия 2'), findsOneWidget);
    expect(find.text('Версия 1'), findsOneWidget);
    expect(find.text('Главное'), findsOneWidget);
    expect(find.text('Новое ссылка', findRichText: true), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('Версия 2')).dy,
      lessThan(tester.getTopLeft(find.text('Версия 1')).dy),
    );

    final rich = tester.widget<RichText>(
      find.text('Новое ссылка', findRichText: true),
    );
    TapGestureRecognizer? recognizer;
    rich.text.visitChildren((span) {
      if (span is TextSpan && span.recognizer is TapGestureRecognizer) {
        recognizer = span.recognizer! as TapGestureRecognizer;
      }
      return recognizer == null;
    });
    recognizer!.onTap!();
    await tester.pumpAndSettle();
    expect(find.text('Открыть ссылку?'), findsOneWidget);
    expect(find.text('https://example.com'), findsOneWidget);
  });
}
