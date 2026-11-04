import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:promax/core/hub/hub_client.dart';
import 'package:promax/core/hub/shared_wallpaper_client.dart';
import 'package:promax/core/hub/wallpaper_cleanup_queue.dart';

class FixtureSecureStore implements WallpaperSecureStore {
  final values = <String, String>{};

  @override
  Future<List<String>> keys(String prefix) async =>
      values.keys.where((key) => key.startsWith(prefix)).toList();
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    values.remove(key);
  }
}

class FixtureCipher implements WallpaperCipher {
  final Uint8List key = Uint8List.fromList(List.filled(32, 7));
  final Uint8List plaintext = Uint8List.fromList([1, 2, 3]);
  final Uint8List ciphertext = Uint8List.fromList(List.filled(25000, 9));

  @override
  Uint8List newKey() => Uint8List.fromList(key);

  @override
  Future<Uint8List> encrypt(Uint8List image, Uint8List key) async {
    expect(image, plaintext);
    expect(key, this.key);
    return ciphertext;
  }

  @override
  Future<Uint8List> decrypt(Uint8List blob, Uint8List key) async {
    expect(blob, ciphertext);
    expect(key, this.key);
    return plaintext;
  }
}

void main() {
  const id = '0123456789abcdef0123456789abcdef';
  final read = 'r' * 43;
  final write = 'w' * 43;
  final expires = DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600;
  late FixtureCipher cipher;
  late List<http.Request> requests;
  late List<Uint8List> chunks;
  late SharedWallpaperClient client;
  late bool consent;
  late bool revokeOnUpload;
  late bool failDelete;
  late FixtureSecureStore store;
  late WallpaperCleanupQueue cleanupQueue;

  setUp(() {
    cipher = FixtureCipher();
    consent = true;
    revokeOnUpload = false;
    failDelete = false;
    store = FixtureSecureStore();
    requests = [];
    chunks = [];
    Future<http.Response> respond(http.Request request) async {
      requests.add(request);
      final path = request.url.path;
      if (request.method == 'POST') {
        expect(jsonDecode(request.body)['size'], cipher.ciphertext.length);
        return http.Response(
          jsonEncode({
            'id': id,
            'read_token': read,
            'write_token': write,
            'chunk_size': 24576,
            'expires': expires,
          }),
          201,
        );
      }
      if (request.method == 'PUT') {
        if (revokeOnUpload) consent = false;
        expect(request.headers['Authorization'], 'Bearer $write');
        chunks.add(base64Decode(jsonDecode(request.body)['data'] as String));
        return http.Response('{}', 200);
      }
      if (request.method == 'DELETE') {
        return failDelete
            ? http.Response('{}', 503)
            : http.Response('{"deleted":true}', 200);
      }
      expect(request.headers['Authorization'], 'Bearer $read');
      if (path == '/v1/wallpapers/$id') {
        return http.Response(
          jsonEncode({
            'size': cipher.ciphertext.length,
            'chunk_size': 24576,
            'expires': expires,
          }),
          200,
        );
      }
      final index = int.parse(path.split('/').last);
      return http.Response(
        jsonEncode({'data': base64Encode(chunks[index])}),
        200,
      );
    }

    HubClient hub() => HubClient(
      baseUri: Uri.parse('https://example.invalid'),
      createClient: () => MockClient(respond),
    );
    cleanupQueue = WallpaperCleanupQueue(hub: hub(), store: store);
    client = SharedWallpaperClient(
      cipher: cipher,
      delay: (_) async {},
      hub: hub(),
      cleanupQueue: cleanupQueue,
    );
  });

  tearDown(() {
    client.dispose();
    cleanupQueue.dispose();
  });

  test('requires explicit consent before any network operation', () async {
    await expectLater(
      client.upload(cipher.plaintext, accountId: 1, hasConsent: () => false),
      throwsStateError,
    );
    expect(requests, isEmpty);
  });

  test(
    'retains deletion capability after network failure and retries',
    () async {
      final uploaded = await client.upload(
        cipher.plaintext,
        accountId: 1,
        hasConsent: () => true,
      );
      failDelete = true;
      final first = await client.delete(1, uploaded);
      expect(first.pending, 1);
      expect(store.values, isNotEmpty);
      failDelete = false;
      final second = await cleanupQueue.retry(1);
      expect(second.deleted, 1);
      expect(second.pending, 0);
      expect(store.values, isEmpty);
      uploaded.reference.dispose();
    },
  );

  test(
    'uploads ciphertext in chunks and downloads with separate capability',
    () async {
      final uploaded = await client.upload(
        cipher.plaintext,
        accountId: 1,
        hasConsent: () => true,
      );
      expect(chunks.length, 2);
      expect(chunks.expand((part) => part).toList(), cipher.ciphertext);
      final restored = WallpaperReference.fromControlPayload(
        uploaded.reference.toControlPayload(),
      );
      expect(
        await client.download(restored, hasConsent: () => true),
        cipher.plaintext,
      );
      await client.delete(1, uploaded);
      expect(requests.last.headers['Authorization'], 'Bearer $write');
      uploaded.reference.dispose();
      expect(uploaded.reference.key, everyElement(0));
      restored.dispose();
    },
  );

  test(
    'revocation stops further upload and removes the partial file',
    () async {
      revokeOnUpload = true;
      await expectLater(
        client.upload(
          cipher.plaintext,
          accountId: 1,
          hasConsent: () => consent,
        ),
        throwsStateError,
      );
      expect(chunks.length, 1);
      expect(requests.last.method, 'DELETE');
      expect(requests.last.headers['Authorization'], 'Bearer $write');
    },
  );

  test('rejects malformed and expired references before downloading', () async {
    expect(
      () => WallpaperReference(
        id: '../bad',
        readToken: read,
        key: cipher.key,
        expires: expires,
      ),
      throwsFormatException,
    );
    final reference = WallpaperReference(
      id: id,
      readToken: read,
      key: cipher.key,
      expires: 1,
    );
    await expectLater(
      client.download(reference, hasConsent: () => true),
      throwsFormatException,
    );
    expect(requests, isEmpty);
    reference.dispose();
  });
}
