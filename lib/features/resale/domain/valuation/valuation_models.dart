import '../../../../core/database/database.dart';

enum ConfidenceLevel { low, medium, good }

class ConfidenceFactor {
  final String label;
  final bool satisfied;
  const ConfidenceFactor({required this.label, required this.satisfied});
}

/// One line of the explainable breakdown shown behind "Comment cette
/// estimation est-elle calculée ?" - always produced by the engine, never
/// hardcoded in a widget (bloc 15).
class ValuationBreakdownLine {
  final String label;
  final double? delta; // null for the base line
  final double runningTotal;
  const ValuationBreakdownLine({
    required this.label,
    this.delta,
    required this.runningTotal,
  });
}

/// Everything the internal valuation engine can use - all of it either
/// already collected elsewhere in the carnet or optionally provided by the
/// owner, never a dedicated "resale questionnaire" (bloc 5/18).
class ValuationInput {
  final String brand;
  final String model;
  final String? trim;
  final int? year;
  final DateTime? firstRegistrationDate;
  final double currentMileage;
  final String? fuelType;
  final String? transmission;
  final VehicleCondition? condition;
  final int maintenanceEntryCount;
  final bool hasRecentMaintenance;

  const ValuationInput({
    required this.brand,
    required this.model,
    this.trim,
    this.year,
    this.firstRegistrationDate,
    required this.currentMileage,
    this.fuelType,
    this.transmission,
    this.condition,
    this.maintenanceEntryCount = 0,
    this.hasRecentMaintenance = false,
  });
}

/// The three tiers are always derived from the same central value - they
/// can never be independently "wrong" relative to each other.
class ValuationResult {
  final double quickSale;
  final double fairPrice;
  final double highPrice;
  final List<ValuationBreakdownLine> breakdown;
  final ConfidenceLevel confidence;
  final List<ConfidenceFactor> confidenceFactors;

  const ValuationResult({
    required this.quickSale,
    required this.fairPrice,
    required this.highPrice,
    required this.breakdown,
    required this.confidence,
    required this.confidenceFactors,
  });
}
