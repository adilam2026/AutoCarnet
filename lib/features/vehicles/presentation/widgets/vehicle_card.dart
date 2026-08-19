import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/database/database.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../account/data/account_repository.dart';
import '../../../reminders/data/reminder_repository.dart';
import '../../../reminders/domain/reminder_urgency.dart';
import '../../domain/vehicle_ownership.dart';

class VehicleCard extends ConsumerWidget {
  const VehicleCard({super.key, required this.vehicle, required this.onTap});
  final Vehicle vehicle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final remindersAsync = ref.watch(vehicleActiveRemindersProvider(vehicle.id));
    final isInactive = vehicle.status != VehicleStatus.active;
    final reminders = remindersAsync.value ?? const <Reminder>[];
    ref.watch(authStateChangesProvider);
    final currentUserId = ref.read(accountRepositoryProvider).currentUser?.id;
    final isShared = !isVehicleOwnedByCurrentUser(vehicle, currentUserId);

    final worstUrgency = reminders.isEmpty
        ? null
        : reminders
            .map((r) => reminderUrgency(r, currentMileage: vehicle.currentMileage))
            .reduce((a, b) => _worse(a, b));
    final nextMaintenance = _nextMaintenanceSummary(reminders, vehicle.currentMileage);

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Row(
            children: [
              Hero(
                tag: 'vehicle-avatar-${vehicle.id}',
                child: CircleAvatar(
                  radius: 28,
                  backgroundColor: scheme.primaryContainer,
                  child: Icon(
                    Icons.directions_car,
                    color: scheme.onPrimaryContainer,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            '${vehicle.brand} ${vehicle.model}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ),
                        if (isShared) ...[
                          const SizedBox(width: AppSpacing.xs),
                          Tooltip(
                            message: 'Partagé avec moi',
                            child: Icon(Icons.people_alt_outlined, size: 14, color: scheme.onSurfaceVariant),
                          ),
                        ],
                        if (isInactive) ...[
                          const SizedBox(width: AppSpacing.xs),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: scheme.surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              _statusLabel(vehicle.status),
                              style: Theme.of(context).textTheme.labelSmall,
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${vehicle.currentMileage.toStringAsFixed(0)} km'
                      '${vehicle.plate != null ? ' • ${vehicle.plate}' : ''}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    if (!isInactive) ...[
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          _urgencyDot(worstUrgency),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              nextMaintenance ?? _urgencyLabel(worstUrgency),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.labelSmall,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              if (reminders.isNotEmpty)
                Badge(
                  label: Text('${reminders.length}'),
                  child: Icon(
                    Icons.notifications_outlined,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              const SizedBox(width: AppSpacing.xs),
              Icon(Icons.chevron_right, color: scheme.outline),
            ],
          ),
        ),
      ),
    );
  }

  ReminderUrgency _worse(ReminderUrgency a, ReminderUrgency b) {
    const order = {
      ReminderUrgency.urgent: 0,
      ReminderUrgency.upcoming: 1,
      ReminderUrgency.later: 2,
      ReminderUrgency.done: 3,
    };
    return order[a]! <= order[b]! ? a : b;
  }

  Widget _urgencyDot(ReminderUrgency? u) {
    final color = switch (u) {
      null => Colors.green,
      ReminderUrgency.urgent => Colors.red,
      ReminderUrgency.upcoming => Colors.orange,
      ReminderUrgency.later => Colors.green,
      ReminderUrgency.done => Colors.green,
    };
    return Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }

  String _urgencyLabel(ReminderUrgency? u) => switch (u) {
        null => 'À jour',
        ReminderUrgency.urgent => 'Action nécessaire',
        ReminderUrgency.upcoming => 'À surveiller',
        ReminderUrgency.later => 'À jour',
        ReminderUrgency.done => 'À jour',
      };

  String? _nextMaintenanceSummary(List<Reminder> reminders, double currentMileage) {
    final maintenanceReminders = reminders.where((r) => r.sourceType == 'maintenance');
    if (maintenanceReminders.isEmpty) return null;
    Reminder best = maintenanceReminders.first;
    double keyOf(Reminder r) {
      final byDays = r.dueDate?.difference(DateTime.now()).inDays.toDouble();
      final byKm = r.dueMileage != null ? r.dueMileage! - currentMileage : null;
      if (byDays != null && byKm != null) return byDays < byKm ? byDays : byKm;
      return byDays ?? byKm ?? double.infinity;
    }

    for (final r in maintenanceReminders) {
      if (keyOf(r) < keyOf(best)) best = r;
    }
    if (best.dueMileage != null) {
      final remaining = best.dueMileage! - currentMileage;
      return remaining <= 0
          ? 'Révision dépassée de ${(-remaining).toStringAsFixed(0)} km'
          : 'Prochaine révision : ${remaining.toStringAsFixed(0)} km';
    }
    if (best.dueDate != null) {
      final d = best.dueDate!;
      final overdue = d.isBefore(DateTime.now());
      return overdue
          ? 'Révision en retard'
          : 'Prochaine révision : ${d.day}/${d.month}/${d.year}';
    }
    return null;
  }

  String _statusLabel(VehicleStatus s) => switch (s) {
        VehicleStatus.active => 'Actif',
        VehicleStatus.archived => 'Archivé',
        VehicleStatus.sold => 'Vendu',
        VehicleStatus.destroyed => 'Détruit',
      };
}
