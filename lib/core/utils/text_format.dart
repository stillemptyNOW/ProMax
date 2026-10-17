import 'package:flutter/material.dart';

// #***! виды форматирования текста
enum TextFormat {
  heading,
  strong,
  emphasized,
  underline,
  strikethrough,
  monospaced,
  quote,
  link,
  animoji,
  userMention,
}

// #***! на проводе форматы это строки капсом
const Map<TextFormat, String> _formatToServer = {
  TextFormat.heading: 'HEADING',
  TextFormat.strong: 'STRONG',
  TextFormat.emphasized: 'EMPHASIZED',
  TextFormat.underline: 'UNDERLINE',
  TextFormat.strikethrough: 'STRIKETHROUGH',
  TextFormat.monospaced: 'MONOSPACED',
  TextFormat.quote: 'QUOTE',
  TextFormat.link: 'LINK',
  TextFormat.animoji: 'ANIMOJI',
  TextFormat.userMention: 'USER_MENTION',
};

final Map<String, TextFormat> _serverToFormat = {
  for (final e in _formatToServer.entries) e.value: e.key,
};

String textFormatToServer(TextFormat format) => _formatToServer[format]!;

TextFormat? textFormatFromServer(String? raw) =>
    raw == null ? null : _serverToFormat[raw];

// #***! отрезок форматирования, откуда сколько и чем
class FormatRange {
  final TextFormat format;
  final int start;
  final int length;
  final int? entityId;
  final String? entityName;
  final Map<String, dynamic>? attributes;

  const FormatRange({
    required this.format,
    required this.start,
    required this.length,
    this.entityId,
    this.entityName,
    this.attributes,
  });

  int get end => start + length;

  // #***! у ссылки и анимодзи детали в attributes
  String? get url {
    final value = attributes?['url'];
    return value is String ? value : null;
  }

  String? get animojiUrl {
    final value = attributes?['animojiLottieUrl'];
    return value is String && value.isNotEmpty ? value : null;
  }

  // #***! обратно в вид для сервера
  Map<String, dynamic> toServer() => {
    'type': textFormatToServer(format),
    'from': start,
    'length': length,
    if (entityId != null) 'entityId': entityId,
    if (entityName != null) 'entityName': entityName,
    if (attributes != null) 'attributes': attributes,
  };
}

// #***! разбор elements, незнакомые типы пропускаем
List<FormatRange> parseFormatElements(dynamic raw) {
  if (raw is! List) return const [];
  final result = <FormatRange>[];
  for (final item in raw) {
    if (item is! Map) continue;
    final format = textFormatFromServer(item['type']?.toString());
    if (format == null) continue;
    final from = _asInt(item['from']);
    final length = _asInt(item['length']);
    if (length <= 0) continue;
    final attrsRaw = item['attributes'];
    final attributes = attrsRaw is Map
        ? Map<String, dynamic>.from(attrsRaw)
        : null;
    final entityId = item['entityId'];
    final entityName = item['entityName'];
    result.add(
      FormatRange(
        format: format,
        start: from,
        length: length,
        entityId: entityId is int ? entityId : null,
        entityName: entityName is String && entityName.isNotEmpty
            ? entityName
            : null,
        attributes: attributes,
      ),
    );
  }
  return result;
}

List<Map<String, dynamic>> serializeFormatElements(
  Iterable<FormatRange> ranges,
) => [for (final range in ranges) range.toServer()];

// #***! сообщение только из анимодзи рисуется крупно, тут это и проверяем
List<String>? animojiOnlyLottieUrls(
  String? text,
  List<FormatRange> ranges, {
  int limit = 4,
}) {
  if (text == null || text.isEmpty) return null;
  final len = text.length;
  final animoji =
      ranges
          .where((r) => r.format == TextFormat.animoji && r.animojiUrl != null)
          .toList()
        ..sort((a, b) => a.start.compareTo(b.start));
  if (animoji.isEmpty || animoji.length > limit) return null;

  var cursor = 0;
  for (final r in animoji) {
    final start = r.start.clamp(0, len).toInt();
    // #***! между анимодзи только пробелы, иначе это обычный текст
    if (text.substring(cursor.clamp(0, len).toInt(), start).trim().isNotEmpty) {
      return null;
    }
    cursor = r.end.clamp(0, len).toInt();
  }
  if (text.substring(cursor.clamp(0, len).toInt()).trim().isNotEmpty) {
    return null;
  }
  return [for (final r in animoji) r.animojiUrl!];
}

const List<(int, int)> _emojiRuneRanges = [
  (0x0023, 0x0023),
  (0x002A, 0x002A),
  (0x0030, 0x0039),
  (0x00A9, 0x00A9),
  (0x00AE, 0x00AE),
  (0x200D, 0x200D),
  (0x203C, 0x203C),
  (0x2049, 0x2049),
  (0x20E3, 0x20E3),
  (0x2122, 0x2122),
  (0x2139, 0x2139),
  (0x2190, 0x21FF),
  (0x2300, 0x23FF),
  (0x24C2, 0x24C2),
  (0x25AA, 0x25FE),
  (0x2600, 0x27BF),
  (0x2934, 0x2935),
  (0x2B00, 0x2BFF),
  (0x3030, 0x3030),
  (0x303D, 0x303D),
  (0x3297, 0x3297),
  (0x3299, 0x3299),
  (0xFE0F, 0xFE0F),
  (0x1F000, 0x1FAFF),
  (0xE0020, 0xE007F),
];

bool _isEmojiRune(int rune) {
  for (final (low, high) in _emojiRuneRanges) {
    if (rune >= low && rune <= high) return true;
  }
  return false;
}

bool isEmojiGlyph(String glyph) {
  var presented = false;
  for (final rune in glyph.runes) {
    if (!_isEmojiRune(rune)) return false;
    if (rune >= 0x1F000 || rune == 0xFE0F || rune == 0x20E3) presented = true;
  }
  return presented;
}

List<String>? emojiOnlyGlyphs(
  String? text,
  List<FormatRange> ranges, {
  int limit = 3,
}) {
  if (text == null || ranges.isNotEmpty) return null;
  final glyphs = <String>[];
  for (final glyph in text.characters) {
    if (glyph.trim().isEmpty) continue;
    if (!isEmojiGlyph(glyph)) return null;
    glyphs.add(glyph);
    if (glyphs.length > limit) return null;
  }
  return glyphs.isEmpty ? null : glyphs;
}

int _asInt(dynamic value) {
  if (value is int) return value;
  if (value is String) return int.tryParse(value) ?? 0;
  return 0;
}

// #***! отрезок с наложенными форматами, его рисует один TextSpan
class FormatSegment {
  final int start;
  final int end;
  final Set<TextFormat> formats;
  final String? url;
  final String? animojiUrl;
  final int? mentionId;
  final String? mentionName;

  const FormatSegment({
    required this.start,
    required this.end,
    required this.formats,
    this.url,
    this.animojiUrl,
    this.mentionId,
    this.mentionName,
  });
}

// #***! режем текст по границам форматов чтоб куски не пересекались
List<FormatSegment> segmentizeFormats(String text, List<FormatRange> ranges) {
  if (text.isEmpty) return const [];
  final length = text.length;
  final clamped = <FormatRange>[];
  for (final range in ranges) {
    final start = range.start.clamp(0, length);
    final end = range.end.clamp(0, length);
    if (end <= start) continue;
    clamped.add(
      FormatRange(
        format: range.format,
        start: start,
        length: end - start,
        entityId: range.entityId,
        entityName: range.entityName,
        attributes: range.attributes,
      ),
    );
  }
  if (clamped.isEmpty) {
    return [FormatSegment(start: 0, end: length, formats: const {})];
  }

  // #***! собираем границы, между соседними формат постоянен
  final boundaries = <int>{0, length};
  for (final range in clamped) {
    boundaries.add(range.start);
    boundaries.add(range.end);
  }
  final points = boundaries.toList()..sort();

  final segments = <FormatSegment>[];
  for (var i = 0; i < points.length - 1; i++) {
    final start = points[i];
    final end = points[i + 1];
    if (end <= start) continue;
    final formats = <TextFormat>{};
    String? url;
    String? animojiUrl;
    int? mentionId;
    String? mentionName;
    // #***! формат наследуется только если отрезок целиком внутри
    for (final range in clamped) {
      if (range.start <= start && range.end >= end) {
        formats.add(range.format);
        if (range.format == TextFormat.link) url ??= range.url;
        if (range.format == TextFormat.animoji) animojiUrl ??= range.animojiUrl;
        if (range.format == TextFormat.userMention) {
          mentionId ??= range.entityId;
          mentionName ??= range.entityName;
        }
      }
    }
    segments.add(
      FormatSegment(
        start: start,
        end: end,
        formats: formats,
        url: url,
        animojiUrl: animojiUrl,
        mentionId: mentionId,
        mentionName: mentionName,
      ),
    );
  }
  return segments;
}

// #***! форматы в TextStyle
TextStyle applyTextFormats(
  TextStyle base,
  Set<TextFormat> formats, {
  Color? quoteColor,
  Color? mentionColor,
  Paint? quoteBackground,
}) {
  if (formats.isEmpty) return base;

  final decorations = <TextDecoration>[];
  if (formats.contains(TextFormat.underline) ||
      formats.contains(TextFormat.link)) {
    decorations.add(TextDecoration.underline);
  }
  if (formats.contains(TextFormat.strikethrough)) {
    decorations.add(TextDecoration.lineThrough);
  }

  final isItalic = formats.contains(TextFormat.emphasized);

  final isQuote = formats.contains(TextFormat.quote);
  final isMention = formats.contains(TextFormat.userMention);
  final isHeading = formats.contains(TextFormat.heading);

  return base.copyWith(
    fontSize: isHeading ? (base.fontSize ?? 16) * 1.08 : null,
    fontWeight: formats.contains(TextFormat.strong) || isHeading
        ? FontWeight.w700
        : null,
    fontStyle: isItalic ? FontStyle.italic : null,
    fontFamily: formats.contains(TextFormat.monospaced) ? 'monospace' : null,
    background: isQuote ? quoteBackground : null,
    color: isMention ? mentionColor : (isQuote ? quoteColor : null),
    decoration: decorations.isEmpty
        ? null
        : TextDecoration.combine(decorations),
  );
}
