import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../l10n/app_localizations.dart';

class DeletedMessageMark extends StatelessWidget {
  const DeletedMessageMark({super.key, required this.color, this.size = 13});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Semantics(
      label: l10n?.messageDeletedMarkHint,
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Symbols.delete, size: size, color: color),
          if (l10n != null) ...[
            const SizedBox(width: 2),
            Text(
              l10n.messageDeletedMark,
              style: TextStyle(
                color: color,
                fontSize: size - 2,
                fontStyle: FontStyle.italic,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
