import 'dart:async';
import 'dart:collection';
import 'dart:io' show Platform;

import 'package:flutter/services.dart';

import '../utils/ids.dart';
import '../utils/logger.dart';
import 'call_controller.dart';
import 'call_session.dart';

const _callKitNamespace = '3f6c2b1e-8d4a-4c7e-9b52-61a0f7d3e9c4';

String callKitUuid(String conversationId) =>
    uuidV5(_callKitNamespace, conversationId);

enum CallKitEndReason {
  local,
  remoteEnded,
  unanswered,
  declinedElsewhere,
  answeredElsewhere,
  failed,
}

enum CallKitAction { answer, decline, hangup, mute, hold, timeout, reset }

class CallKitIncoming {
  const CallKitIncoming({
    required this.conversationId,
    required this.handle,
    required this.callerName,
    required this.isVideo,
    required this.data,
  });

  final String conversationId;
  final String handle;
  final String callerName;
  final bool isVideo;
  final Map<String, String> data;

  String get uuid => callKitUuid(conversationId);

  static CallKitIncoming? fromData(Map<String, String> data) {
    final conversationId = _filled(data['conversationId'] ?? data['vcId']);
    final handle = _filled(data['callerId'] ?? data['suid']);
    if (conversationId == null || handle == null) return null;
    if (_filled(data['vcp']) == null) return null;
    final type = data['type'] ?? data['callType'];
    final iv = data['iv'];
    return CallKitIncoming(
      conversationId: conversationId,
      handle: handle,
      callerName: _filled(data['userName'] ?? data['title']) ?? handle,
      isVideo: type == 'VIDEO' || iv == 'true' || iv == '1',
      data: Map.unmodifiable(data),
    );
  }

  Map<String, Object> toArguments() => {
    'uuid': uuid,
    'conversationId': conversationId,
    'handle': handle,
    'name': callerName,
    'video': isVideo,
    'data': data,
  };
}

class FinishedCallRecord {
  const FinishedCallRecord({
    required this.conversationId,
    required this.hangupType,
    required this.durationMs,
  });

  final String conversationId;
  final String hangupType;
  final int durationMs;

  CallKitEndReason get endReason => switch (hangupType) {
    'CANCELED' => CallKitEndReason.remoteEnded,
    'MISSED' => CallKitEndReason.unanswered,
    'REJECTED' => CallKitEndReason.declinedElsewhere,
    _ when durationMs > 0 => CallKitEndReason.answeredElsewhere,
    _ => CallKitEndReason.remoteEnded,
  };

  static FinishedCallRecord? fromPush(Object? payload) {
    if (payload is! Map) return null;
    final message = payload['message'];
    if (message is! Map || message['status'] == 'REMOVED') return null;
    final attaches = message['attaches'];
    if (attaches is! List) return null;
    for (final attach in attaches) {
      if (attach is! Map || attach['_type'] != 'CALL') continue;
      final conversationId = _filled(attach['conversationId']?.toString());
      final hangupType = _filled(attach['hangupType']?.toString());
      if (conversationId == null || hangupType == null) return null;
      final duration = attach['duration'];
      return FinishedCallRecord(
        conversationId: conversationId,
        hangupType: hangupType,
        durationMs: duration is num ? duration.toInt() : 0,
      );
    }
    return null;
  }
}

class CallKitEvent {
  const CallKitEvent({
    required this.action,
    required this.conversationId,
    this.data = const {},
    this.muted = false,
    this.onHold = false,
  });

  final CallKitAction action;
  final String conversationId;
  final Map<String, String> data;
  final bool muted;
  final bool onHold;

  static CallKitEvent? parse(Object? raw) {
    if (raw is! Map) return null;
    final action = CallKitAction.values.asNameMap()[raw['action']];
    final conversationId = raw['conversationId'];
    if (action == null || conversationId is! String || conversationId.isEmpty) {
      return null;
    }
    final data = raw['data'];
    return CallKitEvent(
      action: action,
      conversationId: conversationId,
      data: data is Map
          ? {
              for (final entry in data.entries)
                if (entry.key is String && entry.value != null)
                  entry.key as String: entry.value.toString(),
            }
          : const {},
      muted: raw['muted'] == true,
      onHold: raw['onHold'] == true,
    );
  }
}

class CallKitRegistry {
  CallKitRegistry({this.memory = 32});

  final int memory;
  final Set<String> _ringing = {};
  final LinkedHashSet<String> _settled = LinkedHashSet();

  bool isKnown(String conversationId) =>
      _ringing.contains(conversationId) || _settled.contains(conversationId);

  void ring(String conversationId) {
    _settled.remove(conversationId);
    _ringing.add(conversationId);
  }

  void forget(String conversationId) => _ringing.remove(conversationId);

  bool settle(String conversationId) {
    final wasRinging = _ringing.remove(conversationId);
    _settled
      ..remove(conversationId)
      ..add(conversationId);
    while (_settled.length > memory) {
      _settled.remove(_settled.first);
    }
    return wasRinging;
  }
}

class _SystemCall {
  _SystemCall(this.conversationId, this.session);

  final String conversationId;
  final CallSession session;
  StreamSubscription<CallSessionState>? stateSub;
  StreamSubscription<void>? infoSub;
  bool reportedMuted = false;
  bool held = false;
  bool mutedBeforeHold = false;
  bool finished = false;
}

class CallKitBridge {
  CallKitBridge._();
  static final CallKitBridge instance = CallKitBridge._();

  static const _method = MethodChannel(
    'io.github.stillemptynow.promax/callkit',
  );
  static const _events = EventChannel(
    'io.github.stillemptynow.promax/callkit_events',
  );

  final CallKitRegistry _registry = CallKitRegistry();
  StreamSubscription<dynamic>? _eventsSub;
  _SystemCall? _active;
  bool? _appCallActive;

  bool get isSupported {
    try {
      return Platform.isIOS;
    } catch (_) {
      return false;
    }
  }

  void init() {
    if (_eventsSub != null || !isSupported) return;
    _eventsSub = _events.receiveBroadcastStream().listen(
      _onEvent,
      onError: (e) => logger.w('CallKitBridge.init: events stream error: $e'),
    );
    unawaited(setAppCallActive(CallController.instance.activeSession != null));
  }

  bool owns(String conversationId) =>
      isSupported && _registry.isKnown(conversationId);

  Future<bool> reportIncoming(Map<String, String> data) async {
    if (!isSupported || CallController.instance.isBusy) return false;
    final incoming = CallKitIncoming.fromData(data);
    if (incoming == null) return false;
    final id = incoming.conversationId;
    if (_registry.isKnown(id)) return true;
    _registry.ring(id);
    try {
      final shown =
          await _method.invokeMethod<bool>(
            'reportIncoming',
            incoming.toArguments(),
          ) ??
          false;
      if (!shown) _registry.forget(id);
      return shown;
    } catch (e) {
      _registry.forget(id);
      logger.w('CallKitBridge.reportIncoming: conv=$id $e');
      return false;
    }
  }

  void finishRinging(FinishedCallRecord record) {
    if (!isSupported || !_registry.settle(record.conversationId)) return;
    unawaited(_end(record.conversationId, record.endReason));
  }

  Future<void> setAppCallActive(bool active) async {
    if (!isSupported || _appCallActive == active) return;
    _appCallActive = active;
    await _invoke('setAppCallActive', {'active': active});
  }

  void _onEvent(Object? raw) {
    final event = CallKitEvent.parse(raw);
    if (event == null) return;
    switch (event.action) {
      case CallKitAction.answer:
        _answer(event);
      case CallKitAction.decline:
        unawaited(_decline(event));
      case CallKitAction.hangup:
      case CallKitAction.reset:
        _registry.settle(event.conversationId);
        _hangup(event.conversationId);
      case CallKitAction.mute:
        unawaited(_mute(event));
      case CallKitAction.hold:
        unawaited(_hold(event));
      case CallKitAction.timeout:
        _registry.settle(event.conversationId);
    }
  }

  void _answer(CallKitEvent event) {
    final id = event.conversationId;
    _registry.settle(id);
    final call = IncomingCall.fromNative(event.data);
    final session = call == null
        ? null
        : CallController.instance.answerFromSystem(call);
    if (session == null) {
      unawaited(_end(id, CallKitEndReason.failed));
      return;
    }
    final previous = _active;
    if (previous != null) _finish(previous);
    final system = _SystemCall(id, session);
    _active = system;
    if (session.currentState == CallSessionState.ended) {
      _finish(system);
      return;
    }
    system.stateSub = session.stateStream.listen((state) {
      if (state == CallSessionState.ended) _finish(system);
    }, onDone: () => _finish(system));
    system.infoSub = session.infoUpdates.listen((_) => _syncMuted(system));
  }

  Future<void> _decline(CallKitEvent event) async {
    _registry.settle(event.conversationId);
    final call = IncomingCall.fromNative(event.data);
    if (call == null) return;
    await CallController.instance.rejectIncoming(call);
  }

  void _hangup(String conversationId) {
    final system = _systemFor(conversationId);
    if (system == null) return;
    unawaited(system.session.hangup());
  }

  Future<void> _mute(CallKitEvent event) async {
    final system = _systemFor(event.conversationId);
    if (system == null) return;
    system.reportedMuted = event.muted;
    if (system.held) {
      system.mutedBeforeHold = event.muted;
      return;
    }
    await _setMuted(system.session, event.muted);
  }

  Future<void> _hold(CallKitEvent event) async {
    final system = _systemFor(event.conversationId);
    if (system == null || system.held == event.onHold) return;
    system.held = event.onHold;
    if (event.onHold) {
      system.mutedBeforeHold = system.session.isMuted;
      await _setMuted(system.session, true);
      return;
    }
    await _setMuted(system.session, system.mutedBeforeHold);
    _syncMuted(system);
  }

  Future<void> _setMuted(CallSession session, bool muted) async {
    if (session.isMuted == muted) return;
    try {
      await session.setMuted(muted);
    } catch (e) {
      logger.w('CallKitBridge.setMuted: muted=$muted $e');
    }
  }

  void _syncMuted(_SystemCall system) {
    if (system.finished || system.held) return;
    final muted = system.session.isMuted;
    if (muted == system.reportedMuted) return;
    system.reportedMuted = muted;
    unawaited(
      _invoke('setMuted', {
        'conversationId': system.conversationId,
        'muted': muted,
      }),
    );
  }

  void _finish(_SystemCall system) {
    if (system.finished) return;
    system.finished = true;
    unawaited(system.stateSub?.cancel());
    unawaited(system.infoSub?.cancel());
    if (identical(_active, system)) _active = null;
    final reason = system.session.endedLocally
        ? CallKitEndReason.local
        : CallKitEndReason.remoteEnded;
    unawaited(_end(system.conversationId, reason));
  }

  _SystemCall? _systemFor(String conversationId) {
    final system = _active;
    if (system == null || system.conversationId != conversationId) return null;
    return system;
  }

  Future<void> _end(String conversationId, CallKitEndReason reason) => _invoke(
    'endCall',
    {'conversationId': conversationId, 'reason': reason.name},
  );

  Future<void> _invoke(String method, Map<String, Object> args) async {
    try {
      await _method.invokeMethod<void>(method, args);
    } catch (e) {
      logger.w('CallKitBridge.$method: $e');
    }
  }
}

String? _filled(String? value) {
  final trimmed = value?.trim();
  return trimmed == null || trimmed.isEmpty ? null : trimmed;
}
