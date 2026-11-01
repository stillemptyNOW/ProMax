import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../core/cache/info_cache.dart';
import '../../../core/storage/app_database.dart';
import '../../../l10n/app_localizations.dart';
import '../../../models/contact_info.dart';
import '../../widgets/promax_avatar.dart';
import '../../widgets/hint_bubble.dart';

class SelfProfilePreviewScreen extends StatefulWidget {
  const SelfProfilePreviewScreen({super.key, required this.profile});
  final ProfileData profile;

  @override
  State<SelfProfilePreviewScreen> createState() =>
      _SelfProfilePreviewScreenState();
}

class _SelfProfilePreviewScreenState extends State<SelfProfilePreviewScreen> {
  late final Future<ContactInfo?> _contact = ContactInfoFetch.get(
    widget.profile.id,
  );

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final profile = widget.profile;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.selfProfilePreview)),
      body: FutureBuilder<ContactInfo?>(
        future: _contact,
        builder: (context, snapshot) {
          final contact = snapshot.data;
          final name =
              contact?.onemeFullName ??
              '${profile.firstName} ${profile.lastName ?? ''}'.trim();
          final bio =
              contact?.raw['description'] as String? ??
              contact?.raw['about'] as String? ??
              profile.description ??
              '';
          return ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Center(
                child: ProMaxAvatar(
                  name: name,
                  imageUrl: contact?.avatarUrl ?? profile.baseUrl,
                  size: 120,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                name,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 24),
              if (bio.isNotEmpty) SelectableText(bio),
              const SizedBox(height: 16),
              Builder(
                builder: (anchor) => ListTile(
                  leading: const Icon(Symbols.tag),
                  title: Text(l10n.selfProfileId),
                  subtitle: Text('${profile.id}'),
                  trailing: const Icon(Symbols.content_copy),
                  onTap: () async {
                    await Clipboard.setData(
                      ClipboardData(text: '${profile.id}'),
                    );
                    if (anchor.mounted) {
                      showHintBubble(anchor, l10n.selfProfileIdCopied);
                    }
                  },
                ),
              ),
              const SizedBox(height: 16),
              Text(
                l10n.selfProfilePreviewPrivacy,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
