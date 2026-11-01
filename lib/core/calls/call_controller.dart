import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../backend/api.dart';
import '../../backend/modules/calls.dart';
import '../config/build_profile.dart';
import '../protocol/opcode_map.dart';
import '../push/fkm_controller.dart';
import '../protocol/packet.dart';
import '../utils/app_foreground.dart';
import '../utils/logger.dart';
import '../utils/parse.dart';
import 'call_bridge.dart';
import 'call_kit.dart';
import 'call_session.dart';
import 'conversation_params.dart';
import 'ws2_signaling.dart';

// #***! входящий из пуша или с нативного экрана
class IncomingCall {
  final String conversationId;

  final int callerId;
  final bool isVideo;
  final ConversationParams params;

  final String? country;
  final bool? isContact;
  final String? callerName;

  final bool autoAccept;

  const IncomingCall({
    required this.conversationId,
    required this.callerId,
    required this.isVideo,
    required this.params,
    this.country,
    this.isContact,
    this.callerName,
    this.autoAccept = false,
  });

  static IncomingCall? fromNative(
    Map<dynamic, dynamic> data, {
    bool autoAccept = false,
  }) {
    final vcp = data['vcp']?.toString();
    if (vcp == null || vcp.isEmpty) return null;

    final conversationId = (data['conversationId'] ?? data['vcId'])?.toString();
    if (conversationId == null || conversationId.isEmpty) return null;

    final callerId = parseIntOrNull(data['callerId'] ?? data['suid']);
    if (callerId == null) return null;

    final params = ConversationParams.decode(vcp);
    if (params == null) return null;

    final type = (data['type'] ?? data['callType'])?.toString();
    final iv = data['iv'];
    final isVideo =
        params.isVideo || type == 'VIDEO' || iv == true || iv == 'true';

    return IncomingCall(
      conversationId: conversationId,
      callerId: callerId,
      isVideo: isVideo,
      params: params,
      country: data['country']?.toString(),
      isContact: data['isContact'] is bool ? data['isContact'] as bool : null,
      callerName: data['userName']?.toString(),
      autoAccept: autoAccept,
    );
  }
}

class AnsweredCall {
  const AnsweredCall({required this.call, required this.session});

  final IncomingCall call;
  final CallSession session;
}

class IncomingDecision {
  const IncomingDecision({required this.call, required this.accept});

  final IncomingCall call;
  final bool accept;
}

// #***! управление звонками поверх сессии
class CallController {
  CallController._();
  static final CallController instance = CallController._();

  Api? _api;
  CallsModule? _calls;
  StreamSubscription<Packet>? _pushSub;

  // #***! стримы наружу
  final _incoming = StreamController<IncomingCall>.broadcast();
  final _ended = StreamController<void>.broadcast();
  final _canceled = StreamController<void>.broadcast();
  final _answered = StreamController<AnsweredCall>.broadcast();
  final _decisions = StreamController<IncomingDecision>.broadcast();

  static const ringTimeout = Duration(seconds: 60);
  Timer? _ringTimer;

  bool get _desktop {
    if (kIsWeb) return false;
    return defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.linux ||
        defaultTargetPlatform == TargetPlatform.macOS;
  }

  // #***! приложение в фоне, звонок показывает натив а не мы
  bool appResumed = false;

  @visibleForTesting
  static bool systemShowsIncoming({
    required bool resumed,
    required bool visible,
    required bool desktop,
    required bool backgroundNotifications,
    required bool firebasePush,
  }) {
    if (resumed || desktop) return false;
    return backgroundNotifications || firebasePush || !visible;
  }

  Stream<IncomingCall> get incomingCalls => _incoming.stream;

  Stream<void> get callEnded => _ended.stream;

  Stream<void> get incomingCanceled => _canceled.stream;

  Stream<AnsweredCall> get answeredCalls => _answered.stream;

  Stream<IncomingDecision> get incomingDecisions => _decisions.stream;

  CallSession? _active;
  StreamSubscription<CallSessionState>? _activeSub;
  CallSession? get activeSession => _active;

  String? _activeJoinLink;
  String? get activeJoinLink => _active == null ? null : _activeJoinLink;

  IncomingCall? _pending;
  IncomingCall? get pendingIncoming => _pending;

  bool _starting = false;

  // #***! занято, второй звонок не берём
  bool get isBusy => _active != null || _starting;

  // #***! подписка на пуши звонков
  void init(Api api) {
    if (_api != null) return;
    _api = api;
    _calls = CallsModule(api);
    _pushSub = api.pushStream.listen(_onPush);
  }

  // #***! разбор пуша входящего
  void _onPush(Packet packet) {
    if (packet.opcode == Opcode.notifMessage) {
      _onCallRecord(packet.payload);
      return;
    }
    if (packet.opcode != Opcode.notifCallStart) return;
    final payload = packet.payload;
    if (payload is! Map) return;

    final vcp = payload['vcp'] as String?;
    final conversationId = payload['conversationId'] as String?;
    final callerId = payload['callerId'] as int?;
    if (vcp == null || conversationId == null || callerId == null) return;
    _screenIncoming(
      payload,
      vcp: vcp,
      conversationId: conversationId,
      callerId: callerId,
    );
  }

  void _screenIncoming(
    Map<dynamic, dynamic> payload, {
    required String vcp,
    required String conversationId,
    required int callerId,
  }) {
    if (systemShowsIncoming(
      resumed: appResumed,
      visible: AppForeground.value,
      desktop: _desktop,
      backgroundNotifications: FkmController.instance.enabled.value,
      firebasePush: BuildProfile.firebasePush,
    )) {
      unawaited(FkmController.instance.showIncomingCall(payload));
      return;
    }

    if (CallKitBridge.instance.owns(conversationId)) return;

    final params = ConversationParams.decode(vcp);
    if (params == null) return;

    _emitIncoming(
      IncomingCall(
        conversationId: conversationId,
        callerId: callerId,
        isVideo: payload['type'] == 'VIDEO' || params.isVideo,
        params: params,
        country: payload['country'] as String?,
        isContact: payload['isContact'] as bool?,
      ),
    );
  }

  void _onCallRecord(Object? payload) {
    final record = FinishedCallRecord.fromPush(payload);
    if (record == null) return;
    CallKitBridge.instance.finishRinging(record);
    if (_pending?.conversationId == record.conversationId) dismissIncoming();
  }

  // #***! звонок с натива, autoAccept значит там уже нажали принять
  void injectFromNative(Map<dynamic, dynamic> data, {bool autoAccept = false}) {
    final call = IncomingCall.fromNative(data, autoAccept: autoAccept);
    if (call != null) _emitIncoming(call);
  }

  CallSession? answerFromSystem(Map<dynamic, dynamic> data) {
    if (isBusy) return null;
    final call = IncomingCall.fromNative(data);
    if (call == null) return null;
    if (_pending != null && _pending!.conversationId != call.conversationId) {
      dismissIncoming();
    }
    final session = _calleeSession(call);
    unawaited(
      _launchCallee(session, call).then<void>(
        (_) {},
        onError: (Object e) => logger.w('CallController.answerFromSystem: $e'),
      ),
    );
    _answered.add(AnsweredCall(call: call, session: session));
    return session;
  }

  // #***! входящий наружу, юишка решит что показать
  void _emitIncoming(IncomingCall incoming) {
    if (isBusy) return;
    if (_pending?.conversationId == incoming.conversationId) return;
    _pending = incoming;
    _ringTimer?.cancel();
    if (_desktop) {
      _ringTimer = Timer(ringTimeout, () {
        if (identical(_pending, incoming)) dismissIncoming();
      });
    }
    _incoming.add(incoming);
  }

  void dismissIncoming() {
    if (_pending == null) return;
    _pending = null;
    _ringTimer?.cancel();
    _canceled.add(null);
  }

  void decideIncoming(String conversationId, {required bool accept}) {
    final call = _pending;
    if (call == null || call.conversationId != conversationId) return;
    if (_decisions.hasListener) {
      _decisions.add(IncomingDecision(call: call, accept: accept));
      return;
    }
    if (accept) return;
    unawaited(rejectIncoming(call));
    _canceled.add(null);
  }

  // #***! исходящий звонок
  Future<CallSession> startOutgoing(int calleeId, {bool isVideo = false}) =>
      _startExclusive(() async {
        final out = await _calls!.initiateCall(calleeId, isVideo: isVideo);
        final config = Ws2Config.fromEndpoint(
          out.endpoint,
          userId: out.callsUserId,
          device: _api?.callsDevice,
          osVersion: _api?.callsOsVersion,
        );
        final session = CallSession(ws2Config: config, role: CallRole.caller);
        return _launch(session, session.start);
      });

  // #***! конференция со ссылкой
  Future<CreatedCall> createConference() async {
    if (isBusy) throw StateError('уже идёт звонок');
    return _calls!.createConference();
  }

  Future<CallLinkPreview?> previewCallLink(String url) =>
      _calls!.resolveCallLink(url);

  // #***! вход по ссылке
  Future<CallSession> joinByLink(String token, {bool isVideo = false}) =>
      _startExclusive(() async {
        final params = await _calls!.joinByLink(token, isVideo: isVideo);
        final config = Ws2Config.fromEndpoint(
          params.endpoint,
          userId: params.callsUserId,
          device: _api?.callsDevice,
          osVersion: _api?.callsOsVersion,
        );
        final session = CallSession(
          ws2Config: config,
          role: CallRole.joiner,
          isGroup: true,
        );
        _activeJoinLink = token;
        return _launch(session, session.start);
      });

  Future<CallSession> _startExclusive(
    Future<CallSession> Function() start,
  ) async {
    if (isBusy) throw StateError('уже идёт звонок');
    _starting = true;
    try {
      return await start();
    } finally {
      _starting = false;
    }
  }

  // #***! принятие входящего
  Future<CallSession> acceptIncoming(IncomingCall call) =>
      _launchCallee(_calleeSession(call), call);

  CallSession _calleeSession(IncomingCall call) {
    _pending = null;
    _ringTimer?.cancel();
    CallBridge.instance.cancelIncoming();
    final config = Ws2Config.fromVcp(
      call.params,
      conversationId: call.conversationId,
      device: _api?.callsDevice,
      osVersion: _api?.callsOsVersion,
    );
    return CallSession(
      ws2Config: config,
      params: call.params,
      role: CallRole.callee,
    );
  }

  Future<CallSession> _launchCallee(CallSession session, IncomingCall call) =>
      _launch(session, () async {
        await session.start();
        await session.accept();
      }, caller: call.callerName);

  Future<void> rejectFromSystem(Map<dynamic, dynamic> data) async {
    final call = IncomingCall.fromNative(data);
    if (call != null) await rejectIncoming(call);
  }

  // #***! отклонение
  Future<void> rejectIncoming(IncomingCall call) async {
    _pending = null;
    _ringTimer?.cancel();
    CallBridge.instance.notifyEnded();
    final config = Ws2Config.fromVcp(
      call.params,
      conversationId: call.conversationId,
      device: _api?.callsDevice,
      osVersion: _api?.callsOsVersion,
    );
    final signaling = Ws2Signaling(config);
    try {
      await signaling.connect();
      await signaling.hangup(reason: 'REJECTED');
    } catch (_) {
    } finally {
      await signaling.close();
    }
  }

  Future<void> endActive() => _active?.hangup() ?? Future.value();

  // #***! сигналим собеседнику про микрофон
  Future<bool> sendMicSignal(bool enabled) async {
    final session = _active;
    if (session == null) return false;
    await session.sendAudioEnabledSignal(enabled);
    return true;
  }

  // #***! общий запуск сессии
  Future<CallSession> _launch(
    CallSession session,
    Future<void> Function() open, {
    String? caller,
  }) async {
    _bind(session);
    try {
      await open();
    } catch (_) {
      await _release(session);
      try {
        await session.abort();
      } catch (_) {}
      rethrow;
    }
    CallBridge.instance.notifyAccepted(caller: caller);
    return session;
  }

  // #***! следим за состоянием, конец сессии освобождает контроллер
  void _bind(CallSession session) {
    unawaited(_activeSub?.cancel());
    _active = session;
    unawaited(CallKitBridge.instance.setAppCallActive(true));
    _activeSub = session.stateStream.listen((state) {
      if (state != CallSessionState.ended) return;
      unawaited(_release(session));
    });
  }

  Future<void> _release(CallSession session) async {
    if (!identical(_active, session)) return;
    _active = null;
    _activeJoinLink = null;
    await _activeSub?.cancel();
    _activeSub = null;
    CallBridge.instance.notifyEnded();
    _ended.add(null);
    unawaited(
      session.closed.whenComplete(
        () => CallKitBridge.instance.setAppCallActive(_active != null),
      ),
    );
  }

  void dispose() {
    _ringTimer?.cancel();
    _activeSub?.cancel();
    _pushSub?.cancel();
    _decisions.close();
    _incoming.close();
    _ended.close();
    _canceled.close();
    _answered.close();
  }
}
