import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../backend/api.dart';
import '../../core/utils/app_foreground.dart';
import '../../main.dart' show api;

mixin ReloadOnReconnect<T extends StatefulWidget> on State<T> {
  StreamSubscription<SessionState>? _reconnectSub;
  int _reloadedEpoch = api.sessionEpoch;

  void reloadAfterReconnect();

  @override
  void initState() {
    super.initState();
    _reconnectSub = api.stateStream.listen(_onSessionState);
    AppForeground.notifier.addListener(_onForegroundChanged);
  }

  @override
  void dispose() {
    _reconnectSub?.cancel();
    AppForeground.notifier.removeListener(_onForegroundChanged);
    super.dispose();
  }

  void _onForegroundChanged() {
    if (AppForeground.value) _onSessionState(api.state);
  }

  void _onSessionState(SessionState state) {
    if (state != SessionState.online) return;
    if (api.sessionEpoch == _reloadedEpoch) return;
    if (!AppForeground.value) return;
    _reloadedEpoch = api.sessionEpoch;
    if (mounted) reloadAfterReconnect();
  }
}
