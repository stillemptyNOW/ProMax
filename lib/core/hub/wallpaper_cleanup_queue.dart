import 'dart:async';
import 'dart:convert';

import '../storage/token_storage.dart';
import 'hub_client.dart';

final _filePattern = RegExp(r'^[0-9a-f]{32}$');
final _tokenPattern = RegExp(r'^[A-Za-z0-9_-]{43}$');

abstract interface class WallpaperSecureStore {
  Future<List<String>> keys(String prefix);
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

class SystemWallpaperSecureStore implements WallpaperSecureStore {
  const SystemWallpaperSecureStore();

  @override
  Future<List<String>> keys(String prefix) =>
      TokenStorage.secureKeysWithPrefix(prefix);
  @override
  Future<String?> read(String key) => TokenStorage.readSecure(key);
  @override
  Future<void> write(String key, String value) =>
      TokenStorage.writeSecure(key, value);
  @override
  Future<void> delete(String key) => TokenStorage.deleteSecure(key);
}

class WallpaperCleanupResult {
  const WallpaperCleanupResult({required this.deleted, required this.pending});
  final int deleted;
  final int pending;
}

class WallpaperCleanupQueue {
  WallpaperCleanupQueue({
    HubClient? hub,
    WallpaperSecureStore store = const SystemWallpaperSecureStore(),
  }) : _hub = hub ?? HubClient(),
       _store = store;

  final HubClient _hub;
  final WallpaperSecureStore _store;
  final Map<int, Future<void>> _chains = {};
  bool _closed = false;

  String _prefix(int accountId) {
    if (accountId <= 0) throw ArgumentError.value(accountId, 'accountId');
    return 'promax_wallpaper_write_v1_${accountId}_';
  }

  String _storageKey(int accountId, String fileId) {
    if (!_filePattern.hasMatch(fileId)) {
      throw const FormatException('Invalid wallpaper id');
    }
    return '${_prefix(accountId)}$fileId';
  }

  Future<T> _serial<T>(int accountId, Future<T> Function() action) {
    _prefix(accountId);
    if (_closed) throw StateError('Wallpaper cleanup queue disposed');
    final before = _chains[accountId] ?? Future<void>.value();
    final operation = before.then((_) => action());
    final done = operation.then<void>((_) {}, onError: (_) {});
    _chains[accountId] = done;
    done.whenComplete(() {
      if (identical(_chains[accountId], done)) _chains.remove(accountId);
    });
    return operation;
  }

  Future<void> remember(int accountId, String fileId, String writeToken) =>
      _serial(accountId, () async {
        if (!_tokenPattern.hasMatch(writeToken)) {
          throw const FormatException('Invalid wallpaper capability');
        }
        final key = _storageKey(accountId, fileId);
        if (await _store.read(key) != null) {
          throw StateError('Wallpaper already registered');
        }
        await _store.write(
          key,
          jsonEncode({'token': writeToken, 'pending': false}),
        );
      });

  Future<void> requestDeletion(int accountId, String fileId) =>
      _serial(accountId, () async {
        final key = _storageKey(accountId, fileId);
        final record = await _read(key);
        if (record == null) throw StateError('Wallpaper not registered');
        await _store.write(
          key,
          jsonEncode({'token': record.token, 'pending': true}),
        );
      });

  Future<WallpaperCleanupResult> deleteAll(int accountId) =>
      _serial(accountId, () async {
        for (final key in await _store.keys(_prefix(accountId))) {
          final record = await _read(key);
          if (record == null) continue;
          await _store.write(
            key,
            jsonEncode({'token': record.token, 'pending': true}),
          );
        }
        return _retryLocked(accountId);
      });

  Future<WallpaperCleanupResult> retry(int accountId) =>
      _serial(accountId, () => _retryLocked(accountId));

  Future<({String token, bool pending})?> _read(String key) async {
    final raw = await _store.read(key);
    if (raw == null) return null;
    final dynamic value;
    try {
      value = jsonDecode(raw);
    } on FormatException {
      throw const FormatException('Invalid saved wallpaper capability');
    }
    if (value is! Map ||
        value['token'] is! String ||
        !_tokenPattern.hasMatch(value['token'] as String) ||
        value['pending'] is! bool) {
      throw const FormatException('Invalid saved wallpaper capability');
    }
    return (token: value['token'] as String, pending: value['pending'] as bool);
  }

  Future<WallpaperCleanupResult> _retryLocked(int accountId) async {
    var deleted = 0;
    var pending = 0;
    final prefix = _prefix(accountId);
    for (final key in await _store.keys(prefix)) {
      final fileId = key.substring(prefix.length);
      if (!_filePattern.hasMatch(fileId)) {
        throw const FormatException('Invalid saved wallpaper id');
      }
      final record = await _read(key);
      if (record == null || !record.pending) continue;
      try {
        final response = await _hub.request(
          '/v1/wallpapers/$fileId',
          method: 'DELETE',
          token: record.token,
        );
        if (response['deleted'] != true) {
          pending++;
          continue;
        }
      } catch (_) {
        pending++;
        continue;
      }
      await _store.delete(key);
      deleted++;
    }
    return WallpaperCleanupResult(deleted: deleted, pending: pending);
  }

  void dispose() {
    _closed = true;
    _hub.cancel();
  }
}
