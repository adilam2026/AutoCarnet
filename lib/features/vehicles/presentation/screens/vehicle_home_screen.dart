import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/database/database.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/currency_format.dart';
import '../../../../core/utils/feedback.dart';
import '../../../../core/utils/layout.dart';
import '../../../../core/widgets/loading_error_views.dart';
import '../../../../core/widgets/section_header.dart';
import '../../../documents/data/document_repository.dart';
import '../../../documents/presentation/document_form_sheet.dart';
import '../../../documents/presentation/document_status_chip.dart';
import '../../../expenses/data/expense_repository.dart';
import '../../../fuel/data/fuel_repository.dart';
import '../../../maintenance/data/maintenance_repository.dart';
import '../../../maintenance/domain/revision_estimation.dart';
import '../../../maintenance/presentation/maintenance_form_sheet.dart';
import '../../../reminders/data/reminder_repository.dart';
import '../../../reminders/domain/reminder_urgency.dart';
import '../../data/vehicle_repository.dart';
import '../../domain/vehicle_health.dart';
import '../providers/vehicle_form_providers.dart';
import '../widgets/add_operation_sheet.dart';
import '../widgets/health_factors_sheet.dart';
import '../widgets/mileage_update_sheet.dart';
import 'vehicle_edit_screen.dart';

/// The carnet of a single vehicle: a real dashboard, not a near-empty
/// screen - mileage, what needs attention, what was last done, an overview,
/// and the administrative essentials, all built only from data already
/// collected elsewhere (Principe 2). Every module reachable from here
/// (RG-VEH-002: all operations belong to exactly one vehicle) is a
/// full-screen push, never a horizontal tab strip.
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
    final activeReminders =
        ref.watch(vehicleActiveRemindersProvider(vehicle.id)).value ?? const [];
    final expenseStats = ref.watch(vehicleExpenseStatsProvider(vehicle.id));
    final fuelStats = ref.watch(vehicleFuelStatsProvider(vehicle.id));
    final maintenanceEntries =
        ref.watch(vehicleMaintenanceProvider(vehicle.id)).value ?? const [];
    final documents = ref.watch(vehicleDocumentsProvider(vehicle.id)).value ?? const [];
    final driverDocuments = ref.watch(driverDocumentsProvider).value ?? const [];
    final mileageHistory =
        ref.watch(vehicleMileageHistoryProvider(vehicle.id)).value ?? const [];
    final recentOperations = [...maintenanceEntries]..sort((a, b) => b.date.compareTo(a.date));

    final health = computeVehicleHealthScore(
      activeReminders: activeReminders,
      maintenanceEntries: maintenanceEntries,
      documents: documents,
      completeness: completeness,
    );

    final monthlyPace = estimateMonthlyPaceKm(mileageHistory);
    final nextMaintenanceReminder =
        _pickNextMaintenanceReminder(activeReminders, vehicle.currentMileage);
    final revisionEstimate = nextMaintenanceReminder == null
        ? null
        : estimateFromKnownNextDue(
            nextMileage: nextMaintenanceReminder.dueMileage,
            nextDateThreshold: nextMaintenanceReminder.dueDate,
            currentMileage: vehicle.currentMileage,
            monthlyPaceKm: monthlyPace,
          );

    final lastMileageEntry = mileageHistory.isEmpty
        ? null
        : ([...mileageHistory]..sort((a, b) => b.recordedAt.compareTo(a.recordedAt))).first;

    return Scaffold(
      appBar: AppBar(
        title: Row(
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
            Expanded(
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
          _HeaderCard(vehicle: vehicle),
          const SizedBox(height: AppSpacing.sm),
          _MileageCard(
            vehicle: vehicle,
            completeness: completeness,
            lastUpdate: lastMileageEntry?.recordedAt,
            onUpdate: () => showMileageUpdateSheet(context, ref, vehicle),
            onComplete: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => VehicleEditScreen(vehicle: vehicle)),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          const SectionHeader('À faire prochainement'),
          const SizedBox(height: AppSpacing.sm),
          if (revisionEstimate != null) ...[
            _NextRevisionCard(estimate: revisionEstimate, title: nextMaintenanceReminder!.title),
            const SizedBox(height: AppSpacing.sm),
          ],
          _TodoCard(
            reminders: activeReminders,
            currentMileage: vehicle.currentMileage,
            excludeReminderId: revisionEstimate != null ? nextMaintenanceReminder!.id : null,
          ),
          const SizedBox(height: AppSpacing.lg),
          SectionHeader(
            'Dernières opérations',
            trailing: recentOperations.isEmpty
                ? null
                : TextButton(
                    onPressed: () => context.push('/vehicles/${vehicle.id}/timeline'),
                    child: const Text('Voir tout'),
                  ),
          ),
          const SizedBox(height: AppSpacing.sm),
          _RecentOperationsCard(
            entries: recentOperations.take(3).toList(),
            vehicle: vehicle,
          ),
          const SizedBox(height: AppSpacing.lg),
          const SectionHeader('Aperçu'),
          const SizedBox(height: AppSpacing.sm),
          _OverviewGrid(
            maintenanceEntries: maintenanceEntries,
            expenseThisYear: expenseStats.maybeWhen(data: (s) => s.thisYear, orElse: () => null),
            fuelStats: fuelStats.maybeWhen(data: (s) => s, orElse: () => null),
            health: health,
            onTapHealth: () => showHealthFactorsSheet(context, health),
          ),
          const SizedBox(height: AppSpacing.lg),
          const SectionHeader('Administratif'),
          const SizedBox(height: AppSpacing.sm),
          _AdministrativeCard(
            vehicleId: vehicle.id,
            vehicleDocuments: documents,
            driverDocuments: driverDocuments,
          ),
          const SizedBox(height: AppSpacing.lg),
          const SectionHeader('Modules'),
          const SizedBox(height: AppSpacing.sm),
          _ModuleTile(
            icon: Icons.description_outlined,
            label: 'Documents',
            trailingCount: documents.length,
            onTap: () => context.push('/vehicles/${vehicle.id}/documents'),
          ),
          _ModuleTile(
            icon: Icons.build_outlined,
            label: 'Entretiens',
            trailingCount: maintenanceEntries.length,
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
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showAddOperationSheet(context, ref, vehicle: vehicle),
        icon: const Icon(Icons.add),
        label: const Text('Ajouter une opération'),
      ),
    );
  }

  /// Featured reminder for the "prochaine révision" card: the maintenance
  /// reminder that's closest to its threshold, whichever unit (date or
  /// mileage) gets there first.
  Reminder? _pickNextMaintenanceReminder(List<Reminder> reminders, double currentMileage) {
    final candidates = reminders.where((r) => r.sourceType == 'maintenance').toList();
    if (candidates.isEmpty) return null;
    double keyOf(Reminder r) {
      final byDays = r.dueDate?.difference(DateTime.now()).inDays.toDouble();
      final byKm = r.dueMileage != null ? r.dueMileage! - currentMileage : null;
      if (byDays != null && byKm != null) return byDays < byKm ? byDays : byKm;
      return byDays ?? byKm ?? double.infinity;
    }

    candidates.sort((a, b) => keyOf(a).compareTo(keyOf(b)));
    return candidates.first;
  }

  String _statusLabel(VehicleStatus s) => switch (s) {
        VehicleStatus.active => 'Actif',
        VehicleStatus.archived => 'Archivé',
        VehicleStatus.sold => 'Vendu',
        VehicleStatus.destroyed => 'Détruit',
      };
}

class _HeaderCard extends StatelessWidget {
  const _HeaderCard({required this.vehicle});
  final Vehicle vehicle;

  @override
  Widget build(BuildContext context) {
    final subtitleParts = <String>[
      if (vehicle.plate != null) vehicle.plate!,
      if (vehicle.year != null) '${vehicle.year}',
    ];
    if (subtitleParts.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Text(
        subtitleParts.join(' • '),
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
      ),
    );
  }
}

class _MileageCard extends StatelessWidget {
  const _MileageCard({
    required this.vehicle,
    required this.completeness,
    required this.lastUpdate,
    required this.onUpdate,
    required this.onComplete,
  });
  final Vehicle vehicle;
  final double completeness;
  final DateTime? lastUpdate;
  final VoidCallback onUpdate;
  final VoidCallback onComplete;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final completenessPercent = (completeness * 100).round();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${vehicle.currentMileage.toStringAsFixed(0)} km',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 2),
            Text(
              lastUpdate != null
                  ? 'Dernière mise à jour : ${_fmt(lastUpdate!)}'
                  : 'Kilométrage jamais mis à jour',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: AppSpacing.sm),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: onUpdate,
                child: const Text('Mettre à jour le kilométrage'),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(value: completeness, minHeight: 5),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Text('$completenessPercent % complète',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelSmall),
              ],
            ),
            if (completenessPercent < 100) ...[
              const SizedBox(height: AppSpacing.xs),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: onComplete,
                  style: TextButton.styleFrom(padding: EdgeInsets.zero),
                  child: Text('Compléter la fiche', style: TextStyle(color: scheme.primary)),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _fmt(DateTime d) => '${d.day}/${d.month}/${d.year}';
}

class _NextRevisionCard extends StatelessWidget {
  const _NextRevisionCard({required this.estimate, required this.title});
  final RevisionEstimate estimate;
  final String title;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final overdue = estimate.isOverdue;
    final lines = <String>[];
    if (estimate.remainingKm != null) {
      lines.add(overdue && estimate.isOverdueByMileage
          ? 'Dépassée de ${(-estimate.remainingKm!).toStringAsFixed(0)} km'
          : 'Reste ${estimate.remainingKm!.toStringAsFixed(0)} km');
    }
    if (estimate.probableDate != null) {
      final isPastDate =
          estimate.isOverdueByDate && estimate.probableDate == estimate.nextDateByFrequency;
      lines.add(isPastDate
          ? 'Échéance dépassée depuis le ${_fmt(estimate.probableDate!)}'
          : 'Estimation : ${_fmt(estimate.probableDate!)}');
    } else if (estimate.remainingKm != null) {
      lines.add('Ajoutez régulièrement votre kilométrage pour une estimation de date.');
    }
    return Card(
      color: overdue ? scheme.errorContainer.withValues(alpha: 0.5) : null,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              overdue ? Icons.warning_amber_outlined : Icons.event_available_outlined,
              color: overdue ? scheme.error : scheme.primary,
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall),
                  for (final l in lines)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(l, style: Theme.of(context).textTheme.bodySmall),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _fmt(DateTime d) => '${d.day}/${d.month}/${d.year}';
}

class _TodoCard extends StatelessWidget {
  const _TodoCard({
    required this.reminders,
    required this.currentMileage,
    this.excludeReminderId,
  });
  final List<Reminder> reminders;
  final double currentMileage;
  final String? excludeReminderId;

  @override
  Widget build(BuildContext context) {
    final visible = reminders.where((r) => r.id != excludeReminderId).toList()
      ..sort((a, b) {
        double keyOf(Reminder r) {
          final byDays = r.dueDate?.difference(DateTime.now()).inDays.toDouble();
          final byKm = r.dueMileage != null ? r.dueMileage! - currentMileage : null;
          if (byDays != null && byKm != null) return byDays < byKm ? byDays : byKm;
          return byDays ?? byKm ?? double.infinity;
        }
        return keyOf(a).compareTo(keyOf(b));
      });

    if (visible.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Row(
            children: [
              const Icon(Icons.check_circle_outline, color: Colors.green),
              const SizedBox(width: AppSpacing.sm),
              Text('Tout est à jour', style: Theme.of(context).textTheme.bodyMedium),
            ],
          ),
        ),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
        child: Column(
          children: [
            for (final r in visible.take(4))
              Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md, vertical: AppSpacing.xs),
                child: Row(
                  children: [
                    _urgencyDot(context, reminderUrgency(r, currentMileage: currentMileage)),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(
                        '${r.title} — ${_dueLabel(r)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _urgencyDot(BuildContext context, ReminderUrgency u) {
    final color = switch (u) {
      ReminderUrgency.urgent => Theme.of(context).colorScheme.error,
      ReminderUrgency.upcoming => Colors.orange,
      ReminderUrgency.later => Colors.green,
      ReminderUrgency.done => Theme.of(context).colorScheme.outline,
    };
    return Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }

  String _dueLabel(Reminder r) {
    if (r.dueDate != null) {
      final d = r.dueDate!;
      final overdue = d.isBefore(DateTime.now());
      return overdue
          ? 'en retard depuis le ${d.day}/${d.month}/${d.year}'
          : 'le ${d.day}/${d.month}/${d.year}';
    }
    if (r.dueMileage != null) return 'à ${r.dueMileage!.toStringAsFixed(0)} km';
    return '';
  }
}

/// Only real automobile interventions - never vehicle-created, fiche-
/// modifiée or kilométrage-mis-à-jour noise, which belong to the audit
/// trail instead (bloc "historique métier vs journal d'audit").
class _RecentOperationsCard extends ConsumerWidget {
  const _RecentOperationsCard({
    required this.entries,
    required this.vehicle,
  });
  final List<MaintenanceEntry> entries;
  final Vehicle vehicle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (entries.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Text(
            'Aucune opération enregistrée pour l\'instant. Commencez votre '
            'carnet avec votre dernière vidange ou révision.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      );
    }
    return Card(
      child: Column(
        children: [
          for (var i = 0; i < entries.length; i++) ...[
            ListTile(
              dense: true,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 0),
              title: Text(entries[i].category,
                  maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text(
                '${_fmt(entries[i].date)} · ${entries[i].mileage.toStringAsFixed(0)} km',
              ),
              trailing: Text(
                (entries[i].partsCost + entries[i].laborCost) > 0
                    ? '${formatAmount(entries[i].partsCost + entries[i].laborCost)} ${entries[i].currency}'
                    : '',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              onTap: () => showMaintenanceFormSheet(
                context,
                vehicleId: vehicle.id,
                currentMileage: vehicle.currentMileage,
                editing: entries[i],
              ),
            ),
            if (i < entries.length - 1) const Divider(height: 1),
          ],
        ],
      ),
    );
  }

  String _fmt(DateTime d) => '${d.day}/${d.month}/${d.year}';
}

class _OverviewGrid extends StatelessWidget {
  const _OverviewGrid({
    required this.maintenanceEntries,
    required this.expenseThisYear,
    required this.fuelStats,
    required this.health,
    required this.onTapHealth,
  });
  final List<MaintenanceEntry> maintenanceEntries;
  final double? expenseThisYear;
  final FuelStats? fuelStats;
  final VehicleHealthScore health;
  final VoidCallback onTapHealth;

  @override
  Widget build(BuildContext context) {
    // Two content-driven rows (never a fixed aspect ratio) so a tile never
    // overflows when the system font scale is large.
    return Column(
      children: [
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: _OverviewTile(
                  icon: Icons.build_outlined,
                  label: 'Entretien',
                  value: maintenanceEntries.isEmpty
                      ? null
                      : '${([...maintenanceEntries]..sort((a, b) => b.date.compareTo(a.date))).first.mileage.toStringAsFixed(0)} km',
                  emptyMessage: 'Aucun entretien enregistré',
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: _OverviewTile(
                  icon: Icons.payments_outlined,
                  label: 'Dépenses cette année',
                  value: expenseThisYear == null ? null : formatAmount(expenseThisYear!),
                  emptyMessage: 'Pas encore de données',
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: _OverviewTile(
                  icon: Icons.speed_outlined,
                  label: 'Consommation',
                  value: fuelStats?.averageConsumption != null
                      ? '${fuelStats!.averageConsumption!.toStringAsFixed(1)} L/100'
                      : null,
                  emptyMessage: 'Ajoutez 2 pleins complets pour calculer la consommation',
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: _OverviewTile(
                  icon: Icons.favorite_outline,
                  label: 'Santé',
                  value: '${health.score}/100',
                  onTap: onTapHealth,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _OverviewTile extends StatelessWidget {
  const _OverviewTile({
    required this.icon,
    required this.label,
    required this.value,
    this.emptyMessage,
    this.onTap,
  });
  final IconData icon;
  final String label;
  final String? value;
  final String? emptyMessage;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.sm),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 18, color: scheme.onSurfaceVariant),
              const SizedBox(height: 4),
              Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelSmall),
              const SizedBox(height: 2),
              value != null
                  ? Text(
                      value!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                    )
                  : Text(
                      emptyMessage ?? 'Pas de données',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AdministrativeCard extends StatelessWidget {
  const _AdministrativeCard({
    required this.vehicleId,
    required this.vehicleDocuments,
    required this.driverDocuments,
  });
  final String vehicleId;
  final List<DocumentWithVersion> vehicleDocuments;
  final List<DocumentWithVersion> driverDocuments;

  static const _rows = [
    ('Assurance', false),
    ('Visite technique', false),
    ('Vignette', false),
    ('Permis de conduire', true),
  ];

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Column(
        children: [
          for (var i = 0; i < _rows.length; i++) ...[
            _buildRow(context, _rows[i].$1, _rows[i].$2),
            if (i < _rows.length - 1) const Divider(height: 1),
          ],
        ],
      ),
    );
  }

  Widget _buildRow(BuildContext context, String type, bool isDriverDoc) {
    final pool = isDriverDoc ? driverDocuments : vehicleDocuments;
    DocumentWithVersion? match;
    for (final d in pool) {
      if (d.document.type == type) {
        match = d;
        break;
      }
    }
    if (match == null) {
      return ListTile(
        dense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
        leading: const Icon(Icons.add_circle_outline),
        title: Text('Ajouter $type'),
        onTap: () => showDocumentFormSheet(
          context,
          vehicleId: isDriverDoc ? null : vehicleId,
          initialType: type,
        ),
      );
    }
    final expiry = match.version?.expiryDate;
    return ListTile(
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      title: Text(type),
      subtitle: expiry != null
          ? Text('Expire le ${_fmt(expiry)}')
          : const Text('Aucune échéance renseignée'),
      trailing: DocumentStatusChip(status: match.computedStatus),
      onTap: () => showDocumentFormSheet(
        context,
        vehicleId: isDriverDoc ? null : vehicleId,
        renewing: match!.document,
        renewingVersion: match.version,
      ),
    );
  }

  String _fmt(DateTime d) => '${d.day}/${d.month}/${d.year}';
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
