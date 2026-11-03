import 'dart:async';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../core/config/app_performance.dart';
import '../../../core/hub/diagnostics.dart';
import '../../../core/hub/hub_client.dart';
import '../../../core/hub/hub_social.dart';
import '../../../core/storage/token_storage.dart';
import '../../../l10n/app_localizations.dart';
import '../../widgets/confirm_dialog.dart';
import '../../widgets/connection_status.dart';
import '../../widgets/custom_notification.dart';
import '../../widgets/settings_card.dart';

class HubSettingsScreen extends StatefulWidget {
  const HubSettingsScreen({super.key});

  @override
  State<HubSettingsScreen> createState() => _HubSettingsScreenState();
}

class _HubSettingsScreenState extends State<HubSettingsScreen> {
  final _client = HubClient();
  late final _social = HubSocial(client: _client);
  bool _busy = false;
  String? _status;

  @override
  void initState() {
    super.initState();
    unawaited(_initSocial());
  }

  Future<void> _initSocial() async {
    final accountId = await TokenStorage.getActiveAccountId();
    if (accountId != null && mounted) {
      await _social.init(accountId);
    }
  }

  @override
  void dispose() {
    _social.dispose();
    _client.cancel();
    super.dispose();
  }

  Future<void> _check() async {
    if (_busy) return;
    setState(() => _busy = true);
    final l10n = AppLocalizations.of(context)!;
    try {
      final health = await _client.request('/health');
      if (health['service'] != 'ProMax' || health['status'] != 'ok') {
        throw const HubException(502);
      }
      if (mounted) setState(() => _status = l10n.hubConnectionOk);
    } catch (_) {
      if (mounted) setState(() => _status = l10n.hubUnavailable);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _report() async {
    if (_busy) return;
    final l10n = AppLocalizations.of(context)!;
    if (!Diagnostics.enabled.value) {
      showCustomNotification(context, l10n.hubDiagnosticsDisabled);
      return;
    }
    if (AppPerformance.frameHealth.frames == 0) {
      showCustomNotification(context, l10n.hubPerformanceEmpty);
      return;
    }
    setState(() => _busy = true);
    try {
      final sent = await Diagnostics.sendPerformance();
      if (mounted) {
        showCustomNotification(
          context,
          sent ? l10n.hubPerformanceSent : l10n.hubDiagnosticsDisabled,
        );
      }
    } catch (_) {
      if (mounted) showCustomNotification(context, l10n.hubUnavailable);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _deleteHubData() async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showConfirmDialog(
      context,
      title: l10n.hubDeleteData,
      message: l10n.hubDeleteDataConfirm,
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    await _socialAction(
      _social.deleteHubData,
      success: l10n.hubDeleteDataSuccess,
    );
  }

  Future<void> _socialAction(
    Future<void> Function() action, {
    String? success,
  }) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
      if (mounted && success != null) showCustomNotification(context, success);
    } catch (_) {
      if (mounted) {
        showCustomNotification(
          context,
          AppLocalizations.of(context)!.hubActionFailed,
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: ConnectionTitleBar(titleText: l10n.hubConnectionTitle),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(_client.baseUri.host),
          const SizedBox(height: 16),
          SettingsCard(
            children: [
              SettingsNavTile(
                icon: Symbols.cloud_sync,
                label: _busy ? l10n.hubWorking : l10n.hubCheckConnection,
                value: _status,
                onTap: _check,
              ),
              SettingsNavTile(
                icon: Symbols.speed,
                label: l10n.hubSendPerformance,
                onTap: _report,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(l10n.hubPerformanceHint),
          const SizedBox(height: 16),
          ListenableBuilder(
            listenable: _social,
            builder: (context, _) => SettingsCard(
              children: [
                SettingsToggleTile(
                  icon: Symbols.verified,
                  label: l10n.hubShowProMaxBadge,
                  subtitle: l10n.hubShowProMaxBadgeHint,
                  value: _social.showPromax,
                  enabled: !_busy,
                  onChanged: (value) => unawaited(
                    _socialAction(() => _social.setShowPromax(value)),
                  ),
                ),
                SettingsToggleTile(
                  icon: Symbols.devices,
                  label: l10n.hubShowOsPresence,
                  subtitle: l10n.hubShowOsPresenceHint,
                  value: _social.showOs,
                  enabled: !_busy,
                  onChanged: (value) =>
                      unawaited(_socialAction(() => _social.setShowOs(value))),
                ),
                SettingsNavTile(
                  icon: Symbols.delete_forever,
                  label: l10n.hubDeleteData,
                  onTap: _deleteHubData,
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          ValueListenableBuilder<bool>(
            valueListenable: Diagnostics.enabled,
            builder: (context, enabled, _) => SettingsCard(
              children: [
                SettingsToggleTile(
                  icon: Symbols.bug_report,
                  label: l10n.diagnosticsTitle,
                  subtitle: l10n.diagnosticsHint,
                  value: enabled,
                  onChanged: Diagnostics.setEnabled,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
