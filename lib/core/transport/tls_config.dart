import 'package:flutter/foundation.dart';
import 'package:kolibri/kolibri.dart' show setTrustMincifryCa;
import 'package:shared_preferences/shared_preferences.dart';

import '../config/build_profile.dart';
import '../config/config.dart';
import 'promax_http_overrides.dart';

// #***! TLS, доверие к CA минцифры и dev режим
abstract class TlsConfig {
  static const String prefKey = 'dev_tls_insecure';

  static Future<void> applyMincifryTrust() async {
    final prefs = await SharedPreferences.getInstance();
    setMincifryTrust(
      prefs.getBool(ServerConfig.prefTrustMincifryKey) ??
          ServerConfig.defaultTrustMincifryCa,
    );
  }

  static void setMincifryTrust(bool enabled) {
    setTrustMincifryCa(enabled: enabled);
    if (kIsWeb) return;
    ProMaxHttpOverrides.install(trustMincifryForMaxHosts: enabled);
  }

  // #***! только в dev сборке, в релизе false
  static Future<bool> isInsecureAllowed() async {
    if (!BuildProfile.insecureTransport) return false;
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(prefKey) ?? false;
  }

  static Future<void> setInsecureAllowed(bool value) async {
    if (!BuildProfile.insecureTransport) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(prefKey, value);
  }
}
