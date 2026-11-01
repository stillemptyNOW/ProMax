import 'package:flutter/foundation.dart';

@immutable
class NotesSpan {
  const NotesSpan(
    this.text, {
    this.bold = false,
    this.italic = false,
    this.code = false,
    this.link,
  });

  final String text;
  final bool bold;
  final bool italic;
  final bool code;
  final String? link;

  @override
  bool operator ==(Object other) =>
      other is NotesSpan &&
      other.text == text &&
      other.bold == bold &&
      other.italic == italic &&
      other.code == code &&
      other.link == link;

  @override
  int get hashCode => Object.hash(text, bold, italic, code, link);

  @override
  String toString() =>
      'NotesSpan($text${bold ? ', bold' : ''}${italic ? ', italic' : ''}'
      '${code ? ', code' : ''}${link == null ? '' : ', link: $link'})';
}

enum NotesBlockKind { heading, bullet, numbered, paragraph }

@immutable
class NotesBlock {
  const NotesBlock({
    required this.kind,
    required this.spans,
    this.level = 0,
    this.number,
  });

  final NotesBlockKind kind;
  final List<NotesSpan> spans;
  final int level;
  final int? number;

  String get plainText => spans.map((span) => span.text).join();
}

final RegExp _heading = RegExp(r'^(#{1,6})\s+(.*?)\s*#*\s*$');
final RegExp _bullet = RegExp(r'^(\s*)[-*+]\s+(.*)$');
final RegExp _numbered = RegExp(r'^(\s*)(\d{1,4})[.)]\s+(.*)$');
final RegExp _rule = RegExp(r'^\s*([-*_])(\s*\1){2,}\s*$');
final RegExp _htmlComment = RegExp(r'<!--.*?-->', dotAll: true);
final RegExp _bareUrl = RegExp(r'https?://[^\s<>]+');
final RegExp _trailingPunctuation = RegExp(r'[.,;:!?)\]]+$');

List<NotesBlock> parseReleaseNotes(String markdown) {
  final source = markdown
      .replaceAll('\r\n', '\n')
      .replaceAll('\r', '\n')
      .replaceAll(_htmlComment, '');
  final blocks = <NotesBlock>[];
  final paragraph = <String>[];
  NotesBlock? openItem;
  final itemLines = <String>[];

  void flushParagraph() {
    if (paragraph.isEmpty) return;
    blocks.add(
      NotesBlock(
        kind: NotesBlockKind.paragraph,
        spans: parseInlineMarkdown(paragraph.join(' ')),
      ),
    );
    paragraph.clear();
  }

  void flushItem() {
    final item = openItem;
    if (item == null) return;
    blocks.add(
      NotesBlock(
        kind: item.kind,
        level: item.level,
        number: item.number,
        spans: parseInlineMarkdown(itemLines.join(' ')),
      ),
    );
    openItem = null;
    itemLines.clear();
  }

  void flush() {
    flushParagraph();
    flushItem();
  }

  var inFence = false;
  for (final rawLine in source.split('\n')) {
    final line = rawLine.trimRight();
    if (line.trimLeft().startsWith('```')) {
      flush();
      inFence = !inFence;
      continue;
    }
    if (inFence) {
      if (line.trim().isNotEmpty) {
        blocks.add(
          NotesBlock(
            kind: NotesBlockKind.paragraph,
            spans: [NotesSpan(line.trim(), code: true)],
          ),
        );
      }
      continue;
    }
    if (line.trim().isEmpty || _rule.hasMatch(line)) {
      flush();
      continue;
    }
    final heading = _heading.firstMatch(line.trimLeft());
    if (heading != null) {
      flush();
      final text = heading.group(2)!;
      if (text.isNotEmpty) {
        blocks.add(
          NotesBlock(
            kind: NotesBlockKind.heading,
            level: heading.group(1)!.length,
            spans: parseInlineMarkdown(text),
          ),
        );
      }
      continue;
    }
    final bullet = _bullet.firstMatch(line);
    final numbered = bullet == null ? _numbered.firstMatch(line) : null;
    if (bullet != null || numbered != null) {
      flush();
      final indent = (bullet ?? numbered)!.group(1)!.length;
      openItem = NotesBlock(
        kind: bullet != null ? NotesBlockKind.bullet : NotesBlockKind.numbered,
        level: (indent ~/ 2).clamp(0, 3),
        number: numbered == null ? null : int.parse(numbered.group(2)!),
        spans: const [],
      );
      itemLines.add(bullet != null ? bullet.group(2)! : numbered!.group(3)!);
      continue;
    }
    final text = line.trim().replaceFirst(RegExp(r'^>\s?'), '');
    if (openItem != null && rawLine.startsWith(RegExp(r'\s'))) {
      itemLines.add(text);
      continue;
    }
    flushItem();
    paragraph.add(text);
  }
  flush();
  return blocks;
}

String? _safeLink(String raw) {
  final uri = Uri.tryParse(raw.trim());
  if (uri == null || !uri.hasAuthority) return null;
  final scheme = uri.scheme.toLowerCase();
  if (scheme != 'https' && scheme != 'http') return null;
  return uri.toString();
}

List<NotesSpan> parseInlineMarkdown(String text) {
  final spans = <NotesSpan>[];
  final buffer = StringBuffer();
  var bold = false;
  var italic = false;

  void emit({bool code = false, String? link, String? content}) {
    final value = content ?? buffer.toString();
    if (content == null) buffer.clear();
    if (value.isEmpty) return;
    final span = NotesSpan(
      value,
      bold: bold,
      italic: italic,
      code: code,
      link: link,
    );
    if (spans.isNotEmpty) {
      final last = spans.last;
      if (last.bold == span.bold &&
          last.italic == span.italic &&
          !last.code &&
          !span.code &&
          last.link == null &&
          span.link == null) {
        spans[spans.length - 1] = NotesSpan(
          last.text + span.text,
          bold: bold,
          italic: italic,
        );
        return;
      }
    }
    spans.add(span);
  }

  var i = 0;
  while (i < text.length) {
    final char = text[i];
    if (char == r'\' && i + 1 < text.length) {
      buffer.write(text[i + 1]);
      i += 2;
      continue;
    }
    if (char == '`') {
      final close = text.indexOf('`', i + 1);
      if (close > i + 1) {
        emit();
        emit(code: true, content: text.substring(i + 1, close));
        i = close + 1;
        continue;
      }
    }
    final pair = i + 1 < text.length ? text.substring(i, i + 2) : '';
    if (pair == '**' || pair == '__') {
      if (bold || text.indexOf(pair, i + 2) > i + 2) {
        emit();
        bold = !bold;
        i += 2;
        continue;
      }
    }
    if (char == '*' && (italic || text.indexOf('*', i + 1) > i + 1)) {
      emit();
      italic = !italic;
      i += 1;
      continue;
    }
    if (char == '[') {
      final labelEnd = text.indexOf('](', i + 1);
      final urlEnd = labelEnd < 0 ? -1 : text.indexOf(')', labelEnd + 2);
      if (labelEnd > i && urlEnd > labelEnd) {
        final label = text.substring(i + 1, labelEnd);
        final link = _safeLink(text.substring(labelEnd + 2, urlEnd));
        emit();
        final shown = label.replaceAll(RegExp(r'[*_`]'), '');
        emit(link: link, content: shown.isEmpty ? (link ?? '') : shown);
        i = urlEnd + 1;
        continue;
      }
    }
    if (char == '<') {
      final close = text.indexOf('>', i + 1);
      if (close > i) {
        final link = _safeLink(text.substring(i + 1, close));
        if (link != null) {
          emit();
          emit(link: link, content: text.substring(i + 1, close));
          i = close + 1;
          continue;
        }
      }
    }
    if (char == 'h' && (i == 0 || !RegExp(r'\w').hasMatch(text[i - 1]))) {
      final match = _bareUrl.matchAsPrefix(text, i);
      if (match != null) {
        final raw = match[0]!.replaceFirst(_trailingPunctuation, '');
        final link = _safeLink(raw);
        if (link != null) {
          emit();
          emit(link: link, content: raw);
          i += raw.length;
          continue;
        }
      }
    }
    buffer.write(char);
    i += 1;
  }
  emit();
  return spans;
}
