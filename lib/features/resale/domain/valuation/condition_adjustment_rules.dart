import '../../../../core/database/database.dart';

/// Condition adjustment coefficients, centralized so they can be tuned
/// without touching the engine composition or the UI.
class ConditionAdjustmentRules {
  const ConditionAdjustmentRules._();

  static const Map<VehicleCondition, double> _factors = {
    VehicleCondition.excellent: 1.05,
    VehicleCondition.veryGood: 1.02,
    VehicleCondition.good: 1.0,
    VehicleCondition.average: 0.95,
    VehicleCondition.needsWork: 0.88,
  };

  static double factorFor(VehicleCondition? condition) {
    if (condition == null) return 1.0;
    return _factors[condition] ?? 1.0;
  }
}
