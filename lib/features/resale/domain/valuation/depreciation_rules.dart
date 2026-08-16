import 'dart:math' as math;

/// Internal AutoCarnet depreciation curve - a commonly-used generic
/// automotive rule of thumb, not sourced from real market data for any
/// specific vehicle. Deliberately non-linear (steeper in year one, then
/// progressively gentler) and centralized here so the coefficients can
/// evolve without touching the engine or the UI.
class DepreciationRules {
  const DepreciationRules._();

  static const _floor = 0.15;

  /// Multiplicative factor to apply to a base value for a given age.
  static double factorForAgeMonths(int ageMonths) {
    if (ageMonths <= 0) return 1.0;
    var years = ageMonths / 12;
    var factor = 1.0;

    double consume(double yearsInBracket, double annualRate) {
      final applied = years < yearsInBracket ? years : yearsInBracket;
      years -= applied;
      return math.pow(1 - annualRate, applied).toDouble();
    }

    factor *= consume(1, 0.20); // Year 1: -20%
    if (years > 0) factor *= consume(4, 0.12); // Years 2-5: -12%/year
    if (years > 0) factor *= consume(5, 0.08); // Years 6-10: -8%/year
    if (years > 0) {
      // Beyond 10 years: -5%/year, uncapped duration.
      factor *= math.pow(1 - 0.05, years).toDouble();
    }

    return factor.clamp(_floor, 1.0);
  }
}
