import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/database/database.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/currency_format.dart';
import '../../../reminders/domain/reminder_urgency.dart';
import '../../../vehicles/domain/vehicle_health.dart';

/// The vehicle as a compact identity strip on the home dashboard ("Premium
/// sobre" concept, 2026, V2 design-review pass) - deliberately plain rather
/// than colour-coded per vehicle: the earlier per-vehicle gradient palette
/// had no functional justification and read as arbitrary/"fun" rather than
/// premium. AutoCarnet's own brand colour (never a colour tied to a
/// specific car) is the only accent here, used sparingly on the icon tile.
/// Shows only what's already computed elsewhere (health score, reminders):
/// nothing here invents new business logic.
class VehicleHeroCard extends ConsumerWidget {
  const VehicleHeroCard({
    super.key,
    required this.vehicle,
    required this.reminders,
    required this.onTap,
  });

  final Vehicle vehicle;

  /// This vehicle's own active reminders (already scoped by the caller via
  /// vehicleActiveRemindersProvider) - used for the health strip and the
  /// "prochaine révision" value.
  final List<Reminder> reminders;
  final VoidCallback onTap;

  Reminder? _nearestMaintenance() {
    final candidates = reminders.where((r) => r.sourceType == 'maintenance').toList();
    if (candidates.isEmpty) return null;
    double keyOf(Reminder r) {
      final byDays = r.dueDate?.difference(DateTime.now()).inDays.toDouble();
      final byKm = r.dueMileage != null ? r.dueMileage! - vehicle.currentMileage : null;
      if (byDays != null && byKm != null) return byDays < byKm ? byDays : byKm;
      return byDays ?? byKm ?? double.infinity;
    }

    candidates.sort((a, b) => keyOf(a).compareTo(keyOf(b)));
    return candidates.first;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final health = ref.watch(vehicleHealthScoreProvider(vehicle));
    final worst = _worstUrgency();
    final revision = _nearestMaintenance();
    final isOk = worst == ReminderUrgency.later || worst == ReminderUrgency.done;
    final statusColor = isOk ? scheme.secondary : scheme.tertiary;

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(AppRadius.lg),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            color: scheme.surfaceContainerLowest,
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.6)),
            boxShadow: AppElevation.card(scheme),
          ),
          padding: const EdgeInsets.fromLTRB(AppSpacing.sm, AppSpacing.sm, AppSpacing.sm, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: scheme.primaryContainer,
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                    ),
                    child: Icon(Icons.directions_car_filled, size: 18, color: scheme.primary),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '${vehicle.brand} ${vehicle.model}',
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          [
                            if (vehicle.year != null) '${vehicle.year}',
                            '${formatAmount(vehicle.currentMileage)} km',
                          ].join(' · '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_right, size: 16, color: scheme.onSurfaceVariant),
                ],
              ),
              const SizedBox(height: 10),
              Divider(height: 1, color: scheme.outlineVariant.withValues(alpha: 0.6)),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        Container(
                          width: 6,
                          height: 6,
                          margin: const EdgeInsets.only(right: 6),
                          decoration: BoxDecoration(shape: BoxShape.circle, color: statusColor),
                        ),
                        Expanded(
                          child: _StripColumn(
                            label: 'Santé',
                            value: health == null
                                ? '—'
                                : '${health.score}${isOk ? ' · À jour' : ' · À surveiller'}',
                            valueColor: isOk ? scheme.secondary : null,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(width: 1, height: 22, margin: const EdgeInsets.symmetric(horizontal: 10), color: scheme.outlineVariant.withValues(alpha: 0.6)),
                  Expanded(
                    child: _StripColumn(
                      label: 'Prochaine révision',
                      value: revision == null ? 'Aucune prévue' : formatReminderAbsoluteDue(revision),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  ReminderUrgency _worstUrgency() {
    var worst = ReminderUrgency.done;
    for (final r in reminders) {
      final u = reminderUrgency(r, currentMileage: vehicle.currentMileage);
      if (_rank(u) < _rank(worst)) worst = u;
    }
    return worst;
  }

  int _rank(ReminderUrgency u) => switch (u) {
        ReminderUrgency.urgent => 0,
        ReminderUrgency.upcoming => 1,
        ReminderUrgency.later => 2,
        ReminderUrgency.done => 3,
      };
}

/// "dans 8 000 km" / "dans 32 jours" / "12/05/2027" - the same compact
/// phrasing used by the "À faire prochainement" list, so a reminder never
/// reads differently depending on which section shows it.
String formatReminderDue(Reminder r, double currentMileage) {
  if (r.dueMileage != null) {
    final remaining = r.dueMileage! - currentMileage;
    if (remaining <= 0) return 'dépassé';
    return 'dans ${formatAmount(remaining)} km';
  }
  if (r.dueDate != null) {
    final days = r.dueDate!.difference(DateTime.now()).inDays;
    if (days < 0) return 'en retard';
    if (days == 0) return 'aujourd\'hui';
    if (days <= 60) return 'dans $days jour${days > 1 ? 's' : ''}';
    final d = r.dueDate!;
    return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
  }
  return '—';
}

/// "12/11/2026 · 98 700 km" (or just one of the two) - the absolute,
/// neutral form used by the dashboard's vehicle summary card: unlike
/// [formatReminderDue], never a relative "dans X km/jours" phrasing, and
/// never the reminder's own title, since this slot's whole point is to stay
/// a plain fact rather than duplicate the entretien tab's own detail.
String formatReminderAbsoluteDue(Reminder r) {
  final parts = <String>[];
  if (r.dueDate != null) {
    final d = r.dueDate!;
    parts.add(
        '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}');
  }
  if (r.dueMileage != null) {
    parts.add('${formatAmount(r.dueMileage!)} km');
  }
  return parts.isEmpty ? '—' : parts.join(' · ');
}

class _StripColumn extends StatelessWidget {
  const _StripColumn({required this.label, required this.value, this.valueColor});
  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label.toUpperCase(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
                fontSize: 9.5, letterSpacing: 0.4, fontWeight: FontWeight.w700, color: scheme.onSurfaceVariant)),
        const SizedBox(height: 1),
        Text(value,
            style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: valueColor),
            maxLines: 1,
            overflow: TextOverflow.ellipsis),
      ],
    );
  }
}
