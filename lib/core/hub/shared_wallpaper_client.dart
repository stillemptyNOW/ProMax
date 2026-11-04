import 'dart:convert';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:promax_crypto/promax_crypto.dart';

import 'hub_client.dart';
import 'wallpaper_cleanup_queue.dart';

const int _maxWallpaperBytes = 2 * 1024 * 1024;
const int _wallpaperChunkBytes = 24576;
final _wallpaperId = RegExp(r'^[0-9a-f]{32}$');
final _wallpaperToken = RegExp(r'^[A-Za-z0-9_-]{43}$');

class WallpaperReference {
  WallpaperReference({
    required this.id,
    required this.readToken,
    required Uint8List key,
    required this.expires,
  }) : key = Uint8List.fromList(key) {
    if (!_wallpaperId.hasMatch(id) ||
        !_wallpaperToken.hasMatch(readToken) ||
        key.length != ProMaxCryptoSizes.key ||
        expires <= 0) {
      throw const FormatException('Invalid wallpaper reference');
    }
  }

  final String id;
  final String readToken;
  final Uint8List key;
  final int expires;

  Map<String, Object> toControlPayload() => {
    'id': id,
    'read_token': readToken,
    'key': base64UrlEncode(key),
    'expires': expires,
  };

  factory WallpaperReference.fromControlPayload(Map<String, dynamic> value) {
    final id = value['id'];
    final token = value['read_token'];
    final key = value['key'];
    final expires = value['expires'];
    if (id is! String ||
        token is! String ||
        key is! String ||
        expires is! int) {
      throw const FormatException('Invalid wallpaper reference');
    }
    try {
      return WallpaperReference(
        id: id,
        readToken: token,
        key: base64Url.decode(key),
        expires: expires,
      );
    } on FormatException {
      throw const FormatException('Invalid wallpaper reference');
    }
  }

  void dispose() => ProMaxCrypto.wipe(key);
}

class UploadedWallpaper {
  const UploadedWallpaper({required this.reference, required this.writeToken});
  final WallpaperReference reference;
  final String writeToken;
}

abstract interface class WallpaperCipher {
  Uint8List newKey();
  Future<Uint8List> encrypt(Uint8List plaintext, Uint8List key);
  Future<Uint8List> decrypt(Uint8List ciphertext, Uint8List key);
}

class NativeWallpaperCipher implements WallpaperCipher {
  const NativeWallpaperCipher();

  @override
  Uint8List newKey() => ProMaxCrypto.randomBytes(ProMaxCryptoSizes.key);

  @override
  Future<Uint8List> encrypt(Uint8List plaintext, Uint8List key) {
    final library = ProMaxCrypto.libraryPath;
    return Isolate.run(() {
      ProMaxCrypto.libraryPath = library;
      return ProMaxCrypto.encryptImageBlob(plaintext, key);
    });
  }

  @override
  Future<Uint8List> decrypt(Uint8List ciphertext, Uint8List key) {
    final library = ProMaxCrypto.libraryPath;
    return Isolate.run(() {
      ProMaxCrypto.libraryPath = library;
      return ProMaxCrypto.decryptImageBlob(ciphertext, key);
    });
  }
}

class SharedWallpaperClient {
  SharedWallpaperClient({
    HubClient? hub,
    required WallpaperCleanupQueue cleanupQueue,
    WallpaperCipher cipher = const NativeWallpaperCipher(),
    Future<void> Function(Duration)? delay,
  }) : _hub = hub ?? HubClient(),
       _cleanupQueue = cleanupQueue,
       _cipher = cipher,
       _delay = delay ?? Future<void>.delayed;

  final HubClient _hub;
  final WallpaperCleanupQueue _cleanupQueue;
  final WallpaperCipher _cipher;
  final Future<void> Function(Duration) _delay;
  bool _closed = false;

  void dispose() {
    _closed = true;
    _hub.cancel();
  }

  void _requireConsent(bool Function() hasConsent) {
    if (_closed) throw StateError('Wallpaper client disposed');
    if (!hasConsent()) throw StateError('Wallpaper sharing requires consent');
  }

  Future<UploadedWallpaper> upload(
    Uint8List image, {
    required int accountId,
    required bool Function() hasConsent,
  }) async {
    _requireConsent(hasConsent);
    if (accountId <= 0) throw ArgumentError.value(accountId, 'accountId');
    if (image.isEmpty || image.length > _maxWallpaperBytes) {
      throw const FormatException('Invalid wallpaper size');
    }
    final key = _cipher.newKey();
    String? id;
    String? writeToken;
    WallpaperReference? reference;
    var registered = false;
    try {
      final ciphertext = await _cipher.encrypt(image, key);
      _requireConsent(hasConsent);
      if (ciphertext.isEmpty || ciphertext.length > _maxWallpaperBytes) {
        throw const FormatException('Invalid encrypted wallpaper size');
      }
      final created = await _hub.request(
        '/v1/wallpapers',
        method: 'POST',
        body: {'size': ciphertext.length},
      );
      final rawId = created['id'];
      final rawReadToken = created['read_token'];
      final rawWriteToken = created['write_token'];
      final chunkSize = created['chunk_size'];
      final expires = created['expires'];
      if (rawId is! String ||
          !_wallpaperId.hasMatch(rawId) ||
          rawReadToken is! String ||
          rawWriteToken is! String ||
          !_wallpaperToken.hasMatch(rawWriteToken) ||
          chunkSize != _wallpaperChunkBytes ||
          expires is! int) {
        throw const FormatException('Invalid wallpaper upload response');
      }
      id = rawId;
      writeToken = rawWriteToken;
      reference = WallpaperReference(
        id: rawId,
        readToken: rawReadToken,
        key: key,
        expires: expires,
      );
      if (expires <= DateTime.now().millisecondsSinceEpoch ~/ 1000) {
        throw const FormatException('Expired wallpaper upload');
      }
      await _cleanupQueue.remember(accountId, id, writeToken);
      registered = true;
      for (
        var offset = 0, number = 0;
        offset < ciphertext.length;
        offset += _wallpaperChunkBytes, number++
      ) {
        _requireConsent(hasConsent);
        final end = (offset + _wallpaperChunkBytes).clamp(0, ciphertext.length);
        await _hub.request(
          '/v1/wallpapers/$id/$number',
          method: 'PUT',
          token: writeToken,
          body: {
            'data': base64Encode(
              Uint8List.sublistView(ciphertext, offset, end),
            ),
          },
        );
        if (end < ciphertext.length) {
          await _delay(const Duration(milliseconds: 220));
        }
      }
      _requireConsent(hasConsent);
      return UploadedWallpaper(reference: reference, writeToken: writeToken);
    } catch (_) {
      reference?.dispose();
      if (id != null && writeToken != null) {
        if (registered) {
          try {
            await _cleanupQueue.requestDeletion(accountId, id);
            await _cleanupQueue.retry(accountId);
          } catch (_) {}
        } else if (!_closed) {
          try {
            await _hub.request(
              '/v1/wallpapers/$id',
              method: 'DELETE',
              token: writeToken,
            );
          } catch (_) {}
        }
      }
      rethrow;
    } finally {
      ProMaxCrypto.wipe(key);
    }
  }

  Future<Uint8List> download(
    WallpaperReference reference, {
    required bool Function() hasConsent,
  }) async {
    _requireConsent(hasConsent);
    if (reference.expires <= DateTime.now().millisecondsSinceEpoch ~/ 1000) {
      throw const FormatException('Wallpaper expired');
    }
    final path = '/v1/wallpapers/${reference.id}';
    final info = await _hub.request(path, token: reference.readToken);
    final size = info['size'];
    if (size is! int ||
        size <= 0 ||
        size > _maxWallpaperBytes ||
        info['chunk_size'] != _wallpaperChunkBytes ||
        info['expires'] != reference.expires) {
      throw const FormatException('Invalid wallpaper metadata');
    }
    final data = BytesBuilder(copy: false);
    for (
      var offset = 0, number = 0;
      offset < size;
      offset += _wallpaperChunkBytes, number++
    ) {
      _requireConsent(hasConsent);
      if (number > 0) await _delay(const Duration(milliseconds: 220));
      _requireConsent(hasConsent);
      final response = await _hub.request(
        '$path/$number',
        token: reference.readToken,
      );
      if (response['data'] is! String) {
        throw const FormatException('Invalid wallpaper chunk');
      }
      final chunk = base64Decode(response['data'] as String);
      final expected = (size - offset).clamp(0, _wallpaperChunkBytes);
      if (chunk.length != expected) {
        throw const FormatException('Invalid wallpaper chunk');
      }
      data.add(chunk);
    }
    _requireConsent(hasConsent);
    final image = await _cipher.decrypt(data.takeBytes(), reference.key);
    _requireConsent(hasConsent);
    if (image.isEmpty || image.length > _maxWallpaperBytes) {
      throw const FormatException('Invalid wallpaper image');
    }
    return image;
  }

  Future<WallpaperCleanupResult> delete(
    int accountId,
    UploadedWallpaper wallpaper,
  ) async {
    if (_closed) throw StateError('Wallpaper client disposed');
    await _cleanupQueue.requestDeletion(accountId, wallpaper.reference.id);
    return _cleanupQueue.retry(accountId);
  }
}
