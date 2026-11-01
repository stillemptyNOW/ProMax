import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../../../../core/storage/quick_replies_store.dart';

const String quickReplyTrigger = ';';

class QuickReplyQuery {
  const QuickReplyQuery({
    required this.start,
    required this.end,
    required this.text,
  });

  final int start;
  final int end;
  final String text;

  @override
  bool operator ==(Object other) =>
      other is QuickReplyQuery &&
      other.start == start &&
      other.end == end &&
      other.text == text;

  @override
  int get hashCode => Object.hash(start, end, text);
}

final RegExp _queryCharacters = RegExp(r'^[\p{L}\p{N}_-]*$', unicode: true);
final RegExp _whitespace = RegExp(r'\s');

QuickReplyQuery? quickReplyQueryAt(String text, int cursor) {
  if (cursor <= 0 || cursor > text.length) return null;
  const maxQueryLength = 32;
  final tokenStart = text.lastIndexOf(quickReplyTrigger, cursor - 1);
  if (tokenStart < 0) return null;
  if (tokenStart > 0 && !_whitespace.hasMatch(text[tokenStart - 1])) {
    return null;
  }
  final query = text.substring(tokenStart + 1, cursor);
  if (query.length > maxQueryLength) return null;
  if (!_queryCharacters.hasMatch(query)) return null;
  if (cursor < text.length && !_whitespace.hasMatch(text[cursor])) {
    return null;
  }
  return QuickReplyQuery(start: tokenStart, end: cursor, text: query);
}

TextEditingValue insertQuickReplyText(
  TextEditingValue value,
  String reply, {
  QuickReplyQuery? replacing,
}) {
  final text = value.text;
  final int start;
  final int end;
  if (replacing != null && replacing.end <= text.length) {
    start = replacing.start;
    end = replacing.end;
  } else if (value.selection.isValid) {
    start = value.selection.start.clamp(0, text.length);
    end = value.selection.end.clamp(start, text.length);
  } else {
    start = text.length;
    end = text.length;
  }
  return TextEditingValue(
    text: text.replaceRange(start, end, reply),
    selection: TextSelection.collapsed(offset: start + reply.length),
  );
}

class QuickReplyPanelController {
  QuickReplyPanelController({
    required TickerProvider vsync,
    required this.accountId,
    required this.enabled,
    required this.valueOf,
    required this.onSelected,
  }) {
    anim = AnimationController(
      vsync: vsync,
      duration: const Duration(milliseconds: 200),
    );
    QuickRepliesStore.instance.addListener(update);
  }

  final int Function() accountId;
  final bool Function() enabled;
  final TextEditingValue Function() valueOf;
  final void Function(QuickReply reply, QuickReplyQuery query) onSelected;

  late final AnimationController anim;
  final ValueNotifier<List<QuickReply>> matches = ValueNotifier(const []);
  QuickReplyQuery? _query;
  bool _visible = false;

  void update() {
    final query = enabled() ? _queryAt(valueOf()) : null;
    _query = query;
    final account = accountId();
    if (query != null) {
      unawaited(QuickRepliesStore.instance.ensureLoaded(account));
    }
    final found = query == null
        ? const <QuickReply>[]
        : matchQuickReplies(
            QuickRepliesStore.instance.repliesFor(account),
            query.text,
          );
    if (found.isNotEmpty && !listEquals(matches.value, found)) {
      matches.value = found;
    }
    _setVisible(found.isNotEmpty);
  }

  void select(QuickReply reply) {
    final query = _query;
    if (query == null) return;
    onSelected(reply, query);
  }

  QuickReplyQuery? _queryAt(TextEditingValue value) {
    final selection = value.selection;
    if (!selection.isValid || !selection.isCollapsed) return null;
    return quickReplyQueryAt(value.text, selection.baseOffset);
  }

  void _setVisible(bool show) {
    if (show == _visible) return;
    _visible = show;
    if (show) {
      anim.forward();
    } else {
      anim.reverse();
    }
  }

  void dispose() {
    QuickRepliesStore.instance.removeListener(update);
    anim.dispose();
    matches.dispose();
  }
}
