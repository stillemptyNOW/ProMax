import 'package:flutter/material.dart';

import '../../widgets/settings_icon_tile.dart';

class ChatToolTile extends StatelessWidget {
  const ChatToolTile({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.value,
  });

  final IconData icon;
  final String label;
  final String? value;
  final VoidCallback onTap;

  static double extentFor(BuildContext context) {
    final scaler = MediaQuery.textScalerOf(context);
    return 70 + (scaler.scale(13.5) + scaler.scale(11.5)) * 1.35;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: cs.surfaceContainerHighest.withValues(alpha: 0.7),
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 14, 10, 10),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SettingsIconTile(icon: icon),
              const SizedBox(height: 8),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: cs.onSurface,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (value != null) ...[
                const SizedBox(height: 2),
                Text(
                  value!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: cs.onSurfaceVariant, fontSize: 11.5),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
