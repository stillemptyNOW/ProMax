import 'package:flutter/material.dart';

import '../../../core/crypto/group_e2ee_service.dart';
import '../../../l10n/app_localizations.dart';
import '../../widgets/custom_notification.dart';
import '../../widgets/settings_card.dart';

class GroupEncryptionScreen extends StatefulWidget {
  const GroupEncryptionScreen({
    super.key,
    required this.accountId,
    required this.groupId,
    this.service,
  });

  final int accountId;
  final int groupId;
  final GroupE2eeService? service;

  @override
  State<GroupEncryptionScreen> createState() => _GroupEncryptionScreenState();
}

class _GroupEncryptionScreenState extends State<GroupEncryptionScreen> {
  late final GroupE2eeService _service =
      widget.service ?? GroupE2eeService.instance;
  bool _loading = true;
  bool _busy = false;
  bool _loadFailed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      await _service.ensureLoaded(widget.accountId, widget.groupId);
    } catch (_) {
      _loadFailed = true;
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _consent({required bool accept}) async {
    if (_busy) return;
    setState(() => _busy = true);
    final l10n = AppLocalizations.of(context)!;
    try {
      final agreed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(l10n.groupEncryptionTitle),
          content: Text(l10n.groupEncryptionConfirm),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(l10n.groupEncryptionCancel),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(l10n.groupEncryptionAgree),
            ),
          ],
        ),
      );
      if (agreed != true || !mounted) return;
      if (accept) {
        await _service.accept(widget.accountId, widget.groupId);
      } else {
        await _service.begin(widget.accountId, widget.groupId);
      }
    } catch (_) {
      if (mounted) showCustomNotification(context, l10n.groupEncryptionFailed);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _status(AppLocalizations l10n, GroupEncryptionInfo info) {
    if (!_service.available) return l10n.groupEncryptionUnavailable;
    switch (info.block) {
      case GroupEncryptionBlock.changed:
        return l10n.groupEncryptionChanged;
      case GroupEncryptionBlock.verification:
        return l10n.groupEncryptionVerification;
      case GroupEncryptionBlock.membership:
        return l10n.groupEncryptionMembership;
      case GroupEncryptionBlock.transport:
        return l10n.groupEncryptionTransport;
      case GroupEncryptionBlock.unavailable:
        return l10n.groupEncryptionUnavailable;
      case GroupEncryptionBlock.consent:
        return l10n.groupEncryptionWaiting;
      case GroupEncryptionBlock.keys:
        return l10n.groupEncryptionKeys;
      case null:
        if (info.ready) return l10n.groupEncryptionReady;
        if (info.required && info.consentCount >= info.memberCount) {
          return l10n.groupEncryptionKeys;
        }
        if (info.required || info.epoch > 0) return l10n.groupEncryptionWaiting;
        return l10n.groupEncryptionOff;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.groupEncryptionTitle)),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ValueListenableBuilder<int>(
              valueListenable: _service.revision,
              builder: (context, _, _) {
                final info = _service.info(widget.accountId, widget.groupId);
                final awaitingConsent =
                    info.proposalReceived &&
                    info.epoch > 0 &&
                    !info.consented &&
                    info.block == null;
                final canBegin =
                    info.epoch == 0 ||
                    info.block == GroupEncryptionBlock.changed;
                return SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SettingsPanel(child: Text(l10n.groupEncryptionIntro)),
                      const SizedBox(height: 16),
                      SettingsPanel(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _loadFailed
                                  ? l10n.groupEncryptionFailed
                                  : _status(l10n, info),
                            ),
                            if (info.memberCount > 0 &&
                                !info.ready &&
                                info.block == null) ...[
                              const SizedBox(height: 8),
                              Text('${info.consentCount}/${info.memberCount}'),
                            ],
                          ],
                        ),
                      ),
                      if (!_loadFailed &&
                          _service.available &&
                          (canBegin || awaitingConsent)) ...[
                        const SizedBox(height: 16),
                        FilledButton(
                          onPressed: _busy
                              ? null
                              : () => _consent(
                                  accept: awaitingConsent && !canBegin,
                                ),
                          child: Text(
                            info.block == GroupEncryptionBlock.changed
                                ? l10n.groupEncryptionRestart
                                : awaitingConsent
                                ? l10n.groupEncryptionAccept
                                : l10n.groupEncryptionEnable,
                          ),
                        ),
                      ],
                    ],
                  ),
                );
              },
            ),
    );
  }
}
