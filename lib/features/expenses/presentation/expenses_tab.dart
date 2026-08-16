import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/feedback.dart';
import '../../../core/utils/layout.dart';
import '../../../core/widgets/dismissible_delete.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/loading_error_views.dart';
import '../../../core/widgets/stat_tile.dart';
import '../data/expense_repository.dart';
import 'expense_form_sheet.dart';

/// Strictly scoped to a single vehicle (RG-DEP-003): the stats and list here
/// never mix data across vehicles, by construction of the providers below.
class ExpensesTab extends ConsumerWidget {
  const ExpensesTab({super.key, required this.vehicleId});
  final String vehicleId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final expensesAsync = ref.watch(vehicleExpensesProvider(vehicleId));
    final statsAsync = ref.watch(vehicleExpenseStatsProvider(vehicleId));
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
              onAction: () => showExpenseFormSheet(context, vehicleId: vehicleId),
            );
          }
          return CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: statsAsync.maybeWhen(
                    data: (stats) => StatTileRow(
                      tiles: [
                        StatTile(
                          label: 'Ce mois',
                          value: stats.thisMonth.toStringAsFixed(0),
                          icon: Icons.calendar_today_outlined,
                        ),
                        StatTile(
                          label: 'Cette année',
                          value: stats.thisYear.toStringAsFixed(0),
                          icon: Icons.event_outlined,
                        ),
                        StatTile(
                          label: 'Total',
                          value: stats.totalAll.toStringAsFixed(0),
                          icon: Icons.summarize_outlined,
                          highlight: true,
                        ),
                      ],
                    ),
                    orElse: () => const SizedBox.shrink(),
                  ),
                ),
              ),
              SliverPadding(
                padding: EdgeInsets.fromLTRB(
                  AppSpacing.md, AppSpacing.sm, AppSpacing.md, fabSafeBottomPadding(context)),
                sliver: SliverList.separated(
                  itemCount: expenses.length,
                  separatorBuilder: (_, _) =>
                      const SizedBox(height: AppSpacing.sm),
                  itemBuilder: (context, i) {
                    final e = expenses[i];
                    return DismissibleDelete(
                      itemKey: ValueKey(e.id),
                      confirmTitle: 'Supprimer cette dépense ?',
                      confirmMessage:
                          '« ${e.category} » du ${_fmt(e.date)} sera '
                          'déplacée dans la corbeille.',
                      onConfirmedDelete: () async {
                        await ref.read(expenseRepositoryProvider).softDelete(e.id);
                        if (context.mounted) {
                          showAppSnackBar(context, 'Dépense supprimée',
                              icon: Icons.delete_outline);
                        }
                      },
                      child: Card(
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.md,
                            vertical: AppSpacing.xs,
                          ),
                          leading: CircleAvatar(
                            backgroundColor: Theme.of(context)
                                .colorScheme
                                .primaryContainer
                                .withValues(alpha: 0.6),
                            child: Icon(
                              Icons.payments_outlined,
                              color: Theme.of(context).colorScheme.primary,
                              size: 20,
                            ),
                          ),
                          title: Text(
                            e.category,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(_fmt(e.date)),
                          trailing: Text(
                            '${e.amount.toStringAsFixed(0)} ${e.currency}',
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => showExpenseFormSheet(context, vehicleId: vehicleId),
        child: const Icon(Icons.add),
      ),
    );
  }

  String _fmt(DateTime d) => '${d.day}/${d.month}/${d.year}';
}
