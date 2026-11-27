import 'package:flutter_test/flutter_test.dart';
import 'package:promax/backend/api.dart';
import 'package:promax/backend/modules/webapp.dart';
import 'package:promax/core/protocol/opcode_map.dart';
import 'package:promax/core/protocol/packet.dart';
import 'package:promax/core/storage/token_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _CallbackApi extends Api {
  final requests = <(int, Map<dynamic, dynamic>)>[];
  bool failFirstLaunch = false;

  @override
  SessionState get state => SessionState.online;

  @override
  Future<Packet> sendRequest(
    int opcode,
    Map<dynamic, dynamic> payload, {
    bool silent = false,
    void Function()? beforeSend,
  }) async {
    requests.add((opcode, payload));
    if (opcode == Opcode.webAppInitData && failFirstLaunch) {
      failFirstLaunch = false;
      throw const PacketError('synthetic temporary launch failure');
    }
    return Packet(
      cmd: CmdType.ok,
      payload: opcode == Opcode.externalCallback
          ? {'botId': 101, 'startParam': 'synthetic-resume'}
          : {'url': 'https://example.test/launch/${requests.length}'},
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(
    () => SharedPreferences.setMockInitialValues({'active_account_id': '101'}),
  );

  test(
    'retry renews the Digital ID launch with the original context',
    () async {
      final api = _CallbackApi();
      addTearDown(api.dispose);
      final module = WebAppModule(api);

      final callback = module.digitalIdCallback(
        'https://max.ru/?externalCallback=1&state=synthetic',
      );
      await callback.launch();
      final renewed = await callback.launch();

      expect(renewed.url, 'https://example.test/launch/3');
      expect(api.requests.map((request) => request.$1), [
        Opcode.externalCallback,
        Opcode.webAppInitData,
        Opcode.webAppInitData,
      ]);
      expect(api.requests.last.$2, {
        'botId': 101,
        'startParam': 'synthetic-resume',
      });
    },
  );

  test(
    'retry after first launch failure reuses the accepted exchange',
    () async {
      final api = _CallbackApi()..failFirstLaunch = true;
      addTearDown(api.dispose);
      final callback = WebAppModule(
        api,
      ).digitalIdCallback('https://max.ru/?externalCallback=1&state=synthetic');

      await expectLater(callback.launch(), throwsA(isA<PacketError>()));
      final launch = await callback.launch();

      expect(launch.url, 'https://example.test/launch/3');
      expect(api.requests.last.$2['startParam'], 'synthetic-resume');
      expect(api.requests.map((request) => request.$1), [
        Opcode.externalCallback,
        Opcode.webAppInitData,
        Opcode.webAppInitData,
      ]);
    },
  );

  test(
    'an accepted exchange stays with the MAX account that started it',
    () async {
      final api = _CallbackApi()..failFirstLaunch = true;
      addTearDown(api.dispose);
      final callback = WebAppModule(
        api,
      ).digitalIdCallback('https://max.ru/?externalCallback=1&state=synthetic');
      await expectLater(callback.launch(), throwsA(isA<PacketError>()));

      await TokenStorage.setActiveAccount(202);
      await expectLater(callback.launch(), throwsA(isA<WebAppUnavailable>()));
      expect(api.requests.map((request) => request.$1), [
        Opcode.externalCallback,
        Opcode.webAppInitData,
      ]);
    },
  );
}
