import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:komet/backend/api.dart';
import 'package:komet/backend/modules/file_uploader.dart';
import 'package:komet/backend/modules/chats.dart';
import 'package:komet/backend/modules/messages.dart';
import 'package:komet/backend/modules/upload_service.dart';
import 'package:komet/core/protocol/opcode_map.dart';
import 'package:komet/core/protocol/packet.dart';
import 'package:komet/core/storage/app_database.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Paths extends PathProviderPlatform with MockPlatformInterfaceMixin {
  _Paths(this.path);
  final String path;
  @override
  Future<String?> getApplicationSupportPath() async => path;
}

class _Api extends Api {
  final requests = <(int, Map<dynamic, dynamic>)>[];
  bool rejectSend = false;

  @override
  Future<Packet> sendRequest(
    int opcode,
    Map<dynamic, dynamic> payload, {
    bool silent = false,
    void Function()? beforeSend,
  }) async {
    requests.add((opcode, payload));
    if (opcode == Opcode.videoUpload) {
      return Packet(
        cmd: CmdType.ok,
        payload: {
          'info': [
            {
              'url': 'https://media.example.invalid/upload',
              'videoId': 303,
              'token': 'synthetic-media-token',
            },
          ],
        },
      );
    }
    return Packet(
      cmd: rejectSend ? CmdType.error : CmdType.ok,
      payload: {
        'message': {
          'id': '404',
          'sender': 101,
          'time': 1000,
          ...payload['message'] as Map,
        },
      },
    );
  }
}

class _Uploader extends FileUploader {
  _Uploader(Api api, MessagesModule messages)
    : super(api: api, messages: messages);
  bool succeeds = true;
  final calls = <String>[];

  @override
  Future<bool> uploadVideoFile(
    Uri uri,
    File file, {
    void Function(int, int)? onProgress,
    int chunkSize = 2 * 1024 * 1024,
    int concurrency = 4,
    Duration overallTimeout = const Duration(minutes: 30),
  }) async {
    calls.add('video');
    expect(await file.exists(), true);
    onProgress?.call(4, 4);
    return succeeds;
  }

  @override
  Future<bool> uploadMediaFile(
    Uri uri,
    File file, {
    void Function(int, int)? onProgress,
    Duration overallTimeout = const Duration(minutes: 5),
    Duration progressThrottle = const Duration(milliseconds: 16),
  }) async {
    calls.add('media');
    return succeeds;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late _Api api;
  late _Uploader uploader;
  late UploadService service;
  late File file;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    directory = await Directory.systemTemp.createTemp(
      'synthetic_recording_upload',
    );
    final previous = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _Paths(directory.path);
    addTearDown(() => PathProviderPlatform.instance = previous);
    await AppDatabase.init();
    await AppDatabase.saveProfile(ProfileData.stub(101));
    await AppDatabase.saveChats([
      CachedChat(
        id: 202,
        accountId: 101,
        type: 'DIALOG',
        unreadCount: 0,
        lastEventTime: 0,
        cachedAt: 0,
        dontDisturbUntil: 0,
        isOnline: false,
        seenTime: 0,
        participants: const {101: 0, 303: 0},
      ).toDbRow(),
    ]);
    api = _Api();
    final messages = MessagesModule(api);
    uploader = _Uploader(api, messages);
    service = UploadService(messages: messages, uploader: uploader);
    file = await File(
      '${directory.path}/synthetic.mp4',
    ).writeAsBytes([1, 2, 3, 4]);
  });
  tearDown(() async {
    await service.dispose();
    await api.dispose();
    await AppDatabase.close();
    await directory.delete(recursive: true);
  });

  Future<void> sendNote() => service.sendVideoNote(
    accountId: 101,
    chatId: 202,
    tempId: 'synthetic-note',
    file: file,
    durationMs: 4000,
  );

  test(
    'circles use a video upload URL and the matching resumable transport',
    () async {
      final done = service.events.first;
      await sendNote();
      expect(await done, isA<UploadJobDone>());
      expect(uploader.calls, ['video']);
      expect(api.requests.first.$2, {'uploaderType': 0, 'type': 1, 'count': 1});
      final attach =
          (api.requests.last.$2['message']['attaches'] as List).single as Map;
      expect(attach['_type'], 'VIDEO');
      expect(attach['videoType'], 1);
      expect(attach['duration'], 4000);
      expect(attach['token'], 'synthetic-media-token');
      expect(await file.exists(), false);
    },
  );

  test(
    'a failed upload preserves the circle and never sends its empty token',
    () async {
      uploader.succeeds = false;
      final failed = service.events.first;
      await sendNote();
      expect((await failed as UploadJobFailed).reason, 'upload_failed');
      expect(api.requests.map((r) => r.$1), [Opcode.videoUpload]);
      expect(await file.readAsBytes(), [1, 2, 3, 4]);
    },
  );

  test('a rejected message preserves the uploaded circle', () async {
    api.rejectSend = true;
    final failed = service.events.first;
    await sendNote();
    expect((await failed as UploadJobFailed).reason, 'send_failed');
    expect(await file.exists(), true);
  });

  test(
    'voice messages keep their direct media transport and audio type',
    () async {
      final done = service.events.first;
      await service.sendVoice(
        accountId: 101,
        chatId: 202,
        tempId: 'synthetic-voice',
        file: file,
        durationMs: 4000,
        wave: Uint8List(80),
      );
      expect(await done, isA<UploadJobDone>());
      expect(uploader.calls, ['media']);
      expect(api.requests.first.$2, {'uploaderType': 1, 'type': 2, 'count': 1});
      expect(await file.exists(), false);
    },
  );
}
