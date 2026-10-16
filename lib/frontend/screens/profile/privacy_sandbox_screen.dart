import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../core/config/build_profile.dart';
import '../../../core/config/persisted_setting.dart';
import '../../../core/config/privacy_settings.dart';
import '../../../core/privacy/ip_geo_lookup.dart';
import '../../../core/storage/spoofing_service.dart';
import '../../../l10n/app_localizations.dart';
import '../../../main.dart' show api;
import '../../widgets/confirm_dialog.dart';
import '../../widgets/connection_status.dart';
import '../../widgets/custom_notification.dart';
import '../../widgets/promax_ui.dart';
import '../../widgets/settings_card.dart';

class PrivacySandboxScreen extends StatefulWidget {
  const PrivacySandboxScreen({super.key});

  @override
  State<PrivacySandboxScreen> createState() => _PrivacySandboxScreenState();
}

class _PrivacySandboxScreenState extends State<PrivacySandboxScreen> {
  String? _accountScope;
  bool? _accountSendsRealDevice;
  bool _applying = false;

  @override
  void initState() {
    super.initState();
    _loadAccountState();
  }

  Future<void> _loadAccountState() async {
    final scope = await SpoofingService.activeScope();
    final real = await SpoofingService.sendsRealDevice(scope);
    if (!mounted) return;
    setState(() {
      _accountScope = scope == SpoofingService.pendingScope ? null : scope;
      _accountSendsRealDevice = real;
    });
  }

  Future<void> _hideDeviceForAccount() async {
    final scope = _accountScope;
    if (scope == null || _applying) return;
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showConfirmDialog(
      context,
      title: l10n.privacyApplyToAccountLabel,
      message: l10n.privacyApplyToAccountMessage,
      confirmLabel: l10n.privacyApplyToAccountConfirm,
    );
    if (!confirmed || !mounted) return;
    setState(() => _applying = true);
    try {
      await SpoofingService.hideRealDevice(scope);
      await api.disconnect();
      await api.connect();
      if (!mounted) return;
      showCustomNotification(context, l10n.privacyApplyToAccountDone);
    } catch (e) {
      if (!mounted) return;
      showCustomNotification(
        context,
        l10n.privacyApplyToAccountFailed(e.toString()),
      );
    } finally {
      if (mounted) setState(() => _applying = false);
    }
    await _loadAccountState();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      backgroundColor: cs.surface,
      appBar: ConnectionTitleBar(
        titleText: l10n.privacySandboxTitle,
        backgroundColor: cs.surface,
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
          children: [
            _Notice(text: l10n.privacySandboxIntro),
            ProMaxSectionTitle(l10n.privacySectionDevice),
            SettingsCard(
              children: [
                _PrivacyToggle(
                  setting: PrivacySettings.hideDevice,
                  icon: Symbols.phonelink_lock,
                  label: l10n.privacyHideDeviceLabel,
                  subtitle: l10n.privacyHideDeviceSubtitle,
                ),
                ..._accountDeviceTiles(l10n),
              ],
            ),
            ProMaxSectionTitle(l10n.privacySectionMiniApps),
            SettingsCard(
              children: [
                _PrivacyToggle(
                  setting: PrivacySettings.neutralWebUserAgent,
                  icon: Symbols.badge,
                  label: l10n.privacyNeutralAgentLabel,
                  subtitle: l10n.privacyNeutralAgentSubtitle,
                ),
                _PrivacyToggle(
                  setting: PrivacySettings.isolateMiniApps,
                  icon: Symbols.shield,
                  label: l10n.privacyIsolateMiniAppsLabel,
                  subtitle: l10n.privacyIsolateMiniAppsSubtitle,
                ),
                _PrivacyToggle(
                  setting: PrivacySettings.blockTrackers,
                  icon: Symbols.block,
                  label: l10n.privacyBlockTrackersLabel,
                  subtitle: l10n.privacyBlockTrackersSubtitle,
                ),
              ],
            ),
            ProMaxSectionTitle(l10n.privacySectionCalls),
            SettingsCard(
              children: [
                _PrivacyToggle(
                  setting: PrivacySettings.hideLocalAddresses,
                  icon: Symbols.lan,
                  label: l10n.privacyHideLocalAddressesLabel,
                  subtitle: l10n.privacyHideLocalAddressesSubtitle,
                ),
                _PrivacyToggle(
                  setting: PrivacySettings.relayCalls,
                  icon: Symbols.vpn_lock,
                  label: l10n.privacyRelayCallsLabel,
                  subtitle: l10n.privacyRelayCallsSubtitle,
                ),
              ],
            ),
            if (BuildProfile.ipGeoLookup || BuildProfile.selfUpdate) ...[
              ProMaxSectionTitle(l10n.privacySectionNetwork),
              SettingsCard(
                children: [
                  if (BuildProfile.ipGeoLookup)
                    _PrivacyToggle(
                      setting: PrivacySettings.sessionIpLookup,
                      icon: Symbols.travel_explore,
                      label: l10n.privacySessionIpLookupLabel,
                      subtitle: l10n.privacySessionIpLookupSubtitle(
                        IpGeoLookup.serviceHost,
                      ),
                    ),
                  if (BuildProfile.selfUpdate)
                    _PrivacyToggle(
                      setting: PrivacySettings.autoUpdateCheck,
                      icon: Symbols.system_update,
                      label: l10n.privacyAutoUpdateLabel,
                      subtitle: l10n.privacyAutoUpdateSubtitle,
                    ),
                ],
              ),
            ],
            const SizedBox(height: 18),
            _Notice(text: l10n.privacyNoticeTls),
            if (BuildProfile.firebasePush) ...[
              const SizedBox(height: 8),
              _Notice(text: l10n.privacyNoticeFirebase),
            ],
          ],
        ),
      ),
    );
  }

  List<Widget> _accountDeviceTiles(AppLocalizations l10n) {
    final real = _accountSendsRealDevice;
    if (_accountScope == null || real == null) return const [];
    if (!real) {
      return [
        _AccountStatus(
          icon: Symbols.verified_user,
          text: l10n.privacyAccountHiddenDevice,
        ),
      ];
    }
    return [
      _AccountStatus(
        icon: Symbols.warning,
        text: l10n.privacyAccountRealDevice,
      ),
      if (BuildProfile.spoofUi)
        SettingsNavTile(
          icon: Symbols.masks,
          label: l10n.privacyApplyToAccountLabel,
          onTap: _applying ? null : _hideDeviceForAccount,
        ),
    ];
  }
}

class _PrivacyToggle extends StatelessWidget {
  const _PrivacyToggle({
    required this.setting,
    required this.icon,
    required this.label,
    required this.subtitle,
  });

  final PersistedSetting<bool> setting;
  final IconData icon;
  final String label;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: setting.current,
      builder: (context, value, _) => SettingsToggleTile(
        icon: icon,
        label: label,
        subtitle: subtitle,
        value: value,
        onChanged: setting.save,
      ),
    );
  }
}

class _AccountStatus extends StatelessWidget {
  const _AccountStatus({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 16, 10),
      child: Row(
        children: [
          Icon(icon, size: 20, color: cs.onSurfaceVariant),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: cs.onSurfaceVariant,
                fontSize: 13,
                height: 1.3,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Text(
        text,
        style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13, height: 1.4),
      ),
    );
  }
}
