import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../domain/vehicle_card_color.dart';

/// A small, self-contained "couleur de la carte" picker (bloc 9/11, then
/// reused by the quick-create screen in the "palette plus vive" pass): a
/// live preview of the identity band in the currently-selected colour, then
/// the AutoCarnet palette as tappable pastilles - deliberately not a full
/// configurator, just enough to answer "à quoi ressemblera ma carte ?".
/// Shared between [VehicleEditScreen] and [VehicleCreateScreen] so the two
/// pickers can never silently drift apart.
class CardColorPicker extends StatelessWidget {
  const CardColorPicker({
    super.key,
    required this.selected,
    required this.vehicleLabel,
    required this.onChanged,
  });

  final VehicleCardColor selected;
  final String vehicleLabel;
  final ValueChanged<VehicleCardColor> onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final onSelected = selected.onColor;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AnimatedContainer(
          duration: AppMotion.fast,
          height: 52,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: selected.color,
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
          child: Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: onSelected.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                child: Icon(Icons.directions_car_filled, size: 14, color: onSelected),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  vehicleLabel,
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: onSelected),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            for (final c in VehicleCardColor.values)
              ColorSwatch(
                color: c,
                selected: c == selected,
                onTap: () => onChanged(c),
              ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          selected.label,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(color: scheme.onSurfaceVariant),
        ),
      ],
    );
  }
}

/// One round pastille in the palette (bloc 6: "conserver le principe des
/// pastilles rondes"). The selected one gets a reinforced outer ring plus a
/// check mark - never a 15-name legend under 15 pastilles, the current
/// selection's own [VehicleCardColor.label] is shown once, above, by
/// [CardColorPicker] instead.
class ColorSwatch extends StatelessWidget {
  const ColorSwatch({super.key, required this.color, required this.selected, required this.onTap});

  final VehicleCardColor color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: color.label,
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Container(
          width: 34,
          height: 34,
          padding: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: selected
                ? Border.all(color: Theme.of(context).colorScheme.onSurface, width: 2)
                : null,
          ),
          child: Container(
            decoration: BoxDecoration(shape: BoxShape.circle, color: color.color),
            // Some palette tones are light enough that a white check mark
            // would itself be unreadable (mission "palette plus vive": the
            // palette is no longer uniformly dark) - the same real
            // luminance-based contrast as the rest of the app, never an
            // assumed white.
            child: selected ? Icon(Icons.check, size: 16, color: color.onColor) : null,
          ),
        ),
      ),
    );
  }
}
