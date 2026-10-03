import 'package:flutter/material.dart';

import '../../../core/config/komet_settings.dart';
import '../../../l10n/app_localizations.dart';
import '../../../main.dart' show animojiModule;
import '../../widgets/error_view.dart';
import '../../widgets/small_spinner.dart';

class QuickReactionScreen extends StatefulWidget {
  const QuickReactionScreen({super.key});

  @override
  State<QuickReactionScreen> createState() => _QuickReactionScreenState();
}

class _QuickReactionScreenState extends State<QuickReactionScreen> {
  late Future<void> _loading = animojiModule.ensureLoaded();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.proMaxQuickReaction)),
      body: FutureBuilder<void>(
        future: _loading,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: SmallSpinner(size: 32));
          }
          final emojis = animojiModule.emojis.toSet().toList();
          if (snapshot.hasError || emojis.isEmpty) {
            return ErrorView(
              message: l10n.proMaxReactionsLoadFailed,
              onRetry: () =>
                  setState(() => _loading = animojiModule.ensureLoaded()),
            );
          }
          return ValueListenableBuilder<String>(
            valueListenable: KometSettings.quickReaction,
            builder: (context, selected, _) => GridView.builder(
              padding: const EdgeInsets.all(20),
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 80,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
              ),
              itemCount: emojis.length,
              itemBuilder: (context, index) {
                final emoji = emojis[index];
                return Semantics(
                  button: true,
                  selected: selected == emoji,
                  label: emoji,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(20),
                    onTap: () => KometSettings.setQuickReaction(emoji),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: selected == emoji
                            ? cs.primaryContainer
                            : cs.surfaceContainerHigh,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: selected == emoji
                              ? cs.primary
                              : Colors.transparent,
                        ),
                      ),
                      child: Text(emoji, style: const TextStyle(fontSize: 32)),
                    ),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}
