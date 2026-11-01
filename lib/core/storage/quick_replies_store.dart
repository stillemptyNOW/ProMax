import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

@immutable
class QuickReply {
  const QuickReply({required this.id, required this.title, required this.text});

  final String id;
  final String title;
  final String text;

  String get label => title.isEmpty ? text : title;

  bool matches(String query) {
    if (query.isEmpty) return true;
    final needle = query.toLowerCase();
    return title.toLowerCase().contains(needle) ||
        text.toLowerCase().contains(needle);
  }

  int rankFor(String query) {
    final needle = query.toLowerCase();
    bool wordStarts(String source) => source
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .any((word) => word.startsWith(needle));
    if (wordStarts(title)) return 0;
    if (wordStarts(text)) return 1;
    return 2;
  }

  QuickReply copyWith({String? title, String? text}) =>
      QuickReply(id: id, title: title ?? this.title, text: text ?? this.text);

  Map<String, String> toJson() => {
    'id': id,
    if (title.isNotEmpty) 'title': title,
    'text': text,
  };

  static QuickReply? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id'];
    final text = raw['text'];
    if (id is! String || id.isEmpty || text is! String) return null;
    if (text.trim().isEmpty) return null;
    final title = raw['title'];
    return QuickReply(
      id: id,
      title: title is String ? title.trim() : '',
      text: text,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is QuickReply &&
      other.id == id &&
      other.title == title &&
      other.text == text;

  @override
  int get hashCode => Object.hash(id, title, text);
}

enum QuickReplySaveResult { saved, empty, limitReached }

List<QuickReply> matchQuickReplies(List<QuickReply> replies, String query) {
  final trimmed = query.trim();
  if (trimmed.isEmpty) return replies;
  final ranked =
      [
        for (final (index, reply) in replies.indexed)
          if (reply.matches(trimmed))
            (rank: reply.rankFor(trimmed), index: index),
      ]..sort((a, b) {
        final byRank = a.rank.compareTo(b.rank);
        return byRank != 0 ? byRank : a.index.compareTo(b.index);
      });
  return [for (final entry in ranked) replies[entry.index]];
}

class QuickRepliesStore extends ChangeNotifier {
  QuickRepliesStore._();

  static final QuickRepliesStore instance = QuickRepliesStore._();

  static const legacyPrefKey = 'promax_quick_replies';
  static const prefKeyPrefix = 'promax_quick_replies_v2_';
  static const int maxCount = 50;
  static const int maxLength = 2000;
  static const int maxTitleLength = 64;

  final Map<int, List<QuickReply>> _replies = {};
  final Map<int, Future<void>> _loading = {};
  int _idCounter = 0;

  static String prefKeyFor(int accountId) => '$prefKeyPrefix$accountId';

  List<QuickReply> repliesFor(int accountId) => _replies[accountId] ?? const [];

  Future<void> ensureLoaded(int accountId) {
    if (accountId == 0 || _replies.containsKey(accountId)) {
      return Future.value();
    }
    return _loading[accountId] ??= load(accountId);
  }

  Future<void> load(int accountId) async {
    if (accountId == 0) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(prefKeyFor(accountId));
      final legacy = prefs.getStringList(legacyPrefKey);
      if (raw == null && legacy != null) {
        final migrated = [
          for (final text in legacy)
            if (_cleanText(text) case final clean?)
              QuickReply(id: _newId(), title: '', text: clean),
        ];
        await prefs.setString(prefKeyFor(accountId), _encode(migrated));
        await prefs.remove(legacyPrefKey);
        _set(accountId, migrated);
        return;
      }
      _set(accountId, _decode(raw));
    } finally {
      _loading.remove(accountId);
    }
  }

  Future<QuickReplySaveResult> add(
    int accountId, {
    String title = '',
    required String text,
  }) async {
    final clean = _cleanText(text);
    if (accountId == 0 || clean == null) return QuickReplySaveResult.empty;
    await ensureLoaded(accountId);
    final current = repliesFor(accountId);
    if (current.length >= maxCount) return QuickReplySaveResult.limitReached;
    await _save(accountId, [
      ...current,
      QuickReply(id: _newId(), title: _cleanTitle(title), text: clean),
    ]);
    return QuickReplySaveResult.saved;
  }

  Future<QuickReplySaveResult> update(
    int accountId,
    String id, {
    String title = '',
    required String text,
  }) async {
    final clean = _cleanText(text);
    if (clean == null) return QuickReplySaveResult.empty;
    final current = repliesFor(accountId);
    final index = current.indexWhere((reply) => reply.id == id);
    if (index < 0) return QuickReplySaveResult.empty;
    final next = [...current];
    next[index] = current[index].copyWith(
      title: _cleanTitle(title),
      text: clean,
    );
    await _save(accountId, next);
    return QuickReplySaveResult.saved;
  }

  Future<void> remove(int accountId, String id) async {
    final current = repliesFor(accountId);
    if (!current.any((reply) => reply.id == id)) return;
    await _save(accountId, [
      for (final reply in current)
        if (reply.id != id) reply,
    ]);
  }

  Future<void> move(int accountId, int from, int to) async {
    final next = [...repliesFor(accountId)];
    if (from < 0 || from >= next.length) return;
    final item = next.removeAt(from);
    next.insert(to.clamp(0, next.length), item);
    await _save(accountId, next);
  }

  Future<void> forget(int accountId) async {
    _replies.remove(accountId);
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(prefKeyFor(accountId));
    notifyListeners();
  }

  @visibleForTesting
  void resetForTest() {
    _replies.clear();
    _loading.clear();
  }

  String _newId() {
    _idCounter++;
    return '${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}'
        '-${_idCounter.toRadixString(36)}';
  }

  static String? _cleanText(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return null;
    return trimmed.length > maxLength
        ? trimmed.substring(0, maxLength)
        : trimmed;
  }

  static String _cleanTitle(String title) {
    final single = title.replaceAll(RegExp(r'\s+'), ' ').trim();
    return single.length > maxTitleLength
        ? single.substring(0, maxTitleLength)
        : single;
  }

  static List<QuickReply> _decode(String? raw) {
    if (raw == null) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      final seen = <String>{};
      return [
        for (final entry in decoded)
          if (QuickReply.fromJson(entry) case final reply?
              when seen.add(reply.id))
            reply,
      ];
    } catch (_) {
      return const [];
    }
  }

  static String _encode(List<QuickReply> replies) =>
      jsonEncode([for (final reply in replies) reply.toJson()]);

  void _set(int accountId, List<QuickReply> replies) {
    _replies[accountId] = List.unmodifiable(replies);
    notifyListeners();
  }

  Future<void> _save(int accountId, List<QuickReply> next) async {
    _set(accountId, next);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(prefKeyFor(accountId), _encode(next));
  }
}
