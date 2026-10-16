import 'package:shared_preferences/shared_preferences.dart';

import '../privacy/neutral_user_agent.dart';
import '../storage/spoofing_service.dart';
import 'persisted_setting.dart';

abstract final class PrivacySettings {
  static const String cdnUserAgentKey = 'privacy_cdn_user_agent';

  static final PersistedSetting<bool> hideDevice = _flag(
    'privacy_hide_device',
    true,
  );
  static final PersistedSetting<bool> neutralWebUserAgent = _flag(
    'privacy_neutral_web_user_agent',
    true,
  );
  static final PersistedSetting<bool> isolateMiniApps = _flag(
    'privacy_isolate_mini_apps',
    true,
  );
  static final PersistedSetting<bool> blockTrackers = _flag(
    'privacy_block_trackers',
    true,
  );
  static final PersistedSetting<bool> hideLocalAddresses = _flag(
    'privacy_hide_local_addresses',
    true,
  );
  static final PersistedSetting<bool> relayCalls = _flag(
    'privacy_relay_calls',
    false,
  );
  static final PersistedSetting<bool> sessionIpLookup = _flag(
    'privacy_session_ip_lookup',
    false,
  );
  static final PersistedSetting<bool> autoUpdateCheck = _flag(
    'privacy_auto_update_check',
    true,
  );

  static String get cdnUserAgent =>
      NeutralUserAgent.cdn(SpoofingService.hardcodedAppVersion);

  static List<PersistedSetting<bool>> get all => [
    hideDevice,
    neutralWebUserAgent,
    isolateMiniApps,
    blockTrackers,
    hideLocalAddresses,
    relayCalls,
    sessionIpLookup,
    autoUpdateCheck,
  ];

  static Future<void> load() async {
    await Future.wait(all.map((setting) => setting.load()));
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getString(cdnUserAgentKey) != cdnUserAgent) {
      await prefs.setString(cdnUserAgentKey, cdnUserAgent);
    }
  }

  static PersistedSetting<bool> _flag(String key, bool defaultValue) =>
      PersistedSetting<bool>(
        prefKey: key,
        defaultValue: defaultValue,
        read: (prefs, key) => prefs.getBool(key),
        write: (prefs, key, value) async {
          await prefs.setBool(key, value);
        },
      );
}
