import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/platform_settings.dart';
import '../storage/token_storage.dart';
import 'hub_client.dart';
import 'hub_content.dart';

class HubSocial extends ChangeNotifier {
  HubSocial({HubClient? client}) : client = client ?? HubClient();

  final HubClient client;
  int? _accountId;
  String? _token;
  bool _showOs = false;
  bool _showPromax = false;
  Timer? _pulseTimer;
  final Map<int, HubPeer> _peers = {};
  bool _disposed = false;

  int? get accountId => _accountId;
  bool get showOs => _showOs;
  bool get showPromax => _showPromax;
  bool get hasToken => _token != null && _token!.isNotEmpty;
  String? get token => _token;
  HubConsent get consent =>
      HubConsent(showOs: _showOs, showPromax: _showPromax);

  static String showOsKey(int id) => 'promax_hub_show_os_$id';
  static String showPromaxKey(int id) => 'promax_hub_show_promax_$id';
  static String tokenKey(int id) => 'promax_hub_social_token_$id';

  Future<void> init(int accountId, {String? token}) async {
    _stopPulseTimer();
    _accountId = accountId;
    _peers.clear();
    final prefs = await SharedPreferences.getInstance();
    _showOs = prefs.getBool(showOsKey(accountId)) ?? false;
    _showPromax = prefs.getBool(showPromaxKey(accountId)) ?? false;
    if (token != null) {
      _token = token;
      await TokenStorage.writeSecure(tokenKey(accountId), token);
    } else {
      try {
        _token = await TokenStorage.readSecure(tokenKey(accountId));
      } catch (_) {
        _token = null;
      }
    }
    if (_disposed) return;
    if (_showOs && hasToken) {
      _startPulseTimer();
      unawaited(pulse());
    }
    notifyListeners();
  }

  Future<void> setShowOs(bool value) async {
    if (_showOs == value) return;
    final account = _accountId;
    final activeToken = _token;
    if (activeToken != null) {
      await client.updateIdentityConsent(
        activeToken,
        HubConsent(showOs: value, showPromax: _showPromax),
      );
      if (_disposed || _accountId != account || _token != activeToken) return;
    }
    _showOs = value;
    if (account != null) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(showOsKey(account), value);
    }
    if (activeToken != null) {
      if (_showOs) {
        _startPulseTimer();
        unawaited(pulse());
      } else {
        _stopPulseTimer();
      }
    }
    if (!_disposed) notifyListeners();
  }

  Future<void> setShowPromax(bool value) async {
    if (_showPromax == value) return;
    final account = _accountId;
    final activeToken = _token;
    if (activeToken != null) {
      await client.updateIdentityConsent(
        activeToken,
        HubConsent(showOs: _showOs, showPromax: value),
      );
      if (_disposed || _accountId != account || _token != activeToken) return;
    }
    _showPromax = value;
    if (account != null) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(showPromaxKey(account), value);
    }
    if (!_disposed) notifyListeners();
  }

  Future<void> pulse() async {
    final activeToken = _token;
    if (!_showOs || activeToken == null || _disposed) return;
    try {
      await client.sendPulse(activeToken, PlatformSettings.current);
    } catch (_) {}
  }

  void _startPulseTimer() {
    _stopPulseTimer();
    _pulseTimer = Timer.periodic(
      const Duration(seconds: 120),
      (_) => unawaited(pulse()),
    );
  }

  void _stopPulseTimer() {
    _pulseTimer?.cancel();
    _pulseTimer = null;
  }

  Future<void> deleteHubData() async {
    final activeToken = _token;
    final account = _accountId;
    if (activeToken != null) {
      await client.deleteIdentityMe(activeToken);
      if (_disposed || _accountId != account || _token != activeToken) return;
    }
    if (account != null) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(showOsKey(account));
      await prefs.remove(showPromaxKey(account));
      try {
        await TokenStorage.deleteSecure(tokenKey(account));
      } catch (_) {}
    }
    _showOs = false;
    _showPromax = false;
    _token = null;
    _peers.clear();
    _stopPulseTimer();
    if (!_disposed) notifyListeners();
  }

  Future<List<HubPeer>> queryPeers(List<int> accountIds) async {
    final activeToken = _token;
    if (activeToken == null || accountIds.isEmpty) return const [];
    final account = _accountId;
    try {
      final list = await client.queryPeers(activeToken, accountIds);
      if (_disposed || _accountId != account || _token != activeToken) {
        return const [];
      }
      for (final id in accountIds) {
        _peers.remove(id);
      }
      for (final peer in list) {
        _peers[peer.accountId] = peer;
      }
      notifyListeners();
      return list;
    } catch (_) {
      if (!_disposed && _accountId == account && _token == activeToken) {
        for (final id in accountIds) {
          _peers.remove(id);
        }
        notifyListeners();
      }
      return const [];
    }
  }

  HubPeer? getCachedPeer(int accountId) => _peers[accountId];

  bool hasProMaxBadge(int accountId) => _peers[accountId]?.promax ?? false;

  String? getPeerOs(int accountId) {
    final peer = _peers[accountId];
    if (peer == null || !peer.isOnline()) return null;
    return peer.os;
  }

  @override
  void dispose() {
    _disposed = true;
    _stopPulseTimer();
    super.dispose();
  }
}
