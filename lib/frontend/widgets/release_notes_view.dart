import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../core/utils/link_opener.dart';
import '../../core/utils/release_notes_markdown.dart';
import '../../core/utils/update_checker.dart';
import 'confirm_dialog.dart';

class ReleaseNotesView extends StatefulWidget {
  const ReleaseNotesView({super.key, required this.releases});

  final List<ReleaseNotes> releases;

  @override
  State<ReleaseNotesView> createState() => _ReleaseNotesViewState();
}

class _ReleaseNotesViewState extends State<ReleaseNotesView> {
  final Map<String, TapGestureRecognizer> _recognizers = {};
  late List<(ReleaseNotes, List<NotesBlock>)> _parsed;

  @override
  void initState() {
    super.initState();
    _parse();
  }

  @override
  void didUpdateWidget(covariant ReleaseNotesView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.releases, widget.releases)) _parse();
  }

  void _parse() {
    _parsed = [
      for (final release in widget.releases)
        (release, parseReleaseNotes(release.body)),
    ];
  }

  @override
  void dispose() {
    for (final recognizer in _recognizers.values) {
      recognizer.dispose();
    }
    super.dispose();
  }

  Future<void> _confirmOpen(String url) async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'Открыть ссылку?',
      message: url,
      confirmLabel: 'Открыть',
    );
    if (!confirmed || !mounted) return;
    await openExternalUrl(context, url);
  }

  TextSpan _inline(List<NotesSpan> spans, TextStyle base, ColorScheme cs) {
    return TextSpan(
      style: base,
      children: [
        for (final span in spans)
          TextSpan(
            text: span.text,
            style: TextStyle(
              fontWeight: span.bold ? FontWeight.w600 : null,
              fontStyle: span.italic ? FontStyle.italic : null,
              fontFamily: span.code ? 'monospace' : null,
              backgroundColor: span.code ? cs.surfaceContainerHighest : null,
              color: span.link != null ? cs.primary : null,
              decoration: span.link != null ? TextDecoration.underline : null,
              decorationColor: span.link != null ? cs.primary : null,
            ),
            recognizer: span.link == null ? null : _recognizerFor(span.link!),
          ),
      ],
    );
  }

  TapGestureRecognizer _recognizerFor(String url) => _recognizers.putIfAbsent(
    url,
    () => TapGestureRecognizer()..onTap = () => _confirmOpen(url),
  );

  Widget _block(NotesBlock block, ColorScheme cs) {
    final body = TextStyle(
      color: cs.onSurfaceVariant,
      fontSize: 13,
      height: 1.4,
    );
    switch (block.kind) {
      case NotesBlockKind.heading:
        return Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 2),
          child: Text.rich(
            _inline(
              block.spans,
              TextStyle(
                color: cs.onSurface,
                fontSize: block.level <= 2 ? 15 : 14,
                fontWeight: FontWeight.w600,
                height: 1.3,
              ),
              cs,
            ),
          ),
        );
      case NotesBlockKind.bullet:
      case NotesBlockKind.numbered:
        return Padding(
          padding: EdgeInsets.only(left: 4.0 + block.level * 14, top: 2),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: block.kind == NotesBlockKind.bullet ? 14 : 22,
                child: Text(
                  block.kind == NotesBlockKind.bullet
                      ? (block.level == 0 ? '•' : '◦')
                      : '${block.number}.',
                  style: body,
                ),
              ),
              Expanded(child: Text.rich(_inline(block.spans, body, cs))),
            ],
          ),
        );
      case NotesBlockKind.paragraph:
        return Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text.rich(_inline(block.spans, body, cs)),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final showTitles = _parsed.length > 1;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final (index, (release, blocks)) in _parsed.indexed) ...[
          if (showTitles)
            Padding(
              padding: EdgeInsets.only(top: index == 0 ? 0 : 14, bottom: 2),
              child: Text(
                release.title,
                style: TextStyle(
                  color: cs.primary,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          for (final block in blocks) _block(block, cs),
        ],
      ],
    );
  }
}
