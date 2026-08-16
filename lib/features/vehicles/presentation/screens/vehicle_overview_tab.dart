import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/database/database.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/section_header.dart';
import '../../../../core/widgets/stat_tile.dart';
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
    final scheme = Theme.of(context).colorScheme;
    final completeness = ref.watch(vehicleCompletenessProvider(vehicle));
    final remindersAsync = ref.watch(vehicleActiveRemindersProvider(vehicle.id));
    final expenseStatsAsync = ref.watch(vehicleExpenseStatsProvider(vehicle.id));
    final fuelStatsAsync = ref.watch(vehicleFuelStatsProvider(vehicle.id));
    final maintenanceAsync = ref.watch(vehicleMaintenanceProvider(vehicle.id));

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md, AppSpacing.md, AppSpacing.md, 96),
      children: [
        Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                scheme.primary,
                scheme.primary.withValues(alpha: 0.75),
              ],
            ),
            borderRadius: BorderRadius.circular(AppRadius.lg),
          ),
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Hero(
                    tag: 'vehicle-avatar-${vehicle.id}',
                    child: CircleAvatar(
                      radius: 22,
                      backgroundColor: scheme.onPrimary.withValues(alpha: 0.15),
                      child: Icon(Icons.directions_car, color: scheme.onPrimary),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      '${vehicle.brand} ${vehicle.model}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: scheme.onPrimary,
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Kilométrage',
                          style: TextStyle(
                            color: scheme.onPrimary.withValues(alpha: 0.8),
                            fontWeight: FontWeight.w500,
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${vehicle.currentMileage.toStringAsFixed(0)} km',
                          style: TextStyle(
                            color: scheme.onPrimary,
                            fontWeight: FontWeight.w800,
                            fontSize: 28,
                            letterSpacing: -0.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  FilledButton.tonal(
                    onPressed: () => showMileageUpdateSheet(context, ref, vehicle),
                    child: const Text('Mettre à jour'),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: completeness,
                  minHeight: 6,
                  backgroundColor: scheme.onPrimary.withValues(alpha: 0.25),
                  valueColor: AlwaysStoppedAnimation(scheme.onPrimary),
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'Fiche complétée à ${(completeness * 100).round()} %',
                style: TextStyle(
                  color: scheme.onPrimary.withValues(alpha: 0.85),
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        remindersAsync.maybeWhen(
          data: (reminders) => reminders.isEmpty
              ? const SizedBox.shrink()
              : Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.lg),
                  child: Card(
                    color: scheme.tertiaryContainer,
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpacing.md),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.notifications_active_outlined,
                                  size: 18, color: scheme.onTertiaryContainer),
                              const SizedBox(width: AppSpacing.sm),
                              Text(
                                'Échéances à venir',
                                style: Theme.of(context)
                                    .textTheme
                                    .titleSmall
                                    ?.copyWith(color: scheme.onTertiaryContainer),
                              ),
                            ],
                          ),
                          const SizedBox(height: AppSpacing.sm),
                          for (final r in reminders.take(5))
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 2),
                              child: Text(
                                '•  ${_reminderLabel(r)}',
                                style: TextStyle(color: scheme.onTertiaryContainer),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
          orElse: () => const SizedBox.shrink(),
        ),
        const SectionHeader('Aperçu'),
        const SizedBox(height: AppSpacing.sm),
        StatTileRow(
          tiles: [
            StatTile(
              label: 'Dépenses / mois',
              icon: Icons.payments_outlined,
              value: expenseStatsAsync.maybeWhen(
                data: (s) => s.thisMonth.toStringAsFixed(0),
                orElse: () => '—',
              ),
            ),
            StatTile(
              label: 'Conso. moyenne',
              icon: Icons.speed_outlined,
              value: fuelStatsAsync.maybeWhen(
                data: (s) => s.averageConsumption != null
                    ? '${s.averageConsumption!.toStringAsFixed(1)} L/100'
                    : '—',
                orElse: () => '—',
              ),
            ),
            StatTile(
              label: 'Entretiens',
              icon: Icons.build_outlined,
              value: maintenanceAsync.maybeWhen(
                data: (l) => '${l.length}',
                orElse: () => '—',
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
