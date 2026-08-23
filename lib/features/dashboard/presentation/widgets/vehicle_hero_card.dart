import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/database/database.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/currency_format.dart';
import '../../../reminders/domain/reminder_urgency.dart';
import '../../../vehicles/domain/vehicle_health.dart';

/// The vehicle as the central, "instrument cluster" element of the home
/// dashboard ("Auto Premium Clair" concept, 2026, design-review pass) - a
/// colour-identified, elevated card rather than a plain bordered rectangle:
/// every vehicle gets its own deterministic gradient (stable across app
/// opens, distinct across a multi-vehicle garage) so the fleet doesn't read
/// as a stack of identical rows. Shows only what's already computed
/// elsewhere (health score, reminders): nothing here invents new business
/// logic.
class VehicleHeroCard extends ConsumerWidget {
  const VehicleHeroCard({
    super.key,
    required this.vehicle,
    required this.reminders,
    required this.onTap,
  });

  final Vehicle vehicle;

  /// This vehicle's own active reminders (already scoped by the caller via
  /// vehicleActiveRemindersProvider) - used for the status pill and the
  /// "prochaine révision"/"prochaine échéance" lines.
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
    final gradient = vehicleCardGradient(vehicle.id);

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(AppRadius.xl),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.xl),
        onTap: onTap,
        child: Ink(
          padding: const EdgeInsets.fromLTRB(
              AppSpacing.md, AppSpacing.md, AppSpacing.md, AppSpacing.sm),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.xl),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: gradient,
            ),
            boxShadow: AppElevation.raised(scheme),
          ),
          child: Stack(
            children: [
              Positioned(
                right: -14,
                bottom: -18,
                child: Icon(Icons.directions_car_filled,
                    size: 128, color: Colors.white.withValues(alpha: 0.14)),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${vehicle.brand} ${vehicle.model}',
                              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w700,
                                  ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              [
                                if (vehicle.year != null) '${vehicle.year}',
                                if (vehicle.plate != null) vehicle.plate!,
                              ].join(' · '),
                              style: AppTypography.mono(context,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                  color: Colors.white.withValues(alpha: 0.78)),
                            ),
                          ],
                        ),
                      ),
                      _StatusBadge(urgency: worst),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Row(
                    children: [
                      Expanded(
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.baseline,
                          textBaseline: TextBaseline.alphabetic,
                          children: [
                            Flexible(
                              child: Text(
                                formatAmount(vehicle.currentMileage),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: AppTypography.mono(context,
                                    fontSize: 30, fontWeight: FontWeight.w700, color: Colors.white),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text('km',
                                style: AppTypography.mono(context,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w500,
                                    color: Colors.white.withValues(alpha: 0.78))),
                          ],
                        ),
                      ),
                      if (health != null) _HealthRing(score: health.score),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Divider(height: 1, color: Colors.white.withValues(alpha: 0.22)),
                  const SizedBox(height: AppSpacing.sm),
                  // Deliberately neutral: no reminder title here (never
                  // "Vidange + filtres à prévoir") - this card is the
                  // summary, the nature of the operation belongs to the
                  // entretien tab. "Prochaine échéance" (document-based)
                  // was removed entirely rather than duplicated with "À
                  // faire prochainement" below.
                  _MetaColumn(
                    label: 'Prochaine révision',
                    value: revision == null ? 'Aucune prévue' : formatReminderAbsoluteDue(revision),
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

/// A small, fixed set of premium gradients (all colour-harmonious with the
/// brand's blue/turquoise identity) picked deterministically from the
/// vehicle's id - the same vehicle always renders the same colour across
/// app opens, and a multi-vehicle garage reads as genuinely distinct cars
/// rather than identical rows (bloc design-review 2026, "couleur liée au
/// véhicule"). Never derived from the free-text "couleur" field the owner
/// can type in the vehicle sheet - that's an arbitrary string, not reliably
/// mappable to a real colour.
List<Color> vehicleCardGradient(String vehicleId) {
  const palette = [
    [Color(0xFF0E1B3E), Color(0xFF1652F0), Color(0xFF3E8BFF)],
    [Color(0xFF2B2420), Color(0xFF7A4A22), Color(0xFFFF9A3D)],
    [Color(0xFF0B2E28), Color(0xFF0EA37A), Color(0xFF3FD9AC)],
    [Color(0xFF2E1230), Color(0xFF8C2F6B), Color(0xFFE6598F)],
  ];
  return palette[vehicleId.hashCode.abs() % palette.length];
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

class _HealthRing extends StatelessWidget {
  const _HealthRing({required this.score});
  final int score;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 42,
      height: 42,
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox.expand(
            child: CircularProgressIndicator(
              value: score / 100,
              strokeWidth: 3.5,
              backgroundColor: Colors.white.withValues(alpha: 0.25),
              valueColor: const AlwaysStoppedAnimation(Colors.white),
              strokeCap: StrokeCap.round,
            ),
          ),
          Text('$score',
              style: AppTypography.mono(context,
                  fontSize: 12, fontWeight: FontWeight.w700, color: Colors.white)),
        ],
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.urgency});
  final ReminderUrgency urgency;

  @override
  Widget build(BuildContext context) {
    final label = switch (urgency) {
      ReminderUrgency.urgent => 'À surveiller',
      ReminderUrgency.upcoming => 'À surveiller',
      ReminderUrgency.later || ReminderUrgency.done => 'À jour',
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.20),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(label,
          style: const TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.w700)),
    );
  }
}

class _MetaColumn extends StatelessWidget {
  const _MetaColumn({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label.toUpperCase(),
            style: TextStyle(
                fontSize: 10.5,
                letterSpacing: 0.4,
                fontWeight: FontWeight.w700,
                color: Colors.white.withValues(alpha: 0.72))),
        const SizedBox(height: 2),
        Text(value,
            style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: Colors.white),
            maxLines: 1,
            overflow: TextOverflow.ellipsis),
      ],
    );
  }
}
