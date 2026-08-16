import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'condition_adjustment_rules.dart';
import 'depreciation_rules.dart';
import 'engine_adjustment_rules.dart';
import 'mileage_adjustment_rules.dart';
import 'valuation_models.dart';
import 'vehicle_valuation_reference.dart';

/// Contract every resale-price source implements - today only
/// [InternalValuationProvider], later an ExternalMarketProvider or a real
/// ArgusLikeProvider can be swapped in via [valuationEngineProvider]
/// without any change to the Revendre screen (bloc 19).
abstract class ValuationEngine {
  ValuationResult compute(ValuationInput input);
}

/// AutoCarnet's own estimation engine (bloc 4-18): always produces a
/// result, explainable step by step, explicitly labeled as an internal
/// estimate rather than a real market quote. Prioritizes real owner data
/// (purchase price + acquisition date) over the internal brand-tier
/// fallback whenever available, since that's always more trustworthy than
/// any static reference table this engine could ship with.
class InternalValuationProvider implements ValuationEngine {
  const InternalValuationProvider();

  @override
  ValuationResult compute(ValuationInput input) {
    final breakdown = <ValuationBreakdownLine>[];

    final usingPurchasePrice = input.purchasePrice != null && input.purchasePrice! > 0;
    final base = usingPurchasePrice
        ? input.purchasePrice!
        : VehicleValuationReference.estimatedNewPrice(input.brand, input.model);
    final baseLabel = usingPurchasePrice
        ? 'Valeur de référence (prix d\'achat renseigné)'
        : 'Valeur de référence estimée par AutoCarnet (prix neuf approximatif)';
    breakdown.add(ValuationBreakdownLine(label: baseLabel, runningTotal: base));
    var running = base;

    // Depreciation anchors on the acquisition date when we're starting from
    // a real purchase price (the price already reflects the vehicle's age
    // at the time of purchase) - otherwise on the registration date.
    final depreciationAnchor = (usingPurchasePrice && input.acquisitionDate != null)
        ? input.acquisitionDate
        : input.firstRegistrationDate;
    final depreciationAgeMonths =
        depreciationAnchor != null ? _monthsBetween(depreciationAnchor, DateTime.now()) : null;
    if (depreciationAgeMonths != null && depreciationAgeMonths > 0) {
      final factor = DepreciationRules.factorForAgeMonths(depreciationAgeMonths);
      final depreciated = running * factor;
      breakdown.add(ValuationBreakdownLine(
        label: 'Décote liée à l\'ancienneté',
        delta: depreciated - running,
        runningTotal: depreciated,
      ));
      running = depreciated;
    }

    // Mileage is always compared to the vehicle's full age since first
    // registration, regardless of which anchor depreciation used.
    final registrationAgeMonths = input.firstRegistrationDate != null
        ? _monthsBetween(input.firstRegistrationDate!, DateTime.now())
        : null;
    if (registrationAgeMonths != null && registrationAgeMonths > 0) {
      final factor = MileageAdjustmentRules.adjustmentFactor(
        currentMileage: input.currentMileage,
        ageMonths: registrationAgeMonths,
      );
      if (factor != 1.0) {
        final adjusted = running * factor;
        breakdown.add(ValuationBreakdownLine(
          label: factor > 1
              ? 'Kilométrage inférieur à la référence pour son âge'
              : 'Kilométrage supérieur à la référence pour son âge',
          delta: adjusted - running,
          runningTotal: adjusted,
        ));
        running = adjusted;
      }
    }

    final conditionFactor = ConditionAdjustmentRules.factorFor(input.condition);
    if (conditionFactor != 1.0) {
      final adjusted = running * conditionFactor;
      breakdown.add(ValuationBreakdownLine(
        label: 'État général déclaré',
        delta: adjusted - running,
        runningTotal: adjusted,
      ));
      running = adjusted;
    }

    final engineFactor = EngineAdjustmentRules.fuelFactor(input.fuelType) *
        EngineAdjustmentRules.transmissionFactor(input.transmission);
    if (engineFactor != 1.0) {
      final adjusted = running * engineFactor;
      breakdown.add(ValuationBreakdownLine(
        label: 'Motorisation et transmission',
        delta: adjusted - running,
        runningTotal: adjusted,
      ));
      running = adjusted;
    }

    // Sanity guard: adjustments alone should never send the estimate wildly
    // outside a plausible band around the base reference.
    final central = running.clamp(base * 0.1, base * 1.3);

    final factors = <ConfidenceFactor>[
      ConfidenceFactor(
        label: 'Date de mise en circulation connue',
        satisfied: input.firstRegistrationDate != null,
      ),
      const ConfidenceFactor(label: 'Kilométrage connu', satisfied: true),
      ConfidenceFactor(label: 'Motorisation connue', satisfied: input.fuelType != null),
      ConfidenceFactor(
        label: 'Finition/version connue',
        satisfied: input.trim != null && input.trim!.trim().isNotEmpty,
      ),
      ConfidenceFactor(label: 'État général renseigné', satisfied: input.condition != null),
      ConfidenceFactor(
        label: 'Historique d\'entretien disponible',
        satisfied: input.maintenanceEntryCount > 0,
      ),
      const ConfidenceFactor(label: 'Aucune donnée de marché externe', satisfied: false),
    ];
    final scored = factors.where((f) => f.label != 'Aucune donnée de marché externe').toList();
    final ratio = scored.where((f) => f.satisfied).length / scored.length;
    final confidence = ratio >= 0.7
        ? ConfidenceLevel.good
        : (ratio >= 0.4 ? ConfidenceLevel.medium : ConfidenceLevel.low);

    return ValuationResult(
      quickSale: central * 0.92,
      fairPrice: central,
      highPrice: central * 1.08,
      breakdown: breakdown,
      confidence: confidence,
      confidenceFactors: factors,
    );
  }

  int _monthsBetween(DateTime a, DateTime b) {
    var months = (b.year - a.year) * 12 + (b.month - a.month);
    if (b.day < a.day) months -= 1;
    return months < 0 ? 0 : months;
  }
}

final valuationEngineProvider = Provider<ValuationEngine>((ref) {
  return const InternalValuationProvider();
});
