import 'package:flutter/material.dart';

/// AutoCarnet's curated palette for the home dashboard's vehicle-card
/// identity (design-review pass, 2026: "carte identité du véhicule",
/// Variante A retenue; enriched in a later pass to 17 tones - "palette trop
/// limitée"). Every tone is dark and similarly-desaturated - never a
/// bright/saturated hue - so white text/icons are legible on every single
/// one of them by construction: there is no per-colour text-contrast
/// branch anywhere in the UI, because none is ever needed.
///
/// The original 8 members keep their exact enum name (and therefore their
/// [storageKey]) even where a newer, closely-related tone was added next to
/// them (e.g. `grisGraphite` alongside the new `grisBleute`) - renaming or
/// removing one would silently reinterpret every vehicle already saved with
/// that key, which the mission explicitly forbids ("une couleur enregistrée
/// reste enregistrée").
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
        VehicleCardColor.bluePetrole => const Color(0xFF123B54),
        VehicleCardColor.blueNuit => const Color(0xFF16233D),
        VehicleCardColor.blueArdoise => const Color(0xFF33475B),
        VehicleCardColor.blueAcier => const Color(0xFF2C5C7A),
        VehicleCardColor.vertForet => const Color(0xFF1E4638),
        VehicleCardColor.vertSapin => const Color(0xFF11332A),
        VehicleCardColor.vertSaugeFonce => const Color(0xFF4A5A44),
        VehicleCardColor.bordeaux => const Color(0xFF6B2432),
        VehicleCardColor.rougeGrenat => const Color(0xFF7E1B26),
        VehicleCardColor.terracotta => const Color(0xFF9C5033),
        VehicleCardColor.cuivre => const Color(0xFFA15A2A),
        VehicleCardColor.prune => const Color(0xFF55305A),
        VehicleCardColor.aubergine => const Color(0xFF34193B),
        VehicleCardColor.roseVieux => const Color(0xFF7C4A56),
        VehicleCardColor.taupe => const Color(0xFF5E5449),
        VehicleCardColor.grisGraphite => const Color(0xFF3B4048),
        VehicleCardColor.grisBleute => const Color(0xFF54606B),
      };

  /// Content painted directly ON [color] (icons, labels in a filled band):
  /// real luminance-based contrast, not an assumption that white always
  /// works - every entry above happens to be dark enough that this
  /// resolves to white today, but an edited/added palette entry stays
  /// protected automatically (mission point 4/14: "ne jamais supposer que
  /// le blanc sera lisible sur toutes les couleurs disponibles").
  Color get onColor => contrastingOnColor(color);

  /// [color] itself, used AS a foreground/border/accent on the app's white
  /// or near-white surfaces (a card's contour, an identity chip's border
  /// and icon chip) - darkened just enough to stay readable if a future
  /// palette entry were ever light, otherwise identical to [color]. Every
  /// current entry is already dark enough that this is a no-op.
  Color get onLightSurface => safeAccentOnLightSurface(color);

  String get label => switch (this) {
        VehicleCardColor.bluePetrole => 'Bleu pétrole',
        VehicleCardColor.blueNuit => 'Bleu nuit',
        VehicleCardColor.blueArdoise => 'Bleu ardoise',
        VehicleCardColor.blueAcier => 'Bleu acier',
        VehicleCardColor.vertForet => 'Vert forêt',
        VehicleCardColor.vertSapin => 'Vert sapin',
        VehicleCardColor.vertSaugeFonce => 'Vert sauge foncé',
        VehicleCardColor.bordeaux => 'Bordeaux',
        VehicleCardColor.rougeGrenat => 'Rouge grenat',
        VehicleCardColor.terracotta => 'Terracotta',
        VehicleCardColor.cuivre => 'Cuivre',
        VehicleCardColor.prune => 'Prune',
        VehicleCardColor.aubergine => 'Aubergine',
        VehicleCardColor.roseVieux => 'Rose vieux',
        VehicleCardColor.taupe => 'Taupe',
        VehicleCardColor.grisGraphite => 'Gris graphite',
        VehicleCardColor.grisBleute => 'Gris bleuté',
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
