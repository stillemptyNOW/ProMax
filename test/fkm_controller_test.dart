import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promax/backend/api.dart';
import 'package:promax/core/push/fkm_bridge.dart';
import 'package:promax/core/push/fkm_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _channel = MethodChannel('io.github.stillemptynow.promax/fkm');
const _localNotifications = MethodChannel(
  'dexterous.com/flutter/local_notifications',
);

TestDefaultBinaryMessenger get _messenger =>
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

Future<void> _fromNative(String method) async {
  await _messenger.handlePlatformMessage(
    _channel.name,
    _channel.codec.encodeMethodCall(MethodCall(method)),
    (_) {},
  );
  await pumpEventQueue();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    AndroidFlutterLocalNotificationsPlugin.registerWith();
    _messenger.setMockMethodCallHandler(
      _localNotifications,
      (call) async => call.method == 'initialize' ? true : null,
    );
  });

  tearDownAll(
    () => _messenger.setMockMethodCallHandler(_localNotifications, null),
  );

  late List<MethodCall> calls;
  late bool nativeEnabled;
  late Api api;
  late FkmController controller;

  void nativeReady() {
    _messenger.setMockMethodCallHandler(_channel, (call) async {
      calls.add(call);
      return call.method == 'isEnabled' ? nativeEnabled : null;
    });
  }

  List<String> methods() => [for (final call in calls) call.method];

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    calls = [];
    nativeEnabled = true;
    api = Api();
    controller = FkmController.withBridge(
      FkmBridge.forTesting(isSupported: true),
    );
  });

  tearDown(() async {
    controller.dispose();
    await api.dispose();
    Api.keepAliveInBackground = false;
    _messenger.setMockMethodCallHandler(_channel, null);
  });

  test(
    'включённый в нативе FKM держит сервис и сообщает, что связи ещё нет',
    () async {
      nativeReady();

      await controller.init(api);

      expect(controller.enabled.value, isTrue);
      expect(Api.keepAliveInBackground, isTrue);
      expect(methods(), ['isEnabled', 'setEnabled', 'setConnected']);
      expect(calls[1].arguments, {'enabled': true});
      expect(calls[2].arguments, {'connected': false});
    },
  );

  test('выключенный в нативе FKM не поднимает сервис', () async {
    nativeEnabled = false;
    nativeReady();

    await controller.init(api);

    expect(controller.enabled.value, isFalse);
    expect(Api.keepAliveInBackground, isFalse);
    expect(methods(), ['isEnabled']);
  });

  test(
    'канал, подключённый к уже запущенному движку, заново включает FKM',
    () async {
      await controller.init(api);
      expect(controller.enabled.value, isFalse);
      expect(Api.keepAliveInBackground, isFalse);

      nativeReady();
      await _fromNative('attached');

      expect(controller.enabled.value, isTrue);
      expect(Api.keepAliveInBackground, isTrue);
      expect(methods(), ['isEnabled', 'setEnabled', 'setConnected']);
    },
  );

  test('кнопка «Выключить» в уведомлении гасит FKM', () async {
    nativeReady();
    await controller.init(api);

    await _fromNative('disabled');

    expect(controller.enabled.value, isFalse);
    expect(Api.keepAliveInBackground, isFalse);
  });

  test('без поддержки платформы канал не трогается', () async {
    nativeReady();
    final unsupported = FkmController.withBridge(
      FkmBridge.forTesting(isSupported: false),
    );

    await unsupported.init(api);

    expect(unsupported.enabled.value, isFalse);
    expect(calls, isEmpty);
  });
}
