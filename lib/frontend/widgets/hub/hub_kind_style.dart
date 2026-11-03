import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../core/hub/hub_content.dart';
import '../../../l10n/app_localizations.dart';

extension HubKindStyle on HubKind {
  IconData get icon => switch (this) {
    HubKind.news => Symbols.newspaper,
    HubKind.update => Symbols.system_update,
    HubKind.important => Symbols.priority_high,
    HubKind.promo => Symbols.local_offer,
    HubKind.holiday => Symbols.celebration,
  };

  Color accent(ColorScheme scheme) => switch (this) {
    HubKind.news => scheme.primary,
    HubKind.update => const Color(0xFF2E9E6B),
    HubKind.important => scheme.error,
    HubKind.promo => const Color(0xFFE08A00),
    HubKind.holiday => const Color(0xFFD0409B),
  };

  String label(AppLocalizations l10n) => switch (this) {
    HubKind.news => l10n.hubKindNews,
    HubKind.update => l10n.hubKindUpdate,
    HubKind.important => l10n.hubKindImportant,
    HubKind.promo => l10n.hubKindPromo,
    HubKind.holiday => l10n.hubKindHoliday,
  };
}

extension HubActionLabel on HubAction {
  String label(AppLocalizations l10n) => switch (this) {
    HubAction.link => l10n.hubActionLink,
    HubAction.update => l10n.hubActionUpdate,
    HubAction.settings => l10n.hubActionSettings,
  };
}
