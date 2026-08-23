import 'package:flutter/material.dart';

/// AutoCarnet's curated palette for the home dashboard's vehicle-card
/// identity (design-review pass, 2026: "carte identité du véhicule",
/// Variante A retenue). Deliberately just 8 dark, similarly-desaturated
/// tones - never a bright/saturated hue - so white text/icons are legible
/// on every single one of them by construction: there is no per-colour
/// text-contrast branch anywhere in the UI, because none is ever needed.
///
/// This is a distinct property from [Vehicle.color] (the vehicle's real
/// paint colour, a free-text administrative field on the fiche) - the two
/// must never be confused or merged.
enum VehicleCardColor {
  bluePetrole,
  blueNuit,
  vertForet,
  bordeaux,
  terracotta,
  prune,
  roseVieux,
  grisGraphite;

  Color get color => switch (this) {
        VehicleCardColor.bluePetrole => const Color(0xFF123B54),
        VehicleCardColor.blueNuit => const Color(0xFF16233D),
        VehicleCardColor.vertForet => const Color(0xFF1E4638),
        VehicleCardColor.bordeaux => const Color(0xFF6B2432),
        VehicleCardColor.terracotta => const Color(0xFF9C5033),
        VehicleCardColor.prune => const Color(0xFF55305A),
        VehicleCardColor.roseVieux => const Color(0xFF7C4A56),
        VehicleCardColor.grisGraphite => const Color(0xFF3B4048),
      };

  String get label => switch (this) {
        VehicleCardColor.bluePetrole => 'Bleu pétrole',
        VehicleCardColor.blueNuit => 'Bleu nuit',
        VehicleCardColor.vertForet => 'Vert forêt',
        VehicleCardColor.bordeaux => 'Bordeaux',
        VehicleCardColor.terracotta => 'Terracotta',
        VehicleCardColor.prune => 'Prune',
        VehicleCardColor.roseVieux => 'Rose vieux',
        VehicleCardColor.grisGraphite => 'Gris graphite',
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
  static VehicleCardColor nextFor(Iterable<String?> existingKeys) {
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
    return best;
  }
}
