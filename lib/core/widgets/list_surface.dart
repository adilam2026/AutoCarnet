import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// A single bordered surface holding several rows separated by hairlines -
/// the "Premium sobre" (V2) alternative to giving every list item its own
/// shadowed card, which the design review called out as excessive ("éviter
/// une grosse carte différente pour chaque ligne"). Rows stay whatever
/// widget the caller wants; this only owns the shared background, border,
/// radius, shadow and the dividers between them.
class ListSurface extends StatelessWidget {
  const ListSurface({super.key, required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.6)),
        boxShadow: AppElevation.card(scheme),
      ),
      clipBehavior: Clip.antiAlias,
      // A tappable row (ListTile/InkWell) paints its splash on the nearest
      // Material ancestor - without one here, that ancestor could be far
      // up the tree (e.g. the Scaffold's own Material), and this surface's
      // own opaque background would then paint over and hide the splash.
      // `transparency` adds no visual of its own - the Container above
      // already owns the background/border/shadow - it only gives rows a
      // correct, nearby painting surface.
      child: Material(
        type: MaterialType.transparency,
        child: Column(
          children: [
            for (var i = 0; i < children.length; i++) ...[
              if (i > 0) Divider(height: 1, color: scheme.outlineVariant.withValues(alpha: 0.6)),
              children[i],
            ],
          ],
        ),
      ),
    );
  }
}
