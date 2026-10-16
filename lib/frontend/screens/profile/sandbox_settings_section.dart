import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../core/config/app_colors.dart';
import '../../../core/security/mark_of_the_web.dart';
import '../../../core/security/sandbox_settings.dart';
import '../../../l10n/app_localizations.dart';
import '../../widgets/custom_notification.dart';
import '../../widgets/settings_card.dart';

class SandboxSettingsSection extends StatefulWidget {
  const SandboxSettingsSection({super.key});

  @override
  State<SandboxSettingsSection> createState() => _SandboxSettingsSectionState();
}

class _SandboxSettingsSectionState extends State<SandboxSettingsSection> {
  bool _confirmEveryFile = false;
  bool _strictProcess = false;

  @override
  void initState() {
    super.initState();
    _strictProcess = SandboxSettings.strictProcess();
    _loadConfirmEveryFile();
  }

  Future<void> _loadConfirmEveryFile() async {
    final value = await SandboxSettings.confirmEveryFile();
    if (mounted) setState(() => _confirmEveryFile = value);
  }

  Future<void> _setConfirmEveryFile(bool value) async {
    setState(() => _confirmEveryFile = value);
    try {
      await SandboxSettings.setConfirmEveryFile(value);
    } catch (_) {
      if (!mounted) return;
      setState(() => _confirmEveryFile = !value);
      showCustomNotification(
        context,
        AppLocalizations.of(context)!.sandboxSettingFailed,
      );
    }
  }

  void _setStrictProcess(bool value) {
    if (!SandboxSettings.setStrictProcess(value)) {
      showCustomNotification(
        context,
        AppLocalizations.of(context)!.sandboxSettingFailed,
      );
      return;
    }
    setState(() => _strictProcess = value);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final summary = MarkOfTheWeb.supported
        ? '${l10n.sandboxSummary} ${l10n.sandboxSummaryWindows}'
        : l10n.sandboxSummary;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(
            l10n.sandboxSectionTitle,
            style: TextStyle(
              color: cs.mutedText,
              fontSize: 12,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.8,
            ),
          ),
        ),
        SettingsCard(
          children: [
            SettingsToggleTile(
              icon: Symbols.folder_shared,
              label: l10n.sandboxConfirmEveryFile,
              subtitle: l10n.sandboxConfirmEveryFileHint,
              value: _confirmEveryFile,
              onChanged: _setConfirmEveryFile,
            ),
            if (SandboxSettings.strictProcessSupported)
              SettingsToggleTile(
                icon: Symbols.shield_lock,
                label: l10n.sandboxStrictProcess,
                subtitle: l10n.sandboxStrictProcessHint,
                value: _strictProcess,
                onChanged: _setStrictProcess,
              ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
          child: Text(
            summary,
            style: TextStyle(color: cs.mutedText, fontSize: 13, height: 1.35),
          ),
        ),
      ],
    );
  }
}
