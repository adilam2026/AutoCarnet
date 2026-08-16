import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../vehicles/domain/vehicle_health.dart';

/// Everything a real estimator would need to compute a market-accurate
/// price. Fields are collected and passed through today even though the
/// only shipped estimator ([NoMarketSourceResaleEstimator]) doesn't use them
/// yet - so a future estimator backed by a real source (Argus or similar)
/// can be plugged in without changing any caller.
class ResaleEstimationInput {
  final String brand;
  final String model;
  final String? trim;
  final int? year;
  final double currentMileage;
  final String? fuelType;
  final String? transmission;
  final VehicleHealthScore health;
  const ResaleEstimationInput({
    required this.brand,
    required this.model,
    this.trim,
    this.year,
    required this.currentMileage,
    this.fuelType,
    this.transmission,
    required this.health,
  });
}

class ResaleEstimateTier {
  final String label;
  final String description;
  const ResaleEstimateTier({required this.label, required this.description});
}

/// The three tiers a resale estimate is always expressed in once a real
/// source is connected (bloc 18 §18.3). Kept as a constant so the UI can
/// render the framework even while no estimator produces numbers yet.
const List<ResaleEstimateTier> resaleEstimateTierDefinitions = [
  ResaleEstimateTier(
    label: 'Vente rapide',
    description: 'Prix bas pour céder le véhicule rapidement.',
  ),
  ResaleEstimateTier(
    label: 'Prix juste',
    description: 'Prix aligné sur un marché réel.',
  ),
  ResaleEstimateTier(
    label: 'Prix haut',
    description: 'Prix ambitieux, délai de vente plus long.',
  ),
];

/// An estimate is either backed by a real source (amounts present) or
/// explicitly unavailable. There is intentionally no third state where a
/// number is shown without a real source behind it.
class ResaleEstimate {
  final bool isAvailable;
  final Map<String, double> amountsByTier; // empty when unavailable
  final String message;
  const ResaleEstimate.unavailable({required this.message})
      : isAvailable = false,
        amountsByTier = const {};
  const ResaleEstimate.available({
    required this.amountsByTier,
    required this.message,
  }) : isAvailable = true;
}

abstract class ResaleEstimator {
  /// Implementations that don't have a real market data source MUST return
  /// [ResaleEstimate.unavailable] instead of inventing a number - the
  /// cahier des charges is explicit that a fabricated estimate is worse
  /// than no estimate at all.
  ResaleEstimate estimate(ResaleEstimationInput input);
}

/// Shipped default: AutoCarnet is not connected to any real market-price
/// source (no Argus API or equivalent) yet. Rather than fabricate a number
/// from a generic depreciation formula and dress it up as an "estimate",
/// this estimator honestly reports the feature as not yet available. Wiring
/// a real source later is a matter of providing a new [ResaleEstimator]
/// implementation and swapping the provider below - no UI code changes.
class NoMarketSourceResaleEstimator implements ResaleEstimator {
  const NoMarketSourceResaleEstimator();

  @override
  ResaleEstimate estimate(ResaleEstimationInput input) {
    return const ResaleEstimate.unavailable(
      message: 'Aucune source de marché réelle (type Argus) n\'est encore '
          'connectée à AutoCarnet. Afficher un chiffre ici sans donnée de '
          'marché reviendrait à l\'inventer : cette estimation restera '
          'indisponible tant qu\'une source fiable n\'est pas intégrée. Le '
          'moteur est prêt à recevoir cette source (modèle, version, année, '
          'kilométrage, état et historique sont déjà transmis).',
    );
  }
}

final resaleEstimatorProvider = Provider<ResaleEstimator>((ref) {
  return const NoMarketSourceResaleEstimator();
});
