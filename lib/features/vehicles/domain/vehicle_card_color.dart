import 'package:flutter/material.dart';

/// AutoCarnet's curated palette for the home dashboard's vehicle-card
/// identity (design-review pass, 2026: "carte identité du véhicule",
/// Variante A retenue; enriched to 17 tones; then rebalanced in the
/// "palette plus vive" pass - the original 17-dark-and-desaturated set read
/// as too uniform once a garage held several vehicles). Tones now span
/// three brightness tiers on purpose (deep premium / intermediate / vivid
/// expressive) across real automotive colour families - blues, greens,
/// reds, oranges/copper, violets, neutrals - so [onColor] genuinely
/// branches: most tiles still resolve to white, but the lightest ("Argent")
/// resolves to dark content, which is exactly why that branch exists rather
/// than an assumption that white always works.
///
/// Every member keeps its exact enum name (and therefore its
/// [storageKey]) across palette passes, even when the tone or [label]
/// behind it changes (e.g. `aubergine` now renders as a vivid violet,
/// `grisBleute` as a light silver) - renaming or removing a member would
/// silently reinterpret every vehicle already saved with that key, which
/// the mission explicitly forbids ("une couleur enregistrée reste
/// enregistrée"). Rebalancing the colour a key maps to is fine; changing
/// what the key itself is is not.
///
/// This is a distinct property from [Vehicle.color] (the vehicle's real
/// paint colour, a free-text administrative field on the fiche) - the two
/// must never be confused or merged.
enum VehicleCardColor {
  bluePetrole,
  blueNuit,
  blueArdoise,
  blueAcier,
  vertForet,
  vertSapin,
  vertSaugeFonce,
  bordeaux,
  rougeGrenat,
  terracotta,
  cuivre,
  prune,
  aubergine,
  roseVieux,
  taupe,
  grisGraphite,
  grisBleute;

  Color get color => switch (this) {
        VehicleCardColor.bluePetrole => const Color(0xFF0E5C82),
        VehicleCardColor.blueNuit => const Color(0xFF16233D),
        VehicleCardColor.blueArdoise => const Color(0xFF2A52BE),
        VehicleCardColor.blueAcier => const Color(0xFF2E74C2),
        VehicleCardColor.vertForet => const Color(0xFF1B4332),
        VehicleCardColor.vertSapin => const Color(0xFF0E8F5E),
        VehicleCardColor.vertSaugeFonce => const Color(0xFF6E8B5E),
        VehicleCardColor.bordeaux => const Color(0xFF6B1F2A),
        VehicleCardColor.rougeGrenat => const Color(0xFF9B1B30),
        VehicleCardColor.terracotta => const Color(0xFFC1613B),
        VehicleCardColor.cuivre => const Color(0xFFB06B34),
        VehicleCardColor.prune => const Color(0xFF5B3161),
        VehicleCardColor.aubergine => const Color(0xFF7B4FB5),
        VehicleCardColor.roseVieux => const Color(0xFFC0293D),
        VehicleCardColor.taupe => const Color(0xFF6B5F52),
        VehicleCardColor.grisGraphite => const Color(0xFF3B4048),
        VehicleCardColor.grisBleute => const Color(0xFFA9B2BC),
      };

  /// Content painted directly ON [color] (icons, labels in a filled band):
  /// real luminance-based contrast, not an assumption that white always
  /// works - most entries above are dark enough that this resolves to
  /// white, but the lightest one ("Argent") genuinely resolves to dark
  /// content, so an edited/added palette entry stays protected
  /// automatically either way (mission point 4/14: "ne jamais supposer que
  /// le blanc sera lisible sur toutes les couleurs disponibles").
  Color get onColor => contrastingOnColor(color);

  /// [color] itself, used AS a foreground/border/accent on the app's white
  /// or near-white surfaces (a card's contour, an identity chip's border
  /// and icon chip) - darkened just enough to stay readable if a palette
  /// entry is too light for that role, otherwise identical to [color]. Even
  /// the lightest current entry ("Argent", ~0.44 luminance) still stays
  /// under the 0.5 darkening threshold, so this remains a no-op today, but
  /// the branch is real and exercised by tests, not an assumption.
  Color get onLightSurface => safeAccentOnLightSurface(color);

  String get label => switch (this) {
        VehicleCardColor.bluePetrole => 'Bleu pétrole',
        VehicleCardColor.blueNuit => 'Bleu marine',
        VehicleCardColor.blueArdoise => 'Bleu royal',
        VehicleCardColor.blueAcier => 'Bleu azur',
        VehicleCardColor.vertForet => 'Vert forêt',
        VehicleCardColor.vertSapin => 'Vert émeraude',
        VehicleCardColor.vertSaugeFonce => 'Vert sauge soutenu',
        VehicleCardColor.bordeaux => 'Bordeaux',
        VehicleCardColor.rougeGrenat => 'Rouge grenat',
        VehicleCardColor.terracotta => 'Terracotta',
        VehicleCardColor.cuivre => 'Cuivre',
        VehicleCardColor.prune => 'Prune',
        VehicleCardColor.aubergine => 'Violet',
        VehicleCardColor.roseVieux => 'Rouge automobile',
        VehicleCardColor.taupe => 'Taupe',
        VehicleCardColor.grisGraphite => 'Gris graphite',
        VehicleCardColor.grisBleute => 'Argent',
      };

  /// The stored key (persisted as-is in [Vehicle.cardColorKey] and synced
  /// to Supabase) - just the enum's own name, but named explicitly so a
  /// future refactor of the enum's declaration order can never silently
  /// change what's on disk (unlike a raw `.index`).
  String get storageKey => name;

  static VehicleCardColor? fromKeyOrNull(String? key) {
    if (key == null) return null;
    for (final c in values) {
      if (c.name == key) return c;
    }
    return null;
  }

  /// Never null: an unrecognised or missing key (a vehicle created before
  /// this feature existed and not yet backfilled, or a corrupted value)
  /// falls back to the brand's own colour rather than leaving the card
  /// with no identity at all.
  static VehicleCardColor fromKey(String? key) =>
      fromKeyOrNull(key) ?? VehicleCardColor.bluePetrole;

  /// Deterministic "least-used first" assignment: picks the palette colour
  /// used least often among [existingKeys] (ties broken by palette
  /// declaration order), so a garage fills up with visibly distinct colours
  /// before any repeat - never a random draw, and never re-picked on every
  /// rebuild since it only runs once, at creation/backfill time, and the
  /// result is persisted.
  ///
  /// [avoid] (typically the most recently created vehicle's own colour)
  /// steers the pick away from repeating that exact colour when another
  /// equally-least-used option exists - the mission's "éviter deux
  /// véhicules successifs de même couleur". With a 17-tone palette this
  /// mostly only matters once the palette starts its second lap (every
  /// tone used at least once): at that point every tone ties at the same
  /// count again, and pure declaration-order tie-breaking would otherwise
  /// hand the very next vehicle right back the colour the previous one just
  /// got.
  static VehicleCardColor nextFor(Iterable<String?> existingKeys, {VehicleCardColor? avoid}) {
    final counts = {for (final c in values) c: 0};
    for (final key in existingKeys) {
      final c = fromKeyOrNull(key);
      if (c != null) counts[c] = counts[c]! + 1;
    }
    var best = values.first;
    var bestCount = counts[best]!;
    for (final c in values.skip(1)) {
      if (counts[c]! < bestCount) {
        best = c;
        bestCount = counts[c]!;
      }
    }
    if (avoid != null && best == avoid) {
      VehicleCardColor? alt;
      var altCount = 1 << 30;
      for (final c in values) {
        if (c == avoid) continue;
        if (counts[c]! < altCount) {
          alt = c;
          altCount = counts[c]!;
        }
      }
      if (alt != null) return alt;
    }
    return best;
  }
}

/// Real luminance-based contrast for content painted ON [background] - a
/// free function (not just [VehicleCardColor.onColor]) so the branching
/// itself is directly unit-testable against arbitrary colours, not only
/// today's already-dark palette.
Color contrastingOnColor(Color background) =>
    background.computeLuminance() > 0.42 ? const Color(0xFF14171A) : Colors.white;

/// [color] made safe to use AS a foreground/border/accent on the app's
/// white/near-white surfaces - itself unless too light to read well there,
/// in which case it's darkened just enough. See
/// [VehicleCardColor.onLightSurface].
Color safeAccentOnLightSurface(Color color) {
  if (color.computeLuminance() <= 0.5) return color;
  final hsl = HSLColor.fromColor(color);
  return hsl.withLightness((hsl.lightness - 0.28).clamp(0.0, 1.0)).toColor();
}
