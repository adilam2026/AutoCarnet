import '../../../../core/database/database.dart';

/// Finition / niveau d'équipement coefficients (mission 2026: précision de
/// l'estimation de revente) - generic across every brand/model, never a
/// per-vehicle value, centralized so they're easy to revisit like
/// [ConditionAdjustmentRules]/[EngineAdjustmentRules]. Deliberately modest
/// and capped: finition is a real price factor, but must stay secondary to
/// the reference price, l'âge and le kilométrage, each of which can swing
/// the estimate by tens of percent.
class FinishLevelAdjustmentRules {
  const FinishLevelAdjustmentRules._();

  static const Map<VehicleFinishLevel, double> _factors = {
    VehicleFinishLevel.entryLevel: 0.96,
    VehicleFinishLevel.midRange: 1.0,
    VehicleFinishLevel.highEnd: 1.05,
    VehicleFinishLevel.fullOptions: 1.08,
  };

  static double factorFor(VehicleFinishLevel? level) {
    if (level == null) return 1.0;
    return _factors[level] ?? 1.0;
  }
}
