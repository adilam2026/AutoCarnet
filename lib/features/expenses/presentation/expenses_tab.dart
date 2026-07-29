import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../data/expense_repository.dart';
import 'expense_form_sheet.dart';

class ExpensesTab extends ConsumerWidget {
  const ExpensesTab({super.key, required this.vehicleId});
  final String vehicleId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final expensesAsync = ref.watch(vehicleExpensesProvider(vehicleId));
    final statsAsync = ref.watch(vehicleExpenseStatsProvider(vehicleId));
    return Scaffold(
      body: expensesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Erreur : $e')),
        data: (expenses) {
          return CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: statsAsync.maybeWhen(
                    data: (stats) => Row(
                      children: [
                        Expanded(
                          child: _StatCard(
                            label: 'Ce mois',
                            value: stats.thisMonth,
                          ),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: _StatCard(
                            label: 'Cette année',
                            value: stats.thisYear,
                          ),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: _StatCard(label: 'Total', value: stats.totalAll),
                        ),
                      ],
                    ),
                    orElse: () => const SizedBox.shrink(),
                  ),
                ),
              ),
              if (expenses.isEmpty)
                const SliverFillRemaining(
                  child: Center(child: Text('Aucune dépense enregistrée')),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.md, vertical: AppSpacing.sm),
                  sliver: SliverList.separated(
                    itemCount: expenses.length,
                    separatorBuilder: (_, _) =>
                        const SizedBox(height: AppSpacing.sm),
                    itemBuilder: (context, i) {
                      final e = expenses[i];
                      return Card(
                        child: ListTile(
                          title: Text(e.category),
                          subtitle: Text(_fmt(e.date)),
                          trailing: Text(
                            '${e.amount.toStringAsFixed(0)} ${e.currency}',
                            style: const TextStyle(fontWeight: FontWeight.bold),
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

class _StatCard extends StatelessWidget {
  const _StatCard({required this.label, required this.value});
  final String label;
  final double value;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: Theme.of(context).textTheme.labelMedium),
            const SizedBox(height: AppSpacing.xs),
            Text(
              value.toStringAsFixed(0),
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ],
        ),
      ),
    );
  }
}
