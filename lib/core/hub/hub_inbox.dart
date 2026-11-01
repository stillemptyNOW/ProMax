import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import '../storage/token_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/app_foreground.dart';
import 'hub_client.dart';

class HubInbox extends ChangeNotifier {
  HubInbox({required this.accountId, required this.phone, HubClient? client})
    : client = client ?? HubClient();

  static const adminPhone = 79920854267;
  final int accountId;
  final int phone;
  final HubClient client;
  List<HubMessage> messages = const [];
  HubDraft? draft;
  String? _token;
  int _seen = 0;
  int readers = 0;
  bool _disposed = false;
  bool _refreshing = false;
  bool offline = false;
  bool _initialized = false;
  Timer? _timer;

  bool get adminCandidate => phone == adminPhone;
  bool get activated => adminCandidate && _token != null;
  int get unread => messages.where((message) => message.id > _seen).length;
  String get _tokenKey => 'promax_hub_admin_$accountId';
  String get _cacheKey => 'promax_hub_messages_$accountId';
  String get _seenKey => 'promax_hub_seen_$accountId';

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _seen = prefs.getInt(_seenKey) ?? 0;
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
    try {
      final incoming = await client.messages();
      if (_disposed) return;
      final byId = {
        for (final message in messages) message.id: message,
        for (final message in incoming) message.id: message,
      };
      final sorted = byId.values.toList()..sort((a, b) => a.id.compareTo(b.id));
      messages = List.unmodifiable(
        sorted.length > 500 ? sorted.sublist(sorted.length - 500) : sorted,
      );
      offline = false;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _cacheKey,
        jsonEncode(messages.map((message) => message.toJson()).toList()),
      );
    } catch (_) {
      offline = true;
    } finally {
      _refreshing = false;
      if (!_disposed) notifyListeners();
    }
  }

  Future<void> markRead() async {
    if (messages.isEmpty || _disposed || messages.last.id <= _seen) return;
    _seen = messages.last.id;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_seenKey, _seen);
    if (!_disposed) notifyListeners();
  }

  Future<void> activate(String code) async {
    if (!adminCandidate) throw const HubException(403);
    final token = await client.activate(code, accountId);
    await TokenStorage.writeSecure(_tokenKey, token);
    if (_disposed) return;
    _token = token;
    await refreshDraft();
  }

  String get _adminToken {
    if (!activated) throw const HubException(401);
    return _token!;
  }

  Future<T> _withAdmin<T>(Future<T> Function(String token) operation) async {
    if (await TokenStorage.getActiveAccountId() != accountId) {
      throw const HubException(401);
    }
    try {
      return await operation(_adminToken);
    } on HubException catch (error) {
      if (error.status == 401 || error.status == 403) {
        _token = null;
        draft = null;
        await TokenStorage.deleteSecure(_tokenKey);
        if (!_disposed) notifyListeners();
      }
      rethrow;
    }
  }

  Future<void> refreshDraft() async {
    final next = await _withAdmin(client.draft);
    if (_disposed) return;
    draft = next;
    notifyListeners();
  }

  Future<void> saveDraft(String text) async {
    final next = await _withAdmin(
      (token) => client.saveDraft(token, text, draft?.revision ?? 0),
    );
    if (_disposed) return;
    draft = next;
    notifyListeners();
  }

  Future<void> publish() async {
    final current = draft;
    if (current == null || current.text.trim().isEmpty) {
      throw const HubException(409);
    }
    await _withAdmin((token) => client.publish(token, current.revision));
    await refreshDraft();
    await refresh();
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    AppForeground.notifier.removeListener(_onForeground);
    super.dispose();
  }
}
