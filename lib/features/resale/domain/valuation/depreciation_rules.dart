import 'dart:math' as math;

/// Internal AutoCarnet depreciation curve - a generic automotive rule of
/// thumb, not sourced from real market data for any specific vehicle.
/// Deliberately non-linear (steeper in year one, then progressively
/// gentler) and centralized here so the coefficients can evolve without
/// touching the engine or the UI. Rates below year 1 aside were widened
/// once (slower decay from year 2 onward) after the Moroccan used-market
/// control cases (Opel Astra 2012/270 000 km, Audi Q5) showed the tighter
/// Western-style rule of thumb previously used here was retaining too
/// little value for older, high-mileage vehicles - then tightened again
/// on the post-10-year brackets specifically (recalibration pass, 2026)
/// after those same two control cases swung the other way and started
/// overestimating: a 14-year-old, 270 000 km Astra was landing close to
/// 80 000 MAD instead of the expected ~70 000 MAD. The under-5-years
/// brackets (which the more recent Audi Q5 case never even reaches) are
/// untouched by this pass - still a generic curve applied identically to
/// every vehicle, never tuned per brand/model.
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
    if (years > 0) factor *= consume(4, 0.095); // Years 2-5: -9.5%/year
    if (years > 0) factor *= consume(5, 0.062); // Years 6-10: -6.2%/year
    if (years > 0) {
      // Beyond 10 years: -3.4%/year, uncapped duration.
      factor *= math.pow(1 - 0.034, years).toDouble();
    }

    return factor.clamp(_floor, 1.0);
  }
}
