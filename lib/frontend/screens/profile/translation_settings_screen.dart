import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../core/translation/message_translator.dart';
import '../../../core/translation/translation_backend.dart';
import '../../../core/translation/translation_languages.dart';
import '../../../core/translation/translation_settings.dart';
import '../../../l10n/app_localizations.dart';
import '../../widgets/custom_notification.dart';

class TranslationSettingsScreen extends StatefulWidget {
  const TranslationSettingsScreen({super.key});

  @override
  State<TranslationSettingsScreen> createState() =>
      _TranslationSettingsScreenState();
}

class _TranslationSettingsScreenState extends State<TranslationSettingsScreen> {
  final _settings = TranslationSettings.instance;
  final _translator = MessageTranslator.instance;
  late final Future<TranslationCapabilities> _capabilities = _translator
      .loadCapabilities();
  List<String> _models = const [];
  final Set<String> _deleting = {};

  @override
  void initState() {
    super.initState();
    _loadModels();
  }

  Future<void> _loadModels() async {
    final models = await _translator.downloadedModels();
    if (mounted) setState(() => _models = models);
  }

  Future<void> _delete(String language) async {
    setState(() => _deleting.add(language));
    final deleted = await _translator.deleteModel(language);
    if (!mounted) return;
    final l10n = AppLocalizations.of(context)!;
    setState(() => _deleting.remove(language));
    showCustomNotification(
      context,
      deleted
          ? l10n.translationSettingsModelDeleted
          : l10n.translationSettingsModelDeleteFailed,
    );
    await _loadModels();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.translationSettingsTitle)),
      body: FutureBuilder<TranslationCapabilities>(
        future: _capabilities,
        builder: (context, snapshot) {
          final caps = snapshot.data;
          if (caps == null) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!caps.available) {
            return Center(child: Text(l10n.translationUnavailable));
          }
          return ListView(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(l10n.translationSettingsPrivacy),
              ),
              ValueListenableBuilder<String?>(
                valueListenable: _settings.targetLanguage,
                builder: (context, target, _) => ListTile(
                  leading: const Icon(Symbols.translate),
                  title: Text(l10n.translationSettingsTarget),
                  trailing: DropdownButton<String>(
                    value: target ?? '',
                    items: [
                      DropdownMenuItem(
                        value: '',
                        child: Text(
                          l10n.translationSettingsTargetApp(
                            Localizations.localeOf(context).languageCode,
                          ),
                        ),
                      ),
                      for (final code in TranslationLanguages.targets)
                        DropdownMenuItem(
                          value: code,
                          child: Text(TranslationLanguages.nameOf(code)),
                        ),
                    ],
                    onChanged: (value) =>
                        _settings.setTargetLanguage(value == '' ? null : value),
                  ),
                ),
              ),
              if (caps.wifiOnlyOption)
                ValueListenableBuilder<bool>(
                  valueListenable: _settings.wifiOnly,
                  builder: (context, enabled, _) => SwitchListTile(
                    title: Text(l10n.translationSettingsWifiOnly),
                    subtitle: Text(l10n.translationSettingsWifiOnlySubtitle),
                    value: enabled,
                    onChanged: _settings.setWifiOnly,
                  ),
                ),
              if (caps.manageModels) ...[
                ListTile(title: Text(l10n.translationSettingsModels)),
                if (_models.isEmpty)
                  ListTile(title: Text(l10n.translationSettingsModelsEmpty)),
                for (final code in _models)
                  ListTile(
                    title: Text(TranslationLanguages.nameOf(code)),
                    trailing: IconButton(
                      tooltip: l10n.translationSettingsDeleteModel,
                      icon: const Icon(Symbols.delete),
                      onPressed: _deleting.contains(code)
                          ? null
                          : () => _delete(code),
                    ),
                  ),
              ] else
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(l10n.translationSettingsSystemModels),
                ),
            ],
          );
        },
      ),
    );
  }
}
