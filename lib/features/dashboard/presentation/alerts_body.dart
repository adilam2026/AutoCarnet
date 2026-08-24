import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/database/database.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/layout.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/list_surface.dart';
import '../../../core/widgets/loading_error_views.dart';
import '../../documents/presentation/personal_documents_screen.dart';
import '../../reminders/data/reminder_repository.dart';
import '../../reminders/domain/reminder_urgency.dart';
import '../../vehicles/data/vehicle_repository.dart';
import 'widgets/vehicle_hero_card.dart' show formatReminderDue;

/// Cross-vehicle view of every reminder (bloc 12, §15.11) - the dashboard
/// used to bury this inside each vehicle; now it's a first-class
/// destination so nothing gets missed across a multi-vehicle garage.
///
/// V2.1 pass: grouped by urgency into "En retard" / "Bientôt" / "Plus tard"
/// list-surfaces (the validated mockup's structure) instead of a row of
/// ChoiceChips - the urgency/vehicle filtering capability isn't lost, it
/// moves into a discreet filter sheet reached via the app bar action, so
/// the main screen stays as compact as the reference.
class AlertsBody extends ConsumerStatefulWidget {
  const AlertsBody({super.key});

  @override
  ConsumerState<AlertsBody> createState() => _AlertsBodyState();
}

class _AlertsBodyState extends ConsumerState<AlertsBody> {
  ReminderUrgency? _urgencyFilter;
  String? _vehicleFilter;

  Future<void> _openFilterSheet(Map<String, Vehicle> vehicles) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => _FilterSheet(
        urgency: _urgencyFilter,
        vehicleId: _vehicleFilter,
        vehicles: vehicles,
        onChanged: (urgency, vehicleId) {
          setState(() {
            _urgencyFilter = urgency;
            _vehicleFilter = vehicleId;
          });
        },
      ),
    );
  }

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
        final urgencyOf = {
          for (final r in reminders)
            r.id: reminderUrgency(r, currentMileage: vehicles[r.vehicleId]?.currentMileage),
        };
        final hasActiveFilter = _urgencyFilter != null || _vehicleFilter != null;
        final filtered = reminders.where((r) {
          final urgency = urgencyOf[r.id]!;
          if (_urgencyFilter == null) {
            if (urgency == ReminderUrgency.done) return false;
          } else if (urgency != _urgencyFilter) {
            return false;
          }
          if (_vehicleFilter != null && r.vehicleId != _vehicleFilter) return false;
          return true;
        }).toList()
          ..sort((a, b) {
            final da = a.dueDate ?? DateTime(2100);
            final db = b.dueDate ?? DateTime(2100);
            return da.compareTo(db);
          });

        Widget row(Reminder r) => _AlertListRow(
              reminder: r,
              vehicle: vehicles[r.vehicleId],
              urgency: urgencyOf[r.id]!,
              onTap: vehicles[r.vehicleId] != null
                  ? () => context.push('/vehicles/${vehicles[r.vehicleId]!.id}')
                  // A personal reminder (permis de conduire...) has no
                  // vehicle to open - it belongs to the profile instead.
                  : r.vehicleId == null
                      ? () => Navigator.of(context).push(
                          MaterialPageRoute(builder: (_) => const PersonalDocumentsScreen()))
                      : null,
            );

        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.md, AppSpacing.md, 0),
              child: Row(
                children: [
                  if (vehicles.isNotEmpty)
                    Expanded(
                      child: Text(
                        vehicles.values.map((v) => '${v.brand} ${v.model}').join(' · '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 13, color: Theme.of(context).colorScheme.onSurfaceVariant),
                      ),
                    ),
                  IconButton(
                    tooltip: 'Filtrer',
                    onPressed: () => _openFilterSheet(vehicles),
                    icon: Icon(hasActiveFilter ? Icons.filter_alt : Icons.filter_alt_outlined),
                  ),
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
                  : hasActiveFilter
                      // A specific urgency/vehicle is picked: grouping by
                      // urgency would just produce one section, so a flat
                      // list-surface is clearer.
                      ? ListView(
                          padding: EdgeInsets.fromLTRB(
                              AppSpacing.md, AppSpacing.sm, AppSpacing.md, fabSafeBottomPadding(context)),
                          children: [ListSurface(children: [for (final r in filtered) row(r)])],
                        )
                      : ListView(
                          padding: EdgeInsets.fromLTRB(
                              AppSpacing.md, AppSpacing.sm, AppSpacing.md, fabSafeBottomPadding(context)),
                          children: [
                            for (final group in [
                              (
                                'En retard',
                                filtered.where((r) => urgencyOf[r.id] == ReminderUrgency.urgent).toList()
                              ),
                              (
                                'Bientôt',
                                filtered.where((r) => urgencyOf[r.id] == ReminderUrgency.upcoming).toList()
                              ),
                              (
                                'Plus tard',
                                filtered.where((r) => urgencyOf[r.id] == ReminderUrgency.later).toList()
                              ),
                            ])
                              if (group.$2.isNotEmpty) ...[
                                _SectionLabel(group.$1),
                                const SizedBox(height: AppSpacing.xs),
                                ListSurface(children: [for (final r in group.$2) row(r)]),
                                const SizedBox(height: AppSpacing.md),
                              ],
                          ],
                        ),
            ),
          ],
        );
      },
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.label);
  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Text(
      label.toUpperCase(),
      style: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.6,
        color: scheme.onSurfaceVariant.withValues(alpha: 0.85),
      ),
    );
  }
}

/// The discreet home for urgency/vehicle filtering the main screen used to
/// spend two full ChoiceChip rows on - same options, reached via the
/// filter icon instead of always sitting on screen.
class _FilterSheet extends StatelessWidget {
  const _FilterSheet({
    required this.urgency,
    required this.vehicleId,
    required this.vehicles,
    required this.onChanged,
  });
  final ReminderUrgency? urgency;
  final String? vehicleId;
  final Map<String, Vehicle> vehicles;
  final void Function(ReminderUrgency? urgency, String? vehicleId) onChanged;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.md, AppSpacing.md, AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Filtrer les alertes', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: AppSpacing.md),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ChoiceChip(
                  label: const Text('En cours'),
                  selected: urgency == null,
                  onSelected: (_) => onChanged(null, vehicleId),
                ),
                ChoiceChip(
                  label: const Text('Urgent'),
                  selected: urgency == ReminderUrgency.urgent,
                  onSelected: (_) => onChanged(ReminderUrgency.urgent, vehicleId),
                ),
                ChoiceChip(
                  label: const Text('À surveiller'),
                  selected: urgency == ReminderUrgency.upcoming,
                  onSelected: (_) => onChanged(ReminderUrgency.upcoming, vehicleId),
                ),
                ChoiceChip(
                  label: const Text('À venir'),
                  selected: urgency == ReminderUrgency.later,
                  onSelected: (_) => onChanged(ReminderUrgency.later, vehicleId),
                ),
                ChoiceChip(
                  label: const Text('Traitées'),
                  selected: urgency == ReminderUrgency.done,
                  onSelected: (_) => onChanged(ReminderUrgency.done, vehicleId),
                ),
              ],
            ),
            if (vehicles.length > 1) ...[
              const SizedBox(height: AppSpacing.md),
              Text('Véhicule', style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: AppSpacing.sm),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ChoiceChip(
                    label: const Text('Tous les véhicules'),
                    selected: vehicleId == null,
                    onSelected: (_) => onChanged(urgency, null),
                  ),
                  for (final v in vehicles.values)
                    ChoiceChip(
                      label: Text('${v.brand} ${v.model}'),
                      selected: vehicleId == v.id,
                      onSelected: (_) => onChanged(urgency, v.id),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// The mockup's ".list-row" language (severity-tinted icon chip, title +
/// vehicle meta, trailing coloured value) - the same shape already used by
/// the home dashboard's "À faire prochainement" and fiche véhicule's
/// Administratif section, so an alert reads identically wherever it shows.
class _AlertListRow extends StatelessWidget {
  const _AlertListRow({
    required this.reminder,
    required this.vehicle,
    required this.urgency,
    required this.onTap,
  });
  final Reminder reminder;
  final Vehicle? vehicle;
  final ReminderUrgency urgency;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (iconColor, valueColor, icon) = switch (urgency) {
      ReminderUrgency.urgent => (scheme.error, scheme.error, Icons.warning_amber_rounded),
      ReminderUrgency.upcoming => (scheme.tertiary, scheme.tertiary, Icons.schedule_outlined),
      ReminderUrgency.later => (scheme.onSurfaceVariant, scheme.onSurfaceVariant, Icons.event_outlined),
      ReminderUrgency.done => (scheme.secondary, scheme.onSurfaceVariant, Icons.check_circle_outline),
    };
    final due = vehicle != null
        ? formatReminderDue(reminder, vehicle!.currentMileage)
        : _dueLabel(reminder);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 9),
          child: Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                child: Icon(icon, size: 14, color: iconColor),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(reminder.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                    if (vehicle != null)
                      Text('${vehicle!.brand} ${vehicle!.model}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Text(due,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  softWrap: false,
                  style: AppTypography.mono(context,
                      fontSize: 13, fontWeight: FontWeight.w700, color: valueColor)),
            ],
          ),
        ),
      ),
    );
  }

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
}
