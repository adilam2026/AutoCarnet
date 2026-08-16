import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/currency_format.dart';
import '../../../../core/utils/layout.dart';
import '../../../../core/widgets/sheet_handle.dart';
import '../../domain/valuation/valuation_models.dart';

/// "Comment cette estimation est-elle calculée ?" (bloc 15) - every line
/// comes straight from ValuationEngine's own breakdown, never hardcoded
/// here.
Future<void> showValuationBreakdownSheet(BuildContext context, ValuationResult result) {
  return showModalBottomSheet(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    builder: (sheetContext) {
      return Padding(
        padding: EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.sm, AppSpacing.md,
            sheetSystemBottomInset(sheetContext) + AppSpacing.md),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SheetHandle(),
              Text('Comment cette estimation est calculée',
                  style: Theme.of(sheetContext).textTheme.titleMedium),
              const SizedBox(height: AppSpacing.md),
              for (final line in result.breakdown)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(line.label,
                            style: Theme.of(sheetContext).textTheme.bodyMedium),
                      ),
                      if (line.delta != null)
                        Text(
                          '${line.delta! >= 0 ? '+' : ''}${formatAmount(line.delta!)}',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: line.delta! >= 0 ? Colors.green : Colors.red,
                          ),
                        ),
                    ],
                  ),
                ),
              const Divider(),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Estimation centrale',
                      style: Theme.of(sheetContext)
                          .textTheme
                          .titleSmall
                          ?.copyWith(fontWeight: FontWeight.w700)),
                  Text(
                    formatAmount(result.fairPrice),
                    style: Theme.of(sheetContext)
                        .textTheme
                        .titleSmall
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                'Estimation AutoCarnet indicative, calculée à partir de règles '
                'internes (ancienneté, kilométrage, état, motorisation) - '
                'aucune cote de marché externe n\'est connectée aujourd\'hui.',
                style: Theme.of(sheetContext).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      );
    },
  );
}
