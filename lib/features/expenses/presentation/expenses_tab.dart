import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/database.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/currency_format.dart';
import '../../../core/utils/feedback.dart';
import '../../../core/utils/layout.dart';
import '../../../core/utils/period_filter.dart';
import '../../../core/widgets/dismissible_delete.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/loading_error_views.dart';
import '../../../core/widgets/stat_tile.dart';
import '../../fuel/data/fuel_repository.dart';
import '../../fuel/presentation/fuel_form_sheet.dart';
import '../../maintenance/data/maintenance_repository.dart';
import '../../maintenance/presentation/maintenance_form_sheet.dart';
import '../../vehicles/data/vehicle_repository.dart';
import '../data/expense_repository.dart';
import 'expense_form_sheet.dart';

/// Strictly scoped to a single vehicle (RG-DEP-003): the stats and list here
/// never mix data across vehicles, by construction of the providers below.
class ExpensesTab extends ConsumerStatefulWidget {
  const ExpensesTab({super.key, required this.vehicleId});
  final String vehicleId;

  @override
  ConsumerState<ExpensesTab> createState() => _ExpensesTabState();
}

class _ExpensesTabState extends ConsumerState<ExpensesTab> {
  String? _categoryFilter;
  PeriodFilter _period = PeriodFilter.all;

  @override
  Widget build(BuildContext context) {
    final expensesAsync = ref.watch(vehicleExpensesProvider(widget.vehicleId));
    final statsAsync = ref.watch(vehicleExpenseStatsProvider(widget.vehicleId));
    final vehicleAsync = ref.watch(vehicleByIdProvider(widget.vehicleId));
    return Scaffold(
      appBar: AppBar(title: const Text('Dépenses')),
      body: expensesAsync.when(
        loading: () => const LoadingView(),
        error: (e, _) => ErrorView(message: e.toString()),
        data: (expenses) {
          if (expenses.isEmpty) {
            return EmptyState(
              icon: Icons.payments_outlined,
              title: 'Aucune dépense enregistrée',
              subtitle:
                  'Suivez toutes les dépenses de ce véhicule pour connaître '
                  'son coût réel au fil du temps.',
              actionLabel: 'Ajouter une dépense',
              onAction: () =>
                  showExpenseFormSheet(context, vehicleId: widget.vehicleId),
            );
          }
          final categories = {for (final e in expenses) e.category}.toList()
            ..sort();
          final filtered = expenses
              .where((e) => _categoryFilter == null || e.category == _categoryFilter)
              .where((e) => _period.matches(e.date))
              .toList();
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                    AppSpacing.md, AppSpacing.md, AppSpacing.md, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    statsAsync.maybeWhen(
                      data: (stats) => Padding(
                        padding: const EdgeInsets.only(bottom: AppSpacing.md),
                        child: StatTileRow(
                          tiles: [
                            StatTile(
                              label: 'Ce mois',
                              value: formatAmount(stats.thisMonth),
                              icon: Icons.calendar_today_outlined,
                            ),
                            StatTile(
                              label: 'Cette année',
                              value: formatAmount(stats.thisYear),
                              icon: Icons.event_outlined,
                            ),
                            StatTile(
                              label: 'Total',
                              value: formatAmount(stats.totalAll),
                              icon: Icons.summarize_outlined,
                              highlight: true,
                            ),
                          ],
                        ),
                      ),
                      orElse: () => const SizedBox.shrink(),
                    ),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          ChoiceChip(
                            label: const Text('Tout'),
                            selected: _categoryFilter == null,
                            onSelected: (_) =>
                                setState(() => _categoryFilter = null),
                          ),
                          const SizedBox(width: 8),
                          for (final c in categories) ...[
                            ChoiceChip(
                              label: Text(c),
                              selected: _categoryFilter == c,
                              onSelected: (_) =>
                                  setState(() => _categoryFilter = c),
                            ),
                            const SizedBox(width: 8),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    PeriodFilterChips(
                      value: _period,
                      onChanged: (p) => setState(() => _period = p),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: filtered.isEmpty
                    ? const EmptyState(
                        icon: Icons.filter_alt_off_outlined,
                        title: 'Aucun résultat pour ces filtres',
                        subtitle: 'Essayez une autre catégorie ou période.',
                      )
                    : ListView.separated(
                        padding: EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.sm,
                            AppSpacing.md, fabSafeBottomPadding(context)),
                        itemCount: filtered.length,
                        separatorBuilder: (_, _) =>
                            const SizedBox(height: AppSpacing.sm),
                        itemBuilder: (context, i) {
                          final e = filtered[i];
                          final isLinked = e.linkedMaintenanceId != null ||
                              e.linkedFuelId != null;
                          final tile = Card(
                            child: ListTile(
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: AppSpacing.md,
                                vertical: AppSpacing.xs,
                              ),
                              leading: Container(
                                width: 38,
                                height: 38,
                                decoration: BoxDecoration(
                                  color: Theme.of(context).colorScheme.primaryContainer,
                                  borderRadius: BorderRadius.circular(11),
                                ),
                                child: Icon(
                                  isLinked
                                      ? Icons.link_outlined
                                      : Icons.payments_outlined,
                                  color: Theme.of(context).colorScheme.primary,
                                  size: 19,
                                ),
                              ),
                              title: Text(
                                e.category,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              subtitle: Text(
                                isLinked
                                    ? '${_fmt(e.date)} • générée automatiquement'
                                    : _fmt(e.date),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              trailing: Text(
                                '${formatAmount(e.amount)} ${e.currency}',
                                style: AppTypography.mono(context,
                                    fontSize: 13, fontWeight: FontWeight.w600),
                              ),
                              onTap: () => _openSource(context, ref, e, vehicleAsync),
                            ),
                          );
                          if (isLinked) {
                            // A generated expense must be edited/deleted from
                            // its source operation, never independently -
                            // otherwise its amount could drift from what
                            // created it.
                            return tile;
                          }
                          return DismissibleDelete(
                            itemKey: ValueKey(e.id),
                            confirmTitle: 'Supprimer cette dépense ?',
                            confirmMessage:
                                '« ${e.category} » du ${_fmt(e.date)} sera '
                                'déplacée dans la corbeille.',
                            onConfirmedDelete: () async {
                              await ref
                                  .read(expenseRepositoryProvider)
                                  .softDelete(e.id);
                              if (context.mounted) {
                                showAppSnackBar(context, 'Dépense supprimée',
                                    icon: Icons.delete_outline);
                              }
                            },
                            child: tile,
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showExpenseFormSheet(context, vehicleId: widget.vehicleId),
        icon: const Icon(Icons.add),
        label: const Text('Ajouter une dépense'),
      ),
    );
  }

  Future<void> _openSource(
    BuildContext context,
    WidgetRef ref,
    Expense expense,
    AsyncValue<Vehicle?> vehicleAsync,
  ) async {
    final vehicle = vehicleAsync.maybeWhen(data: (v) => v, orElse: () => null);
    if (vehicle == null) return;
    if (expense.linkedMaintenanceId != null) {
      final entry = await ref
          .read(maintenanceRepositoryProvider)
          .getById(expense.linkedMaintenanceId!);
      if (entry != null && context.mounted) {
        showMaintenanceFormSheet(
          context,
          vehicleId: widget.vehicleId,
          currentMileage: vehicle.currentMileage,
          editing: entry,
        );
      }
      return;
    }
    if (expense.linkedFuelId != null) {
      final entry =
          await ref.read(fuelRepositoryProvider).getById(expense.linkedFuelId!);
      if (entry != null && context.mounted) {
        showFuelFormSheet(
          context,
          vehicleId: widget.vehicleId,
          currentMileage: vehicle.currentMileage,
          editing: entry,
        );
      }
      return;
    }
    if (context.mounted) {
      showExpenseFormSheet(context, vehicleId: widget.vehicleId, editing: expense);
    }
  }

  String _fmt(DateTime d) => '${d.day}/${d.month}/${d.year}';
}
