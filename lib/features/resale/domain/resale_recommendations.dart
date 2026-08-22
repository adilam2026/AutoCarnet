import '../../../core/database/database.dart';
import 'resale_readiness.dart';
import 'valuation/valuation_models.dart';

/// Merges the preparation-for-sale recommendations with a few
/// estimation-specific ones derived from what the vehicle sheet is still
/// missing - dynamic per vehicle, never the same fixed list for everyone
/// (bloc 16).
List<String> buildResaleRecommendations({
  required ResaleReadiness readiness,
  required ValuationResult valuation,
  required Vehicle vehicle,
}) {
  final recs = <String>[...readiness.recommendations];

  final missingCharacteristics = <String>[
    if (vehicle.trim == null || vehicle.trim!.trim().isEmpty) 'la version/finition',
    if (vehicle.motorization == null || vehicle.motorization!.trim().isEmpty)
      'la motorisation',
  ];
  if (missingCharacteristics.isNotEmpty) {
    recs.add(
      'Complétez ${missingCharacteristics.join(' et ')} de la fiche véhicule '
      'pour améliorer la fiabilité de l\'estimation.',
    );
  }
  if (vehicle.firstRegistrationDate == null) {
    recs.add(
      'Renseignez la date de première mise en circulation pour un calcul '
      'd\'ancienneté précis.',
    );
  }
  if (vehicle.condition == null) {
    recs.add('Indiquez l\'état général du véhicule pour affiner l\'estimation.');
  }

  return recs;
}
