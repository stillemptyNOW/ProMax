enum HubKind {
  news,
  update,
  important,
  promo,
  holiday;

  static HubKind parse(Object? value) => HubKind.values.firstWhere(
    (kind) => kind.name == value,
    orElse: () => HubKind.news,
  );

  bool get urgent => this == important || this == update;
}

enum HubAction {
  link,
  update,
  settings;

  static HubAction parse(Object? value) => HubAction.values.firstWhere(
    (action) => action.name == value,
    orElse: () => HubAction.link,
  );
}

class HubMeta {
  const HubMeta({
    this.kind = HubKind.news,
    this.title = '',
    this.image = '',
    this.buttonLabel = '',
    this.buttonAction = HubAction.link,
    this.buttonUrl = '',
  });

  static const plain = HubMeta();

  final HubKind kind;
  final String title;
  final String image;
  final String buttonLabel;
  final HubAction buttonAction;
  final String buttonUrl;

  bool get hasButton =>
      buttonLabel.trim().isNotEmpty &&
      (buttonAction != HubAction.link || buttonUrl.isNotEmpty);

  factory HubMeta.fromJson(Map<String, dynamic> value) => HubMeta(
    kind: HubKind.parse(value['kind']),
    title: value['title'] as String? ?? '',
    image: value['image'] as String? ?? '',
    buttonLabel: value['button_label'] as String? ?? '',
    buttonAction: HubAction.parse(value['button_action']),
    buttonUrl: value['button_url'] as String? ?? '',
  );

  Map<String, Object> toJson() => {
    'kind': kind.name,
    'title': title,
    'image': image,
    'button_label': buttonLabel,
    'button_action': buttonAction.name,
    'button_url': buttonUrl,
  };

  HubMeta copyWith({
    HubKind? kind,
    String? title,
    String? image,
    String? buttonLabel,
    HubAction? buttonAction,
    String? buttonUrl,
  }) => HubMeta(
    kind: kind ?? this.kind,
    title: title ?? this.title,
    image: image ?? this.image,
    buttonLabel: buttonLabel ?? this.buttonLabel,
    buttonAction: buttonAction ?? this.buttonAction,
    buttonUrl: buttonUrl ?? this.buttonUrl,
  );

  @override
  bool operator ==(Object other) =>
      other is HubMeta &&
      other.kind == kind &&
      other.title == title &&
      other.image == image &&
      other.buttonLabel == buttonLabel &&
      other.buttonAction == buttonAction &&
      other.buttonUrl == buttonUrl;

  @override
  int get hashCode =>
      Object.hash(kind, title, image, buttonLabel, buttonAction, buttonUrl);
}

enum HubSpanStyle { plain, bold, link }

class HubSpan {
  const HubSpan(this.text, this.style, [this.url]);
  final String text;
  final HubSpanStyle style;
  final String? url;
}

class HubBlock {
  const HubBlock(this.spans, {this.bullet = false});
  final List<HubSpan> spans;
  final bool bullet;
}

abstract class HubRichText {
  static final _inline = RegExp(
    r'\*\*(.+?)\*\*|\[([^\]]+)\]\((https://[^\s)]+)\)|(https://[^\s)]+)',
  );
  static final _bullet = RegExp(r'^\s*(?:[-*•])\s+');

  static List<HubBlock> parse(String text) {
    final blocks = <HubBlock>[];
    for (final line in text.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;
      final bullet = _bullet.hasMatch(line);
      blocks.add(
        HubBlock(
          _spans(bullet ? line.replaceFirst(_bullet, '') : trimmed),
          bullet: bullet,
        ),
      );
    }
    return blocks;
  }

  static List<HubSpan> _spans(String line) {
    final spans = <HubSpan>[];
    var cursor = 0;
    for (final match in _inline.allMatches(line)) {
      if (match.start > cursor) {
        spans.add(
          HubSpan(line.substring(cursor, match.start), HubSpanStyle.plain),
        );
      }
      if (match.group(1) != null) {
        spans.add(HubSpan(match.group(1)!, HubSpanStyle.bold));
      } else if (match.group(3) != null) {
        spans.add(HubSpan(match.group(2)!, HubSpanStyle.link, match.group(3)));
      } else {
        spans.add(HubSpan(match.group(4)!, HubSpanStyle.link, match.group(4)));
      }
      cursor = match.end;
    }
    if (cursor < line.length) {
      spans.add(HubSpan(line.substring(cursor), HubSpanStyle.plain));
    }
    return spans;
  }

  static String plain(String text) => parse(
    text,
  ).map((block) => block.spans.map((span) => span.text).join()).join(' ');
}
