/// Motorisation/transmission coefficients - explicitly internal AutoCarnet
/// heuristics (bloc 11), never presented as a market truth. Centralized so
/// they're easy to revisit once real data is available.
class EngineAdjustmentRules {
  const EngineAdjustmentRules._();

  static const Map<String, double> _fuelFactors = {
    'Diesel': 1.02,
    'Hybride': 1.03,
    'Hybride rechargeable': 1.03,
    'Électrique': 0.98,
    'GPL': 0.97,
  };

  static double fuelFactor(String? fuelType) {
    if (fuelType == null) return 1.0;
    return _fuelFactors[fuelType] ?? 1.0;
  }

  static double transmissionFactor(String? transmission) {
    if (transmission == 'Automatique') return 1.02;
    return 1.0;
  }
}
