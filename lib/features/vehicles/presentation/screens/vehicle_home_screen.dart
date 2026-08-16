import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/database/database.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/feedback.dart';
import '../../../../core/utils/layout.dart';
import '../../../../core/widgets/loading_error_views.dart';
import '../../../../core/widgets/section_header.dart';
import '../../../../core/widgets/stat_tile.dart';
import '../../../documents/data/document_repository.dart';
import '../../../expenses/data/expense_repository.dart';
import '../../../fuel/data/fuel_repository.dart';
import '../../../maintenance/data/maintenance_repository.dart';
import '../../../reminders/data/reminder_repository.dart';
import '../../data/vehicle_repository.dart';
import '../../domain/vehicle_health.dart';
import '../providers/vehicle_form_providers.dart';
import '../widgets/mileage_update_sheet.dart';
import 'vehicle_edit_screen.dart';

/// The carnet of a single vehicle. Every module reachable from here (RG-VEH-002:
/// all operations belong to exactly one vehicle) is a full-screen push, never
/// a horizontal tab strip - with 6+ modules that scrolls badly and hides
/// state.
class VehicleHomeScreen extends ConsumerWidget {
  const VehicleHomeScreen({super.key, required this.vehicleId});
  final String vehicleId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vehicleAsync = ref.watch(vehicleByIdProvider(vehicleId));

    return vehicleAsync.when(
      loading: () => const Scaffold(body: LoadingView()),
      error: (e, _) => Scaffold(body: ErrorView(message: e.toString())),
      data: (vehicle) => _VehicleHomeBody(vehicle: vehicle),
    );
  }
}

class _VehicleHomeBody extends ConsumerWidget {
  const _VehicleHomeBody({required this.vehicle});
  final Vehicle vehicle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final completeness = ref.watch(vehicleCompletenessProvider(vehicle));
    final remindersAsync = ref.watch(vehicleActiveRemindersProvider(vehicle.id));
    final expenseStatsAsync = ref.watch(vehicleExpenseStatsProvider(vehicle.id));
    final fuelStatsAsync = ref.watch(vehicleFuelStatsProvider(vehicle.id));
    final maintenanceAsync = ref.watch(vehicleMaintenanceProvider(vehicle.id));
    final documentsAsync = ref.watch(vehicleDocumentsProvider(vehicle.id));

    final health = remindersAsync.maybeWhen(
      data: computeVehicleHealth,
      orElse: () => VehicleHealth.good,
    );

    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Hero(
              tag: 'vehicle-avatar-${vehicle.id}',
              child: CircleAvatar(
                radius: 14,
                backgroundColor: scheme.primaryContainer,
                child: Icon(Icons.directions_car, size: 16, color: scheme.primary),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Flexible(
              child: Text(
                '${vehicle.brand} ${vehicle.model}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        actions: [
          PopupMenuButton<VehicleStatus>(
            tooltip: 'Statut du véhicule',
            icon: _StatusIndicator(status: vehicle.status),
            onSelected: (status) async {
              await ref.read(vehicleRepositoryProvider).setStatus(vehicle.id, status);
              if (context.mounted) {
                showAppSnackBar(
                  context,
                  'Statut mis à jour : ${_statusLabel(status)}',
                  icon: Icons.check_circle_outline,
                );
              }
            },
            itemBuilder: (context) => [
              for (final status in VehicleStatus.values)
                PopupMenuItem(
                  value: status,
                  child: Row(
                    children: [
                      if (status == vehicle.status)
                        const Padding(
                          padding: EdgeInsets.only(right: 8),
                          child: Icon(Icons.check, size: 18),
                        )
                      else
                        const SizedBox(width: 26),
                      Text(_statusLabel(status)),
                    ],
                  ),
                ),
            ],
          ),
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            tooltip: 'Modifier la fiche',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => VehicleEditScreen(vehicle: vehicle)),
            ),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: ListView(
        padding: EdgeInsets.fromLTRB(
          AppSpacing.md, AppSpacing.md, AppSpacing.md, fabSafeBottomPadding(context)),
        children: [
          // Compact status row: mileage, health, completeness - no big
          // decorative card, the space serves information (item 6).
          Card(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      _HealthDot(health: health),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Text(
                          '${vehicle.currentMileage.toStringAsFixed(0)} km',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                      ),
                      OutlinedButton(
                        onPressed: () => showMileageUpdateSheet(context, ref, vehicle),
                        child: const Text('Mettre à jour'),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Row(
                    children: [
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: completeness,
                            minHeight: 5,
                          ),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Text(
                        '${(completeness * 100).round()} % complète',
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          remindersAsync.maybeWhen(
            data: (reminders) => reminders.isEmpty
                ? const SizedBox.shrink()
                : Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.sm),
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
                            for (final r in reminders.take(3))
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
          const SizedBox(height: AppSpacing.lg),
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
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          const SectionHeader('Modules'),
          const SizedBox(height: AppSpacing.sm),
          _ModuleTile(
            icon: Icons.description_outlined,
            label: 'Documents',
            trailingCount: documentsAsync.maybeWhen(
              data: (d) => d.length,
              orElse: () => null,
            ),
            onTap: () => context.push('/vehicles/${vehicle.id}/documents'),
          ),
          _ModuleTile(
            icon: Icons.build_outlined,
            label: 'Entretiens',
            trailingCount: maintenanceAsync.maybeWhen(
              data: (m) => m.length,
              orElse: () => null,
            ),
            onTap: () => context.push('/vehicles/${vehicle.id}/maintenance'),
          ),
          _ModuleTile(
            icon: Icons.payments_outlined,
            label: 'Dépenses',
            onTap: () => context.push('/vehicles/${vehicle.id}/expenses'),
          ),
          _ModuleTile(
            icon: Icons.local_gas_station_outlined,
            label: 'Carburant',
            onTap: () => context.push('/vehicles/${vehicle.id}/fuel'),
          ),
          _ModuleTile(
            icon: Icons.timeline_outlined,
            label: 'Timeline',
            onTap: () => context.push('/vehicles/${vehicle.id}/timeline'),
          ),
        ],
      ),
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

  String _statusLabel(VehicleStatus s) => switch (s) {
        VehicleStatus.active => 'Actif',
        VehicleStatus.archived => 'Archivé',
        VehicleStatus.sold => 'Vendu',
        VehicleStatus.destroyed => 'Détruit',
      };
}

class _ModuleTile extends StatelessWidget {
  const _ModuleTile({
    required this.icon,
    required this.label,
    required this.onTap,
    this.trailingCount,
  });
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final int? trailingCount;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: Card(
        child: ListTile(
          leading: CircleAvatar(
            backgroundColor: scheme.primaryContainer.withValues(alpha: 0.6),
            child: Icon(icon, color: scheme.primary, size: 20),
          ),
          title: Text(label),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (trailingCount != null && trailingCount! > 0)
                Padding(
                  padding: const EdgeInsets.only(right: AppSpacing.xs),
                  child: Text(
                    '$trailingCount',
                    style: Theme.of(context).textTheme.labelMedium,
                  ),
                ),
              const Icon(Icons.chevron_right),
            ],
          ),
          onTap: onTap,
        ),
      ),
    );
  }
}

class _HealthDot extends StatelessWidget {
  const _HealthDot({required this.health});
  final VehicleHealth health;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = switch (health) {
      VehicleHealth.good => scheme.primary,
      VehicleHealth.attention => scheme.tertiary,
      VehicleHealth.critical => scheme.error,
    };
    return Tooltip(
      message: switch (health) {
        VehicleHealth.good => 'Aucune échéance urgente',
        VehicleHealth.attention => 'Échéance proche',
        VehicleHealth.critical => 'Échéance dépassée',
      },
      child: Container(
        width: 12,
        height: 12,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
    );
  }
}

class _StatusIndicator extends StatelessWidget {
  const _StatusIndicator({required this.status});
  final VehicleStatus status;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = switch (status) {
      VehicleStatus.active => scheme.primary,
      VehicleStatus.archived => scheme.outline,
      VehicleStatus.sold => scheme.tertiary,
      VehicleStatus.destroyed => scheme.error,
    };
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(color: color.withValues(alpha: 0.15), shape: BoxShape.circle),
      child: Icon(Icons.circle, size: 10, color: color),
    );
  }
}
