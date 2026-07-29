import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../vehicles/data/vehicle_repository.dart';
import '../data/fuel_repository.dart';
import 'fuel_form_sheet.dart';

class FuelTab extends ConsumerWidget {
  const FuelTab({super.key, required this.vehicleId});
  final String vehicleId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entriesAsync = ref.watch(vehicleFuelEntriesProvider(vehicleId));
    final statsAsync = ref.watch(vehicleFuelStatsProvider(vehicleId));
    final vehicleAsync = ref.watch(vehicleByIdProvider(vehicleId));

    return Scaffold(
      body: entriesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Erreur : $e')),
        data: (entries) {
          return CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: statsAsync.maybeWhen(
                    data: (stats) => Card(
                      child: Padding(
                        padding: const EdgeInsets.all(AppSpacing.md),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                          children: [
                            _Stat(
                              label: 'Conso. moyenne',
                              value: stats.averageConsumption != null
                                  ? '${stats.averageConsumption!.toStringAsFixed(1)} L/100km'
                                  : '—',
                            ),
                            _Stat(
                              label: 'Total litres',
                              value: '${stats.totalLiters.toStringAsFixed(0)} L',
                            ),
                            _Stat(
                              label: 'Total dépensé',
                              value: stats.totalCost.toStringAsFixed(0),
                            ),
                          ],
                        ),
                      ),
                    ),
                    orElse: () => const SizedBox.shrink(),
                  ),
                ),
              ),
              if (entries.isEmpty)
                const SliverFillRemaining(
                  child: Center(child: Text('Aucun plein enregistré')),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.md, vertical: AppSpacing.sm),
                  sliver: SliverList.separated(
                    itemCount: entries.length,
                    separatorBuilder: (_, _) =>
                        const SizedBox(height: AppSpacing.sm),
                    itemBuilder: (context, i) {
                      final f = entries[i];
                      return Card(
                        child: ListTile(
                          title: Text(
                              '${f.quantityLiters.toStringAsFixed(1)} L — ${f.fuelType}'),
                          subtitle: Text(
                            '${_fmt(f.date)} • ${f.mileage.toStringAsFixed(0)} km'
                            '${f.isFullTank ? '' : ' • partiel'}',
                          ),
                          trailing: Text(f.totalAmount.toStringAsFixed(0)),
                        ),
                      );
                    },
                  ),
                ),
            ],
          );
        },
      ),
      floatingActionButton: vehicleAsync.maybeWhen(
        data: (vehicle) => FloatingActionButton(
          onPressed: () => showFuelFormSheet(
            context,
            vehicleId: vehicleId,
            currentMileage: vehicle.currentMileage,
          ),
          child: const Icon(Icons.add),
        ),
        orElse: () => null,
      ),
    );
  }

  String _fmt(DateTime d) => '${d.day}/${d.month}/${d.year}';
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(value, style: Theme.of(context).textTheme.titleMedium),
        Text(label, style: Theme.of(context).textTheme.labelSmall),
      ],
    );
  }
}
