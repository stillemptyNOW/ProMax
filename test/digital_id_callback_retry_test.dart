import 'package:flutter_test/flutter_test.dart';
import 'package:promax/backend/api.dart';
import 'package:promax/backend/modules/webapp.dart';
import 'package:promax/core/protocol/opcode_map.dart';
import 'package:promax/core/protocol/packet.dart';

class _CallbackApi extends Api {
  final requests = <(int, Map<dynamic, dynamic>)>[];

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
    return Packet(
      cmd: CmdType.ok,
      payload: opcode == Opcode.externalCallback
          ? {'botId': 101, 'startParam': 'synthetic-resume'}
          : {'url': 'https://example.test/launch/${requests.length}'},
    );
  }
}

void main() {
  test(
    'retry renews the Digital ID launch with the original context',
    () async {
      final api = _CallbackApi();
      addTearDown(api.dispose);
      final module = WebAppModule(api);

      final launch = await module.handleExternalCallback(
        'https://max.ru/?externalCallback=1&state=synthetic',
      );
      final renewed = await module.reloadDigitalIdLaunch(launch);

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
}
