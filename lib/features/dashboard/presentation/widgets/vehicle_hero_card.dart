import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/database/database.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/currency_format.dart';
import '../../../reminders/domain/reminder_urgency.dart';
import '../../../vehicles/domain/vehicle_card_color.dart';
import '../../../vehicles/domain/vehicle_health.dart';

/// The vehicle as the home dashboard's real "carte identité du véhicule"
/// (design-review pass, 2026, Variante A retenue) - the accueil's principal
/// component, not just another card among the others. Hierarchy comes from
/// colour, composition and depth rather than sheer size: a top band in the
/// vehicle's own identity colour ([VehicleCardColor], auto-assigned at
/// creation, personalisable from the fiche) carries the identity (icon,
/// name, year, mileage); the lower zone stays on the app's ordinary white
/// surface so the health/révision numbers read exactly like the rest of
/// the accueil. Cohérence pass: the vehicle's colour is also the card's
/// single outer contour (never just the top band's fill), so the three
/// zones read as one unified component instead of stacked pieces - text
/// and icons on the coloured band go through [VehicleCardColor.onColor]
/// (real luminance contrast, not an assumed white) and the contour/CTA
/// accent goes through [VehicleCardColor.onLightSurface]. A final low-key
/// row ("Voir la fiche du véhicule") makes explicit what the whole card
/// already does on tap (bloc 20 bis): it is never a second, competing tap
/// target, only a visible affordance. Shows only what's already computed
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
    final vehicleColor = VehicleCardColor.fromKey(vehicle.cardColorKey);
    final cardColor = vehicleColor.color;
    // Text/icons painted directly on the coloured band: luminance-based,
    // never assumed white (mission point 4) - every current palette entry
    // resolves to white, but this stays correct if that ever changes.
    final onColor = vehicleColor.onColor;
    // A near-invisible tint of the vehicle's own colour, not a new one -
    // just enough to separate the CTA row from the facts above it.
    final ctaTint = Color.alphaBlend(cardColor.withValues(alpha: 0.05), scheme.surfaceContainerLowest);
    // The card's own identity colour as its single outer contour (mission
    // point 1-3): it must read as ONE unified block, not three stacked
    // pieces - the coloured band above already IS this colour, so the
    // border only becomes visible where it meets the white/tinted zones
    // below, tying the whole card together without a heavy fill.
    final contourColor = vehicleColor.onLightSurface;

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
            key: ValueKey('vehicleHeroCardContour-${vehicle.id}'),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerLowest,
              // The border must carry its OWN matching borderRadius, not
              // just rely on the ancestor Material's rounded clip to hide
              // the corners - a border painted on an un-rounded
              // BoxDecoration is a sharp rectangle first and only gets
              // clipped afterwards, which left tiny slivers of the
              // straight vertical edges visible just past the bottom
              // corners (finition bug, cohérence pass follow-up).
              borderRadius: BorderRadius.circular(AppRadius.lg),
              border: Border.all(color: contourColor, width: 1.3),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Level 1 - identity: the vehicle's own colour, clipped to
                // the card's own rounded corners by the Material above (no
                // bar ever "sits on top" of the card - it belongs to it).
                Container(
                  color: cardColor,
                  padding: const EdgeInsets.fromLTRB(13, 11, 13, 11),
                  child: Row(
                    children: [
                      Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: onColor.withValues(alpha: 0.16),
                          borderRadius: BorderRadius.circular(AppRadius.sm),
                        ),
                        child: Icon(Icons.directions_car_filled, size: 16, color: onColor),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              '${vehicle.brand} ${vehicle.model}',
                              style: TextStyle(
                                  fontSize: 16.5,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: -0.3,
                                  color: onColor),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 1),
                            Row(
                              children: [
                                if (vehicle.year != null) ...[
                                  Text('${vehicle.year}',
                                      style: TextStyle(fontSize: 12, color: onColor.withValues(alpha: 0.78))),
                                  Text(' · ',
                                      style: TextStyle(fontSize: 12, color: onColor.withValues(alpha: 0.55))),
                                ],
                                Flexible(
                                  child: Text(
                                    '${formatAmount(vehicle.currentMileage)} km',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: AppTypography.mono(context,
                                        fontSize: 13, fontWeight: FontWeight.w800, color: onColor),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      Icon(Icons.chevron_right, size: 14, color: onColor.withValues(alpha: 0.85)),
                    ],
                  ),
                ),
                // Level 2 - état du véhicule: back on the ordinary white
                // surface, so these numbers read exactly like the rest of
                // the accueil.
                Padding(
                  padding: const EdgeInsets.fromLTRB(13, 7, 13, 7),
                  child: _FactsRow(
                    dotColor: statusColor,
                    healthText: health == null
                        ? '—'
                        : '${health.score}${isOk ? ' · À jour' : ' · À surveiller'}',
                    healthOk: isOk,
                    revisionText:
                        revision == null ? 'Aucune prévue' : formatReminderAbsoluteDue(revision),
                  ),
                ),
                Divider(height: 1, thickness: 1, color: scheme.outlineVariant.withValues(alpha: 0.6)),
                // Level 3 - action: an explicit affordance that the whole
                // card opens the fiche véhicule (bloc 20 bis) - not a new
                // tap target, it shares the InkWell above.
                Container(
                  color: ctaTint,
                  padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Voir la fiche du véhicule',
                          style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: contourColor),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Icon(Icons.chevron_right, size: 14, color: contourColor),
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
