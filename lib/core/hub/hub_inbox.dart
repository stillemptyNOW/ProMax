import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import '../storage/token_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/app_foreground.dart';
import 'hub_client.dart';
import 'hub_content.dart';

class HubAdminIdentity {
  const HubAdminIdentity({required this.accountId, required this.phone});
  final int accountId;
  final int phone;
  bool matches(int account, int number) =>
      account == accountId && number == phone;
}

class HubInbox extends ChangeNotifier {
  HubInbox({
    required this.accountId,
    required this.phone,
    HubClient? client,
    this.adminIdentity = const HubAdminIdentity(
      accountId: 461448957,
      phone: adminPhone,
    ),
  }) : client = client ?? HubClient();

  static const adminPhone = 79920854267;
  final int accountId;
  final int phone;
  final HubClient client;
  final HubAdminIdentity adminIdentity;
  List<HubMessage> messages = const [];
  HubDraft? draft;
  String? editingText;
  HubMeta? editingMeta;
  Set<int> _hidden = {};
  Set<int> _bannerDismissed = {};
  bool muted = false;
  String? _token;
  int _seen = 0;
  int readers = 0;
  bool _disposed = false;
  bool _refreshing = false;
  bool offline = false;
  bool _initialized = false;
  Timer? _timer;

  bool get adminCandidate => adminIdentity.matches(accountId, phone);
  bool get activated => adminCandidate && _token != null;
  List<HubMessage> get visible => [
    for (final message in messages)
      if (!_hidden.contains(message.id)) message,
  ];
  int get unread => visible.where((message) => message.id > _seen).length;
  HubMessage? get banner {
    if (muted) return null;
    for (final message in visible.reversed) {
      if (message.id <= _seen) return null;
      if (message.meta.kind.urgent && !_bannerDismissed.contains(message.id)) {
        return message;
      }
    }
    return null;
  }

  int get seen => _seen;
  bool isUnread(HubMessage message) => message.id > _seen;
  String get _hiddenKey => 'promax_hub_hidden_$accountId';
  String get _mutedKey => 'promax_hub_muted_$accountId';
  String get _tokenKey => 'promax_hub_admin_$accountId';
  String get _cacheKey => 'promax_hub_messages_$accountId';
  String get _seenKey => 'promax_hub_seen_$accountId';

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _seen = prefs.getInt(_seenKey) ?? 0;
    muted = prefs.getBool(_mutedKey) ?? false;
    _hidden = {
      for (final id in prefs.getStringList(_hiddenKey) ?? const <String>[])
        ?int.tryParse(id),
    };
    try {
      final cached = jsonDecode(prefs.getString(_cacheKey) ?? '[]') as List;
      messages = [
        for (final value in cached)
          HubMessage.fromJson(value as Map<String, dynamic>),
      ];
    } catch (_) {
      messages = const [];
    }
    if (adminCandidate) {
      try {
        _token = await TokenStorage.readSecure(_tokenKey);
      } catch (_) {}
    }
    if (_disposed) return;
    _initialized = true;
    notifyListeners();
    AppForeground.notifier.addListener(_onForeground);
    _timer = Timer.periodic(const Duration(minutes: 1), (_) => _onForeground());
    await refresh();
  }

  void _onForeground() {
    if (AppForeground.value) unawaited(refresh());
  }

  Future<void> refresh() async {
    if (_disposed || !_initialized || _refreshing) return;
    _refreshing = true;
    final wasOffline = offline;
    var changed = false;
    try {
      final incoming = await client.messages(
        after: messages.isEmpty ? 0 : messages.last.id,
      );
      if (_disposed) return;
      offline = false;
      if (incoming.isEmpty) return;
      final byId = {
        for (final message in messages) message.id: message,
        for (final message in incoming) message.id: message,
      };
      final sorted = byId.values.toList()..sort((a, b) => a.id.compareTo(b.id));
      messages = List.unmodifiable(
        sorted.length > 500 ? sorted.sublist(sorted.length - 500) : sorted,
      );
      changed = true;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _cacheKey,
        jsonEncode(messages.map((message) => message.toJson()).toList()),
      );
    } catch (_) {
      offline = true;
    } finally {
      _refreshing = false;
      if (!_disposed && (changed || offline != wasOffline)) notifyListeners();
    }
  }

  Future<void> markRead() async {
    if (messages.isEmpty || _disposed || messages.last.id <= _seen) return;
    _seen = messages.last.id;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_seenKey, _seen);
    if (!_disposed) notifyListeners();
  }

  Future<void> hide(int id) async {
    _hidden = {..._hidden, id};
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_hiddenKey, [
      for (final value in _hidden) '$value',
    ]);
  }

  void dismissBanner(int id) {
    _bannerDismissed = {..._bannerDismissed, id};
    notifyListeners();
  }

  Future<void> setMuted(bool value) async {
    if (muted == value) return;
    muted = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_mutedKey, value);
  }

  Future<void> activate(String code) async {
    if (!adminCandidate) throw const HubException(403);
    await _checkActiveAccount();
    final token = await client.activate(code, accountId);
    await _checkActiveAccount();
    await TokenStorage.writeSecure(_tokenKey, token);
    await _checkActiveAccount();
    _token = token;
    notifyListeners();
    await refreshDraft();
  }

  String get _adminToken {
    if (!activated) throw const HubException(401);
    return _token!;
  }

  Future<void> _checkActiveAccount() async {
    final activeAccount = await TokenStorage.getActiveAccountId();
    if (_disposed || activeAccount != accountId) {
      throw const HubException(401);
    }
  }

  Future<T> _withAdmin<T>(Future<T> Function(String token) operation) async {
    await _checkActiveAccount();
    final token = _adminToken;
    late T result;
    try {
      result = await operation(token);
    } on HubException catch (error) {
      if ((error.status == 401 || error.status == 403) && _token == token) {
        _token = null;
        draft = null;
        await TokenStorage.deleteSecure(_tokenKey);
        if (!_disposed) notifyListeners();
      }
      rethrow;
    }
    await _checkActiveAccount();
    if (_token != token) throw const HubException(401);
    return result;
  }

  Future<void> refreshDraft() async {
    final next = await _withAdmin(client.draft);
    _acceptDraft(next);
  }

  void _acceptDraft(HubDraft next) {
    if (_disposed) return;
    final current = draft;
    if (current != null &&
        (next.revision < current.revision ||
            (next.revision == current.revision &&
                next.publishedRevision < current.publishedRevision))) {
      return;
    }
    draft = next;
    notifyListeners();
  }

  Future<void> saveDraft(String text, {HubMeta meta = HubMeta.plain}) async {
    await _checkActiveAccount();
    final value = text.trim();
    if (value.isEmpty || text.runes.length > 8000) {
      throw const HubException(422);
    }
    if (draft?.text == value && draft?.meta == meta) return;
    final revision = draft?.revision ?? 0;
    try {
      final next = await _withAdmin(
        (token) => client.saveDraft(token, value, revision, meta: meta),
      );
      _acceptDraft(next);
    } on HubException catch (error) {
      if (error.status == 409) await _refreshDraftAfterAction();
      rethrow;
    }
  }

  Future<void> _refreshDraftAfterAction() async {
    try {
      await refreshDraft();
    } catch (_) {}
  }

  Future<void> publish({int? revision}) async {
    final current = draft;
    if (current == null ||
        current.text.trim().isEmpty ||
        (revision != null && current.revision != revision)) {
      throw const HubException(409);
    }
    try {
      await _withAdmin((token) => client.publish(token, current.revision));
    } on HubException catch (error) {
      if (error.status == 409) await _refreshDraftAfterAction();
      rethrow;
    }
    _acceptDraft(
      HubDraft(
        text: current.text,
        revision: current.revision,
        publishedRevision: current.revision,
        meta: current.meta,
      ),
    );
    await _refreshDraftAfterAction();
    await refresh();
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    client.cancel();
    AppForeground.notifier.removeListener(_onForeground);
    super.dispose();
  }
}
