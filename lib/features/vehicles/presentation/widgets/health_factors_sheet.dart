import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/layout.dart';
import '../../../../core/widgets/sheet_handle.dart';
import '../../domain/vehicle_health.dart';

/// Detail view for a health score: the number alone ("90/100") doesn't
/// explain itself, so tapping it always opens exactly what's contributing.
Future<void> showHealthFactorsSheet(BuildContext context, VehicleHealthScore health) {
  final level = healthLevelForScore(health.score);
  return showModalBottomSheet(
    context: context,
    useSafeArea: true,
    builder: (sheetContext) {
      final scheme = Theme.of(sheetContext).colorScheme;
      final color = switch (level) {
        VehicleHealthLevel.good => Colors.green,
        VehicleHealthLevel.attention => Colors.orange,
        VehicleHealthLevel.critical => scheme.error,
      };
      return Padding(
        padding: EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.sm, AppSpacing.md,
            sheetSystemBottomInset(sheetContext) + AppSpacing.md),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SheetHandle(),
            Text('Santé du véhicule', style: Theme.of(sheetContext).textTheme.titleMedium),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                Text('${health.score}',
                    style: Theme.of(sheetContext).textTheme.displaySmall?.copyWith(
                          color: color,
                          fontWeight: FontWeight.w700,
                        )),
                Padding(
                  padding: const EdgeInsets.only(bottom: 6, left: 4),
                  child: Text('/100', style: Theme.of(sheetContext).textTheme.titleSmall),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.sm),
              child: LinearProgressIndicator(
                value: health.score / 100,
                minHeight: 8,
                backgroundColor: scheme.surfaceContainerHighest,
                color: color,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            for (final factor in health.factors)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      switch (factor.impact) {
                        HealthImpact.positive => Icons.check_circle_outline,
                        HealthImpact.negative => Icons.warning_amber_outlined,
                        HealthImpact.neutral => Icons.info_outline,
                      },
                      size: 18,
                      color: switch (factor.impact) {
                        HealthImpact.positive => Colors.green,
                        HealthImpact.negative => Colors.orange,
                        HealthImpact.neutral => scheme.onSurfaceVariant,
                      },
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(factor.label, style: Theme.of(sheetContext).textTheme.bodyMedium),
                          Text(factor.detail, style: Theme.of(sheetContext).textTheme.bodySmall),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      );
    },
  );
}
