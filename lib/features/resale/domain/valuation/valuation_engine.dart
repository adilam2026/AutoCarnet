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
/// estimate rather than a real market quote. Always starts from its own
/// brand-tier reference price - there is no "real purchase price" input
/// (the Acquisition section was removed from the vehicle sheet entirely),
/// so depreciation always anchors on the first-registration date.
class InternalValuationProvider implements ValuationEngine {
  const InternalValuationProvider();

  @override
  ValuationResult compute(ValuationInput input) {
    final breakdown = <ValuationBreakdownLine>[];

    final year = input.year ?? input.firstRegistrationDate?.year;
    final priceEstimate =
        VehicleValuationReference.newPriceFor(input.brand, input.model, year: year);
    final base = priceEstimate.priceMad;
    breakdown.add(ValuationBreakdownLine(
      label: priceEstimate.sourced
          ? 'Valeur de référence AutoCarnet (prix neuf sourcé pour ce modèle/génération)'
          : 'Valeur de référence estimée par AutoCarnet (prix neuf approximatif par gamme)',
      runningTotal: base,
    ));
    var running = base;

    final ageMonths = input.firstRegistrationDate != null
        ? _monthsBetween(input.firstRegistrationDate!, DateTime.now())
        : null;
    if (ageMonths != null && ageMonths > 0) {
      final factor = DepreciationRules.factorForAgeMonths(ageMonths);
      final depreciated = running * factor;
      breakdown.add(ValuationBreakdownLine(
        label: 'Décote liée à l\'ancienneté',
        delta: depreciated - running,
        runningTotal: depreciated,
      ));
      running = depreciated;
    }

    if (ageMonths != null && ageMonths > 0) {
      final factor = MileageAdjustmentRules.adjustmentFactor(
        currentMileage: input.currentMileage,
        ageMonths: ageMonths,
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
      ConfidenceFactor(
        label: 'Prix neuf de référence tracé à une source réelle',
        satisfied: priceEstimate.sourced,
      ),
      const ConfidenceFactor(label: 'Aucune donnée de marché externe', satisfied: false),
    ];
    final scored = factors.where((f) => f.label != 'Aucune donnée de marché externe').toList();
    final ratio = scored.where((f) => f.satisfied).length / scored.length;
    // Never "bonne confiance" when the whole estimate is anchored on an
    // unsourced, generic brand-tier guess: the base price is the single
    // most consequential number in the calculation, so an unverified one
    // caps confidence regardless of how complete the rest of the data is.
    final confidence = !priceEstimate.sourced
        ? (ratio >= 0.4 ? ConfidenceLevel.medium : ConfidenceLevel.low)
        : (ratio >= 0.7
            ? ConfidenceLevel.good
            : (ratio >= 0.4 ? ConfidenceLevel.medium : ConfidenceLevel.low));

    // The fourchette's width now actually reflects how much AutoCarnet
    // trusts its own inputs (recalibration pass, 2026) - a well-documented,
    // sourced vehicle gets a tighter band; a mostly-unknown one gets a
    // wider, more cautious band, so the "prix haut" is never implied to be
    // just as reachable when confidence is low.
    final spread = switch (confidence) {
      ConfidenceLevel.good => 0.06,
      ConfidenceLevel.medium => 0.09,
      ConfidenceLevel.low => 0.13,
    };

    return ValuationResult(
      quickSale: _roundToNearestThousand(central * (1 - spread)),
      fairPrice: _roundToNearestThousand(central),
      highPrice: _roundToNearestThousand(central * (1 + spread)),
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

  /// AutoCarnet never claims false precision (mission: "390 000 MAD" not
  /// "389 847 MAD") - every price the engine hands back is rounded to a
  /// commercially sensible figure, not a raw multiplication result.
  double _roundToNearestThousand(double value) => (value / 1000).round() * 1000;
}

final valuationEngineProvider = Provider<ValuationEngine>((ref) {
  return const InternalValuationProvider();
});
