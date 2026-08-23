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
import 'widgets/vehicle_hero_card.dart' show formatReminderDue;

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
      error: (e, _) =>
          const ErrorView(message: 'Impossible de charger ces données. Réessayez dans un instant.'),
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
                        return _AlertTile(
                          reminder: r,
                          vehicle: vehicle,
                          urgency: urgency,
                          onTap: vehicle != null
                              ? () => context.push('/vehicles/${vehicle.id}')
                              : null,
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }

}

/// Same rail-coloured tile language as the home dashboard's "À faire" list
/// and the fiche véhicule's reminder tiles - one consistent way to show a
/// reminder anywhere in the app.
class _AlertTile extends StatelessWidget {
  const _AlertTile({
    required this.reminder,
    required this.vehicle,
    required this.urgency,
    required this.onTap,
  });
  final Reminder reminder;
  final Vehicle? vehicle;
  final ReminderUrgency urgency;
  final VoidCallback? onTap;

  Color _railColor(ColorScheme scheme) => switch (urgency) {
        ReminderUrgency.urgent => scheme.error,
        ReminderUrgency.upcoming => scheme.secondary,
        ReminderUrgency.later => scheme.tertiary,
        ReminderUrgency.done => scheme.outline,
      };

  IconData get _icon => switch (urgency) {
        ReminderUrgency.urgent => Icons.warning_amber_outlined,
        ReminderUrgency.upcoming => Icons.schedule_outlined,
        ReminderUrgency.later => Icons.notifications_outlined,
        ReminderUrgency.done => Icons.check_circle_outline,
      };

  /// Fallback for the rare sync-lag case where the reminder's vehicle
  /// isn't locally known yet - formatReminderDue needs a real currentMileage.
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

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final railColor = _railColor(scheme);
    final due = vehicle != null
        ? formatReminderDue(reminder, vehicle!.currentMileage)
        : _dueLabel(reminder);

    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: Material(
        color: scheme.surfaceContainerLowest,
        child: InkWell(
          onTap: onTap,
          child: Container(
            decoration: BoxDecoration(
              border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.6)),
            ),
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(width: 3, color: railColor),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.sm, vertical: AppSpacing.sm),
                      child: Row(
                        children: [
                          Container(
                            width: 34,
                            height: 34,
                            decoration: BoxDecoration(
                              color: railColor.withValues(alpha: 0.14),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Icon(_icon, size: 17, color: railColor),
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(reminder.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style:
                                        const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
                                if (vehicle != null)
                                  Text('${vehicle!.brand} ${vehicle!.model}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant)),
                              ],
                            ),
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          Text(due,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              softWrap: false,
                              style: AppTypography.mono(context,
                                  fontSize: 12, fontWeight: FontWeight.w600, color: railColor)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
