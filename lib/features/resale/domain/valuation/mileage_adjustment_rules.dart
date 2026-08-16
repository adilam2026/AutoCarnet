/// Compares actual mileage to a reference mileage for the vehicle's age and
/// nudges the estimate accordingly - configurable in one place, not spread
/// across the UI. A vehicle with a higher mileage than the reference for
/// its age must never come out strictly ahead of an identical, less-driven
/// vehicle without reason.
class MileageAdjustmentRules {
  const MileageAdjustmentRules._();

  static const referenceKmPerYear = 15000;
  static const _adjustmentPerThousandKm = 0.0015;
  static const _maxAdjustment = 0.15;

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
