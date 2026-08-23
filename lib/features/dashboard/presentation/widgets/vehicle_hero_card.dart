import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/database/database.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/currency_format.dart';
import '../../../reminders/domain/reminder_urgency.dart';
import '../../../vehicles/domain/vehicle_health.dart';

/// The vehicle as the home dashboard's HERO block ("Premium sobre" concept,
/// 2026, V2 design-review pass, "accent supérieur" variant) - deliberately
/// plain rather than colour-coded per vehicle: the earlier per-vehicle
/// gradient palette had no functional justification and read as
/// arbitrary/"fun" rather than premium. AutoCarnet's own brand colour
/// (never a colour tied to a specific car) is the only accent here: a thin
/// line on the card's top edge (never the left edge - that reads as an
/// alert rail) plus a hair more elevation than ordinary cards, so this one
/// card reads as "my vehicle", not just another row of information. Shows
/// only what's already computed elsewhere (health score, reminders):
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

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        boxShadow: AppElevation.hero(scheme),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Container(
            decoration: BoxDecoration(
              color: scheme.surfaceContainerLowest,
              border: Border.all(color: AppElevation.heroBorder(scheme)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(height: 3, color: scheme.primary),
                Padding(
                  padding: const EdgeInsets.fromLTRB(13, 12, 13, 11),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 34,
                            height: 34,
                            decoration: BoxDecoration(
                              color: scheme.primaryContainer,
                              borderRadius: BorderRadius.circular(AppRadius.sm),
                            ),
                            child: Icon(Icons.directions_car_filled, size: 17, color: scheme.primary),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  '${vehicle.brand} ${vehicle.model}',
                                  style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, letterSpacing: -0.3),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 1),
                                Row(
                                  children: [
                                    if (vehicle.year != null) ...[
                                      Text('${vehicle.year}',
                                          style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant)),
                                      Text(' · ',
                                          style: TextStyle(fontSize: 12.5, color: scheme.outline)),
                                    ],
                                    Flexible(
                                      child: Text(
                                        '${formatAmount(vehicle.currentMileage)} km',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: AppTypography.mono(context, fontSize: 13.5, fontWeight: FontWeight.w800),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          Icon(Icons.chevron_right, size: 14, color: scheme.onSurfaceVariant),
                        ],
                      ),
                      const SizedBox(height: 7),
                      _FactsRow(
                        dotColor: statusColor,
                        healthText: health == null
                            ? '—'
                            : '${health.score}${isOk ? ' · À jour' : ' · À surveiller'}',
                        healthOk: isOk,
                        revisionText:
                            revision == null ? 'Aucune prévue' : formatReminderAbsoluteDue(revision),
                      ),
                    ],
                  ),
                ),
              ],
            ),
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

/// The V2.1 "compact single facts line" (validated design-review pass):
/// collapses the earlier two-column status strip (with its own divider)
/// into one slim inline row - "Santé X · À jour · Prochaine révision Y" -
/// about half the height for the same information, nothing dropped.
class _FactsRow extends StatelessWidget {
  const _FactsRow({
    required this.dotColor,
    required this.healthText,
    required this.healthOk,
    required this.revisionText,
  });

  final Color dotColor;
  final String healthText;
  final bool healthOk;
  final String revisionText;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final factStyle = TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant);
    final boldStyle = TextStyle(
        fontSize: 11.5,
        fontWeight: FontWeight.w700,
        color: healthOk ? scheme.secondary : scheme.onSurface);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 6,
          height: 6,
          margin: const EdgeInsets.only(right: 3),
          decoration: BoxDecoration(shape: BoxShape.circle, color: dotColor),
        ),
        Text.rich(
          TextSpan(
            style: factStyle,
            children: [const TextSpan(text: 'Santé '), TextSpan(text: healthText, style: boldStyle)],
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        Text(' · ', style: TextStyle(fontSize: 11.5, color: scheme.outline)),
        Expanded(
          child: Text.rich(
            TextSpan(
              style: factStyle,
              children: [
                const TextSpan(text: 'Prochaine révision '),
                TextSpan(
                    text: revisionText,
                    style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: scheme.onSurface)),
              ],
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
