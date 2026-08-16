import '../../../core/database/database.dart';
import '../../documents/data/document_repository.dart';

enum HealthImpact { positive, negative, neutral }

class HealthFactor {
  final String label;
  final String detail;
  final HealthImpact impact;
  const HealthFactor({
    required this.label,
    required this.detail,
    required this.impact,
  });
}

class VehicleHealthScore {
  final int score; // 0-100, higher is better
  final List<HealthFactor> factors;
  const VehicleHealthScore({required this.score, required this.factors});
}

/// A resale-oriented health score, built only from data already collected
/// elsewhere in the carnet (active reminders, maintenance history, document
/// validity, completeness) - never a market judgement, just a reflection of
/// how well-documented and up-to-date the vehicle's own record is.
VehicleHealthScore computeResaleHealthScore({
  required List<Reminder> activeReminders,
  required List<MaintenanceEntry> maintenanceEntries,
  required List<DocumentWithVersion> documents,
  required double completeness,
}) {
  var score = 100;
  final factors = <HealthFactor>[];
  final now = DateTime.now();

  final overdue = activeReminders
      .where((r) => r.dueDate != null && r.dueDate!.isBefore(now))
      .length;
  if (overdue > 0) {
    score -= (overdue * 15).clamp(0, 40);
    factors.add(HealthFactor(
      label: '$overdue échéance${overdue > 1 ? 's' : ''} en retard',
      detail: 'Traitez ces alertes avant de présenter le véhicule.',
      impact: HealthImpact.negative,
    ));
  }

  final soon = activeReminders
      .where((r) =>
          r.dueDate != null &&
          !r.dueDate!.isBefore(now) &&
          r.dueDate!.difference(now).inDays <= 15)
      .length;
  if (soon > 0) {
    score -= (soon * 5).clamp(0, 15);
    factors.add(HealthFactor(
      label: '$soon échéance${soon > 1 ? 's' : ''} proche${soon > 1 ? 's' : ''}',
      detail: 'À anticiper avant la mise en vente.',
      impact: HealthImpact.negative,
    ));
  }

  if (overdue == 0 && soon == 0 && activeReminders.isNotEmpty) {
    factors.add(const HealthFactor(
      label: 'Aucune échéance urgente',
      detail: 'Tous les rappels actifs restent lointains.',
      impact: HealthImpact.positive,
    ));
  }

  final expiredDocs = documents
      .where((d) => d.computedStatus == DocumentVersionStatus.expired)
      .length;
  if (expiredDocs > 0) {
    score -= (expiredDocs * 10).clamp(0, 20);
    factors.add(HealthFactor(
      label: '$expiredDocs document${expiredDocs > 1 ? 's' : ''} expiré${expiredDocs > 1 ? 's' : ''}',
      detail: 'Renouvelez-les avant de vendre.',
      impact: HealthImpact.negative,
    ));
  } else if (documents.isNotEmpty) {
    factors.add(const HealthFactor(
      label: 'Documents à jour',
      detail: 'Aucun document expiré détecté.',
      impact: HealthImpact.positive,
    ));
  }

  if (maintenanceEntries.isEmpty) {
    score -= 10;
    factors.add(const HealthFactor(
      label: 'Aucun entretien enregistré',
      detail: 'Un historique d\'entretien rassure un acheteur.',
      impact: HealthImpact.negative,
    ));
  } else {
    final lastMaintenance =
        maintenanceEntries.map((m) => m.date).reduce((a, b) => a.isAfter(b) ? a : b);
    final monthsSince = now.difference(lastMaintenance).inDays / 30;
    if (monthsSince <= 6) {
      factors.add(const HealthFactor(
        label: 'Entretien récent',
        detail: 'Dernier entretien il y a moins de 6 mois.',
        impact: HealthImpact.positive,
      ));
    } else if (monthsSince > 12) {
      score -= 10;
      factors.add(const HealthFactor(
        label: 'Entretien ancien',
        detail: 'Dernier entretien il y a plus d\'un an.',
        impact: HealthImpact.negative,
      ));
    }
  }

  if (completeness >= 0.9) {
    factors.add(HealthFactor(
      label: 'Fiche très complète',
      detail: '${(completeness * 100).round()} % des informations renseignées.',
      impact: HealthImpact.positive,
    ));
  } else if (completeness < 0.5) {
    score -= 10;
    factors.add(const HealthFactor(
      label: 'Fiche incomplète',
      detail: 'Complétez la fiche véhicule pour rassurer un acheteur.',
      impact: HealthImpact.negative,
    ));
  }

  score = score.clamp(0, 100);
  if (factors.isEmpty) {
    factors.add(const HealthFactor(
      label: 'Pas encore assez de données',
      detail: 'Ajoutez entretiens, documents et informations pour affiner ce score.',
      impact: HealthImpact.neutral,
    ));
  }

  return VehicleHealthScore(score: score, factors: factors);
}
