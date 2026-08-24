import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/database/database.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/currency_format.dart';
import '../../../reminders/domain/reminder_urgency.dart';
import '../../../vehicles/domain/brand_logos.dart';
import '../../../vehicles/domain/vehicle_card_color.dart';
import '../../../vehicles/domain/vehicle_health.dart';

/// The vehicle identity header - icon/name/year/mileage on a band in the
/// vehicle's own colour ([VehicleCardColor], auto-assigned at creation,
/// personalisable from the fiche), plus the compact santé/révision facts
/// line underneath. This is only the TOP of the accueil's "grande carte"
/// (see `_GrandVehicleCard` in vehicles_list_body.dart, mission "fusion
/// carte véhicule + carte globale" pass, 2026): it owns no border, no
/// rounded corners and no tap target of its own on purpose - the grand
/// card wrapping it owns the single outer contour (clipping this band's
/// square top corners into its own rounded ones for free), and the only
/// way into the fiche véhicule is now that wrapper's own bottom CTA, never
/// a tap anywhere on this identity header (a whole-card tap target would
/// only compete with the horizontal swipe gesture the grand card also
/// carries). Text/icons on the coloured band go through
/// [VehicleCardColor.onColor] (real luminance contrast, not an assumed
/// white). Shows only what's already computed elsewhere (health score,
/// reminders): nothing here invents new business logic.
class VehicleHeroCard extends ConsumerWidget {
  const VehicleHeroCard({
    super.key,
    required this.vehicle,
    required this.reminders,
  });

  final Vehicle vehicle;

  /// This vehicle's own active reminders (already scoped by the caller via
  /// vehicleActiveRemindersProvider) - used for the health strip and the
  /// "prochaine révision" value.
  final List<Reminder> reminders;

  Reminder? _nearestMaintenance() {
    final candidates = reminders
        .where((r) => r.sourceType == 'maintenance')
        .toList();
    if (candidates.isEmpty) return null;
    double keyOf(Reminder r) {
      final byDays = r.dueDate?.difference(DateTime.now()).inDays.toDouble();
      final byKm = r.dueMileage != null
          ? r.dueMileage! - vehicle.currentMileage
          : null;
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
    final isOk =
        worst == ReminderUrgency.later || worst == ReminderUrgency.done;
    final statusColor = isOk ? scheme.secondary : scheme.tertiary;
    final vehicleColor = VehicleCardColor.fromKey(vehicle.cardColorKey);
    final cardColor = vehicleColor.color;
    // Text/icons painted directly on the coloured band: luminance-based,
    // never assumed white (mission point 4) - every current palette entry
    // resolves to white, but this stays correct if that ever changes.
    final onColor = vehicleColor.onColor;

    // Brand logo square: base size raised (mission pass, 2026: "les logos
    // sont actuellement trop petits") and, for a logo with a known-under-
    // filled glyph box (see brandLogoVisualBoost - e.g. Audi's wide, short
    // rings), boosted further so every brand reads with a similar visual
    // presence rather than the same technical point size - clamped so a
    // boosted glyph can never outgrow its own container.
    final logo = brandLogoFor(vehicle.brand);
    const logoContainerSize = 42.0;
    const baseLogoSize = 24.0;
    final logoSize = logo == null
        ? baseLogoSize
        : (baseLogoSize * brandLogoVisualBoost(vehicle.brand))
            .clamp(baseLogoSize, logoContainerSize - 10);

    return Column(
      key: ValueKey('vehicleHeroCardHeader-${vehicle.id}'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Identity band - the grand card wrapping this widget clips its
        // square top corners into its own rounded ones (CSS-style
        // overflow-clip via that wrapper's ClipRRect), so no radius is
        // needed here at all.
        Container(
          color: cardColor,
          padding: const EdgeInsets.fromLTRB(13, 13, 13, 11),
          child: Row(
            children: [
              Container(
                width: logoContainerSize,
                height: logoContainerSize,
                decoration: BoxDecoration(
                  color: onColor.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                alignment: Alignment.center,
                // The brand's own logo glyph when one is available (bloc:
                // identité visuelle) - a locally-bundled, tintable monochrome
                // mark, never a full-colour bitmap, so it stays legible and
                // undistorted against this band's own arbitrary colour
                // exactly like the generic icon it replaces. Falls back to
                // the generic vehicle icon for a brand simple_icons doesn't
                // cover - never a blank square, never a guessed logo.
                child: Icon(
                  logo ?? Icons.directions_car_filled,
                  size: logoSize,
                  color: onColor,
                ),
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
                        color: onColor,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 1),
                    Row(
                      children: [
                        if (vehicle.year != null) ...[
                          Text(
                            '${vehicle.year}',
                            style: TextStyle(
                              fontSize: 12,
                              color: onColor.withValues(alpha: 0.78),
                            ),
                          ),
                          Text(
                            ' · ',
                            style: TextStyle(
                              fontSize: 12,
                              color: onColor.withValues(alpha: 0.55),
                            ),
                          ),
                        ],
                        Flexible(
                          child: Text(
                            '${formatAmount(vehicle.currentMileage)} km',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTypography.mono(
                              context,
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                              color: onColor,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right,
                size: 14,
                color: onColor.withValues(alpha: 0.85),
              ),
            ],
          ),
        ),
        // Facts line - back on the ordinary white surface, so these
        // numbers read exactly like the rest of the accueil.
        Padding(
          padding: const EdgeInsets.fromLTRB(13, 9, 13, 9),
          child: _FactsRow(
            dotColor: statusColor,
            healthText: health == null
                ? '—'
                : '${health.score}${isOk ? ' · À jour' : ' · À surveiller'}',
            healthOk: isOk,
            revisionText: revision == null
                ? 'Aucune prévue'
                : formatReminderAbsoluteDue(revision),
          ),
        ),
      ],
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
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}',
    );
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
      color: healthOk ? scheme.secondary : scheme.onSurface,
    );

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
            children: [
              const TextSpan(text: 'Santé '),
              TextSpan(text: healthText, style: boldStyle),
            ],
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
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: scheme.onSurface,
                  ),
                ),
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
