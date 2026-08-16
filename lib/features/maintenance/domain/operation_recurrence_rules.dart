/// Whether a given operation category is expected to recur, and if so its
/// AutoCarnet default frequency - the built-in fallback used only when the
/// owner hasn't configured (or the app hasn't yet observed and the owner
/// confirmed) a frequency specific to their vehicle (see
/// OperationFrequencyRepository, priority order in bloc 2.4).
class OperationRecurrenceRule {
  final bool isRecurrent;
  final double? defaultFrequencyKm;
  final int? defaultFrequencyMonths;
  const OperationRecurrenceRule({
    required this.isRecurrent,
    this.defaultFrequencyKm,
    this.defaultFrequencyMonths,
  });

  static const nonRecurrent = OperationRecurrenceRule(isRecurrent: false);
}

/// Only vidange/révision periodic categories get a concrete AutoCarnet
/// default (10 000 km, per the cahier des charges) - every other category
/// stays non-recurrent by default rather than guessing a number nobody
/// asked for (diagnostic, carrosserie, réparation ponctuelle...).
class OperationRecurrenceRules {
  const OperationRecurrenceRules._();

  static const _periodic = OperationRecurrenceRule(
    isRecurrent: true,
    defaultFrequencyKm: 10000,
  );

  static const Map<String, OperationRecurrenceRule> _rules = {
    'Vidange': _periodic,
    'Vidange + filtres': _periodic,
    'Révision': _periodic,
    'Révision constructeur': _periodic,
  };

  static OperationRecurrenceRule forCategory(String category) {
    return _rules[category] ?? OperationRecurrenceRule.nonRecurrent;
  }
}

/// The frequency actually used for a suggestion, and where it came from -
/// so the UI can say "fréquence observée" / "fréquence de ce véhicule"
/// instead of presenting every number as equally authoritative.
class ResolvedFrequency {
  final double? frequencyKm;
  final int? frequencyMonths;
  final bool isVehicleSpecific;
  const ResolvedFrequency({
    this.frequencyKm,
    this.frequencyMonths,
    required this.isVehicleSpecific,
  });

  static const none = ResolvedFrequency(isVehicleSpecific: false);

  bool get isRecurrent => frequencyKm != null || frequencyMonths != null;
}

/// Priority (bloc 2.4): 1. frequency explicitly configured for this vehicle
/// and category, 2. AutoCarnet's built-in default for the category. (The
/// "observed in history, pending confirmation" tier is a suggestion the UI
/// offers separately - it only becomes a vehicle override once the owner
/// accepts it, at which point it flows through tier 1 like any other.)
ResolvedFrequency resolveFrequency({
  required String category,
  double? vehicleFrequencyKm,
  int? vehicleFrequencyMonths,
}) {
  if (vehicleFrequencyKm != null || vehicleFrequencyMonths != null) {
    return ResolvedFrequency(
      frequencyKm: vehicleFrequencyKm,
      frequencyMonths: vehicleFrequencyMonths,
      isVehicleSpecific: true,
    );
  }
  final rule = OperationRecurrenceRules.forCategory(category);
  if (!rule.isRecurrent) return ResolvedFrequency.none;
  return ResolvedFrequency(
    frequencyKm: rule.defaultFrequencyKm,
    frequencyMonths: rule.defaultFrequencyMonths,
    isVehicleSpecific: false,
  );
}
