import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/database/database.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/layout.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/loading_error_views.dart';
import '../../reminders/data/reminder_repository.dart';
import '../../reminders/domain/reminder_urgency.dart';
import '../../vehicles/data/vehicle_repository.dart';

/// Cross-vehicle view of every reminder (bloc 12, §15.11) - the dashboard
/// used to bury this inside each vehicle; now it's a first-class
/// destination so nothing gets missed across a multi-vehicle garage.
class AlertsBody extends ConsumerStatefulWidget {
  const AlertsBody({super.key});

  @override
  ConsumerState<AlertsBody> createState() => _AlertsBodyState();
}

class _AlertsBodyState extends ConsumerState<AlertsBody> {
  ReminderUrgency? _urgencyFilter;
  String? _vehicleFilter;

  @override
  Widget build(BuildContext context) {
    final remindersAsync = ref.watch(allRemindersProvider);
    final vehiclesAsync = ref.watch(vehiclesListProvider);

    return remindersAsync.when(
      loading: () => const LoadingView(),
      error: (e, _) => ErrorView(message: e.toString()),
      data: (reminders) {
        if (reminders.isEmpty) {
          return const EmptyState(
            icon: Icons.notifications_none_outlined,
            title: 'Aucune échéance à venir',
            subtitle:
                'Les documents à renouveler et les entretiens prévus '
                'apparaîtront ici, tous véhicules confondus.',
          );
        }
        final vehicles = vehiclesAsync.maybeWhen(
          data: (v) => {for (final vehicle in v) vehicle.id: vehicle},
          orElse: () => <String, Vehicle>{},
        );
        // Default view: hide handled reminders unless "Traitées" is picked.
        final urgencyOf = {
          for (final r in reminders)
            r.id: reminderUrgency(r,
                currentMileage: vehicles[r.vehicleId]?.currentMileage),
        };
        final filtered = reminders.where((r) {
          final urgency = urgencyOf[r.id]!;
          if (_urgencyFilter == null) {
            if (urgency == ReminderUrgency.done) return false;
          } else if (urgency != _urgencyFilter) {
            return false;
          }
          if (_vehicleFilter != null && r.vehicleId != _vehicleFilter) {
            return false;
          }
          return true;
        }).toList()
          ..sort((a, b) {
            final da = a.dueDate ?? DateTime(2100);
            final db = b.dueDate ?? DateTime(2100);
            return da.compareTo(db);
          });

        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  AppSpacing.md, AppSpacing.md, AppSpacing.md, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        ChoiceChip(
                          label: const Text('En cours'),
                          selected: _urgencyFilter == null,
                          onSelected: (_) => setState(() => _urgencyFilter = null),
                        ),
                        const SizedBox(width: 8),
                        ChoiceChip(
                          label: const Text('Urgent'),
                          selected: _urgencyFilter == ReminderUrgency.urgent,
                          onSelected: (_) =>
                              setState(() => _urgencyFilter = ReminderUrgency.urgent),
                        ),
                        const SizedBox(width: 8),
                        ChoiceChip(
                          label: const Text('À surveiller'),
                          selected: _urgencyFilter == ReminderUrgency.upcoming,
                          onSelected: (_) => setState(
                              () => _urgencyFilter = ReminderUrgency.upcoming),
                        ),
                        const SizedBox(width: 8),
                        ChoiceChip(
                          label: const Text('À venir'),
                          selected: _urgencyFilter == ReminderUrgency.later,
                          onSelected: (_) =>
                              setState(() => _urgencyFilter = ReminderUrgency.later),
                        ),
                        const SizedBox(width: 8),
                        ChoiceChip(
                          label: const Text('Traitées'),
                          selected: _urgencyFilter == ReminderUrgency.done,
                          onSelected: (_) =>
                              setState(() => _urgencyFilter = ReminderUrgency.done),
                        ),
                      ],
                    ),
                  ),
                  if (vehicles.length > 1) ...[
                    const SizedBox(height: AppSpacing.sm),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          ChoiceChip(
                            label: const Text('Tous les véhicules'),
                            selected: _vehicleFilter == null,
                            onSelected: (_) =>
                                setState(() => _vehicleFilter = null),
                          ),
                          const SizedBox(width: 8),
                          for (final v in vehicles.values) ...[
                            ChoiceChip(
                              label: Text('${v.brand} ${v.model}'),
                              selected: _vehicleFilter == v.id,
                              onSelected: (_) =>
                                  setState(() => _vehicleFilter = v.id),
                            ),
                            const SizedBox(width: 8),
                          ],
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Expanded(
              child: filtered.isEmpty
                  ? const EmptyState(
                      icon: Icons.filter_alt_off_outlined,
                      title: 'Aucun résultat pour ces filtres',
                      subtitle: 'Essayez un autre filtre.',
                    )
                  : ListView.separated(
                      padding: EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.md,
                          AppSpacing.md, fabSafeBottomPadding(context)),
                      itemCount: filtered.length,
                      separatorBuilder: (_, _) =>
                          const SizedBox(height: AppSpacing.sm),
                      itemBuilder: (context, i) {
                        final r = filtered[i];
                        final urgency = urgencyOf[r.id]!;
                        final vehicle = vehicles[r.vehicleId];
                        final scheme = Theme.of(context).colorScheme;
                        return Card(
                          child: ListTile(
                            onTap: vehicle != null
                                ? () => context.push('/vehicles/${vehicle.id}')
                                : null,
                            leading: CircleAvatar(
                              backgroundColor: _urgencyColor(scheme, urgency)
                                  .withValues(alpha: 0.18),
                              child: Icon(
                                _urgencyIcon(urgency),
                                color: _urgencyColor(scheme, urgency),
                                size: 20,
                              ),
                            ),
                            title: Text(r.title,
                                maxLines: 1, overflow: TextOverflow.ellipsis),
                            subtitle: Text(
                              [
                                if (vehicle != null) '${vehicle.brand} ${vehicle.model}',
                                _dueLabel(r),
                              ].join(' • '),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            trailing: const Icon(Icons.chevron_right),
                          ),
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }

  Color _urgencyColor(ColorScheme scheme, ReminderUrgency u) => switch (u) {
        ReminderUrgency.urgent => scheme.error,
        ReminderUrgency.upcoming => Colors.orange,
        ReminderUrgency.later => Colors.green,
        ReminderUrgency.done => scheme.outline,
      };

  IconData _urgencyIcon(ReminderUrgency u) => switch (u) {
        ReminderUrgency.urgent => Icons.warning_amber_outlined,
        ReminderUrgency.upcoming => Icons.schedule_outlined,
        ReminderUrgency.later => Icons.notifications_outlined,
        ReminderUrgency.done => Icons.check_circle_outline,
      };

  String _dueLabel(Reminder r) {
    if (r.dueDate != null) {
      final d = r.dueDate!;
      final overdue = d.isBefore(DateTime.now());
      return overdue
          ? 'En retard depuis le ${d.day}/${d.month}/${d.year}'
          : '${d.day}/${d.month}/${d.year}';
    }
    if (r.dueMileage != null) return '${r.dueMileage!.toStringAsFixed(0)} km';
    return '';
  }
}
