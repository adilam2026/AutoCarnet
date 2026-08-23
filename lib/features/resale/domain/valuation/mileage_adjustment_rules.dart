/// Compares actual mileage to a reference mileage for the vehicle's age and
/// nudges the estimate accordingly - configurable in one place, not spread
/// across the UI. A vehicle with a higher mileage than the reference for
/// its age must never come out strictly ahead of an identical, less-driven
/// vehicle without reason. Strengthened (recalibration pass, 2026) after
/// the Opel Astra 2012/270 000 km control case showed a vehicle far above
/// its age-reference mileage wasn't being penalized enough to keep the
/// overall estimate realistic - a moderate excess (a few thousand km) still
/// barely moves the estimate, but a large, genuine excess (tens of
/// thousands of km) now weighs meaningfully more than before.
class MileageAdjustmentRules {
  const MileageAdjustmentRules._();

  static const referenceKmPerYear = 15000;
  static const _adjustmentPerThousandKm = 0.0026;
  static const _maxAdjustment = 0.25;

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
    final rawAdjustment = -(deltaKm / 1000) * _adjustmentPerThousandKm;
    return 1 + rawAdjustment.clamp(-_maxAdjustment, _maxAdjustment);
  }
}
