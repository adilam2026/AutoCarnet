/// Compares actual mileage to a reference mileage for the vehicle's age and
/// nudges the estimate accordingly - configurable in one place, not spread
/// across the UI. A vehicle with a higher mileage than the reference for
/// its age must never come out strictly ahead of an identical, less-driven
/// vehicle without reason.
///
/// Made convex (quadratic, not linear) instead of just stronger (moteur de
/// revente recalibration pass, 2026): since the reference mileage itself
/// grows with age, a purely linear rate created a real correctness bug -
/// two otherwise-identical vehicles just 1-2 years apart in age, at the
/// SAME absolute mileage, could have their ranking inverted by the mileage
/// term alone (the older one, whose reference grew, landing artificially
/// ABOVE the newer one), which is exactly the "le kilométrage ne doit
/// jamais annuler la décote d'ancienneté" rule the cadre métier forbids.
/// Squaring the deviation keeps a moderate gap (a few thousand km, or the
/// few thousand km a 1-2 year age difference alone produces at a fixed
/// mileage) close to negligible, while a genuinely large deviation (tens
/// of thousands of km, e.g. a high-mileage old vehicle) still weighs
/// meaningfully - the constant below is calibrated so a ~57 000 km excess
/// (the Opel Astra 2012/270 000 km control case) still corrects by roughly
/// a third, matching the previous linear rate's intended strength for that
/// same real-world case, without the small-gap side effect.
class MileageAdjustmentRules {
  const MileageAdjustmentRules._();

  static const referenceKmPerYear = 15000;
  static const _adjustmentPerThousandKmSquared = 0.00011;
  static const _maxAdjustment = 0.40;

  static double referenceMileageForAge(int ageMonths) {
    if (ageMonths <= 0) return 0;
    return referenceKmPerYear * (ageMonths / 12);
  }

  /// Multiplicative factor: > 1 when the vehicle has driven less than the
  /// reference for its age, < 1 when it has driven more.
  static double adjustmentFactor({
    required double currentMileage,
    required int ageMonths,
  }) {
    final reference = referenceMileageForAge(ageMonths);
    if (reference <= 0) return 1.0;
    final deltaKm = currentMileage - reference;
    final deltaThousand = deltaKm / 1000;
    final magnitude = _adjustmentPerThousandKmSquared * deltaThousand * deltaThousand;
    final rawAdjustment = deltaKm >= 0 ? -magnitude : magnitude;
    return 1 + rawAdjustment.clamp(-_maxAdjustment, _maxAdjustment);
  }
}
