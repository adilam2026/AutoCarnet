import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// The small soft-tinted icon container used throughout the app's
/// "Premium sobre" design language for an actionable row's leading icon
/// (see vehicle_home_screen.dart's `_ModuleTile`) - a bare, unstyled
/// [Icon] on a list row reads as belonging to an older generation of the
/// app. Pass [color] (e.g. `scheme.error`) for a rare/sensitive action;
/// omitted, it defaults to the app's own soft petrol accent.
class IconChip extends StatelessWidget {
  const IconChip(this.icon, {super.key, this.size = 36, this.iconSize = 18, this.color});

  final IconData icon;
  final double size;
  final double iconSize;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color != null ? color!.withValues(alpha: 0.12) : AppElevation.surfaceAccent(scheme),
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Icon(icon, size: iconSize, color: color ?? scheme.primary),
    );
  }
}
