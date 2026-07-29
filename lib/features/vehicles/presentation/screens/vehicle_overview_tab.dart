import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/database/database.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../expenses/data/expense_repository.dart';
import '../../../fuel/data/fuel_repository.dart';
import '../../../maintenance/data/maintenance_repository.dart';
import '../../../reminders/data/reminder_repository.dart';
import '../providers/vehicle_form_providers.dart';
import '../widgets/mileage_update_sheet.dart';

/// Reads-only aggregation of other modules (RG-DASH-001/002): this screen
/// owns no data of its own.
class VehicleOverviewTab extends ConsumerWidget {
  const VehicleOverviewTab({super.key, required this.vehicle});
  final Vehicle vehicle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final completeness = ref.watch(vehicleCompletenessProvider(vehicle));
    final remindersAsync = ref.watch(vehicleActiveRemindersProvider(vehicle.id));
    final expenseStatsAsync = ref.watch(vehicleExpenseStatsProvider(vehicle.id));
    final fuelStatsAsync = ref.watch(vehicleFuelStatsProvider(vehicle.id));
    final maintenanceAsync = ref.watch(vehicleMaintenanceProvider(vehicle.id));

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.md),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${vehicle.currentMileage.toStringAsFixed(0)} km',
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                    ),
                    OutlinedButton(
                      onPressed: () =>
                          showMileageUpdateSheet(context, ref, vehicle),
                      child: const Text('Mettre à jour'),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                LinearProgressIndicator(value: completeness),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'Fiche complétée à ${(completeness * 100).round()} %',
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        remindersAsync.maybeWhen(
          data: (reminders) => reminders.isEmpty
              ? const SizedBox.shrink()
              : Card(
                  color: Theme.of(context).colorScheme.tertiaryContainer,
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Échéances à venir',
                            style: Theme.of(context).textTheme.titleSmall),
                        const SizedBox(height: AppSpacing.sm),
                        for (final r in reminders.take(5))
                          Padding(
                            padding:
                                const EdgeInsets.symmetric(vertical: 2),
                            child: Text('• ${_reminderLabel(r)}'),
                          ),
                      ],
                    ),
                  ),
                ),
          orElse: () => const SizedBox.shrink(),
        ),
        const SizedBox(height: AppSpacing.md),
        Row(
          children: [
            Expanded(
              child: _KpiCard(
                label: 'Dépenses / mois',
                value: expenseStatsAsync.maybeWhen(
                  data: (s) => s.thisMonth.toStringAsFixed(0),
                  orElse: () => '—',
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: _KpiCard(
                label: 'Conso. moyenne',
                value: fuelStatsAsync.maybeWhen(
                  data: (s) => s.averageConsumption != null
                      ? '${s.averageConsumption!.toStringAsFixed(1)} L/100'
                      : '—',
                  orElse: () => '—',
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: _KpiCard(
                label: 'Entretiens',
                value: maintenanceAsync.maybeWhen(
                  data: (l) => '${l.length}',
                  orElse: () => '—',
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  String _reminderLabel(Reminder r) {
    if (r.dueDate != null) {
      final d = r.dueDate!;
      return '${r.title} — ${d.day}/${d.month}/${d.year}';
    }
    if (r.dueMileage != null) {
      return '${r.title} — ${r.dueMileage!.toStringAsFixed(0)} km';
    }
    return r.title;
  }
}

class _KpiCard extends StatelessWidget {
  const _KpiCard({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(value, style: Theme.of(context).textTheme.titleMedium),
            Text(label, style: Theme.of(context).textTheme.labelSmall),
          ],
        ),
      ),
    );
  }
}
