/// Internal AutoCarnet depreciation curve - a generic automotive rule of
/// thumb, not sourced from real market data for any specific vehicle.
///
/// Recalibration pass (2026, "moteur de revente" audit): the previous curve
/// (compounded per-year rates) was systematically too steep across every
/// age band when measured against the explicit cadre métier - a 3-year-old
/// vehicle was already at ~35% cumulative décote (cadre: 15-25% for 2-4
/// ans), a 5-year-old at ~46% (cadre: 25-35%). This rewrite expresses
/// décote as CUMULATIVE anchors from the new price at specific ages -
/// never a per-year rate compounded across brackets, which is exactly the
/// mistake the cadre explicitly warns against ("un véhicule de 7 ans ne
/// doit pas subir 12% + 15-25% + 25-35%") - interpolated linearly between
/// anchors on the vehicle's EXACT age (days, not just whole years), so a
/// January and a December registration in the same year never land on the
/// same point on the curve, and no two consecutive ages ever jump by more
/// than the interpolation step between anchors (no "8 ans -> 235k / 9 ans
/// -> 190k" cliff).
class DepreciationRules {
  const DepreciationRules._();

  /// Cumulative décote from new at each anchor age (years), chosen inside
  /// the business cadre's own bands - never on a boundary value that would
  /// spill into the neighbouring bracket's range.
  static const Map<int, double> _anchors = {
    0: 0.00,
    1: 0.12,
    2: 0.17,
    3: 0.20,
    4: 0.23,
    5: 0.26,
    6: 0.28,
    7: 0.31,
    8: 0.34,
    9: 0.37,
    10: 0.40,
    11: 0.43,
    12: 0.46,
    13: 0.50,
    14: 0.53,
    15: 0.56,
    16: 0.60,
    17: 0.62,
    18: 0.64,
    19: 0.66,
    20: 0.68,
  };

  /// Beyond the last anchor (20 ans), décote keeps approaching this ceiling
  /// with a diminishing rate - never a straight line that keeps plunging
  /// toward zero residual value, and never a hard stop either. The actual
  /// floor value for a given old vehicle still depends on its own
  /// conservation profile, kilométrage and état - this ceiling is only the
  /// age component's own asymptote.
  static const double _maxDecoteBeyond20 = 0.80;

  /// Multiplicative factor to apply to a base value for a given exact age.
  static double factorForAgeDays(int ageDays) {
    if (ageDays <= 0) return 1.0;
    final decote = _cumulativeDecote(ageDays / 365.25);
    return (1 - decote).clamp(1 - _maxDecoteBeyond20, 1.0);
  }

  static double _cumulativeDecote(double ageYears) {
    final keys = _anchors.keys.toList()..sort();
    final lastKey = keys.last;
    if (ageYears >= lastKey) {
      final extra = ageYears - lastKey;
      final remaining = _maxDecoteBeyond20 - _anchors[lastKey]!;
      // Diminishing-return approach: half the remaining gap closes roughly
      // every 6 extra years, so the curve keeps climbing but ever more
      // slowly - it never re-accelerates and never truly reaches the
      // ceiling.
      final approached = remaining * (1 - (0.9 * (1 / (1 + extra / 6))));
      return _anchors[lastKey]! + approached;
    }
    for (var i = 0; i < keys.length - 1; i++) {
      final a = keys[i], b = keys[i + 1];
      if (ageYears >= a && ageYears <= b) {
        final t = (ageYears - a) / (b - a);
        return _anchors[a]! + (_anchors[b]! - _anchors[a]!) * t;
      }
    }
    return _anchors[lastKey]!;
  }
}
