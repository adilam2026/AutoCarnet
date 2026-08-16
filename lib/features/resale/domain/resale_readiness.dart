import '../../../core/database/database.dart';
import '../../documents/data/document_repository.dart';

class ResaleReadinessItem {
  final String label;
  final String detail;
  final bool ok;
  const ResaleReadinessItem({
    required this.label,
    required this.detail,
    required this.ok,
  });
}

class ResaleReadiness {
  final double completeness;
  final int maintenanceCount;
  final int documentsCount;
  final int expiredDocumentsCount;
  final int overdueReminders;
  final int mileageHistoryCount;
  final List<ResaleReadinessItem> items;
  final List<String> recommendations;
  const ResaleReadiness({
    required this.completeness,
    required this.maintenanceCount,
    required this.documentsCount,
    required this.expiredDocumentsCount,
    required this.overdueReminders,
    required this.mileageHistoryCount,
    required this.items,
    required this.recommendations,
  });
}

/// Everything here is a direct read of data the owner already entered
/// elsewhere in the carnet (Principe 2) - nothing is inferred or invented.
ResaleReadiness computeResaleReadiness({
  required double completeness,
  required List<MaintenanceEntry> maintenanceEntries,
  required List<DocumentWithVersion> documents,
  required List<Reminder> activeReminders,
  required List<MileageEntry> mileageHistory,
}) {
  final expiredDocs = documents
      .where((d) => d.computedStatus == DocumentVersionStatus.expired)
      .length;
  final overdue = activeReminders
      .where((r) => r.dueDate != null && r.dueDate!.isBefore(DateTime.now()))
      .length;

  final items = <ResaleReadinessItem>[
    ResaleReadinessItem(
      label: 'Fiche véhicule complétée',
      detail: '${(completeness * 100).round()} % des champs renseignés',
      ok: completeness >= 0.8,
    ),
    ResaleReadinessItem(
      label: 'Historique d\'entretien',
      detail: maintenanceEntries.isEmpty
          ? 'Aucun entretien enregistré'
          : '${maintenanceEntries.length} entretien(s) enregistré(s)',
      ok: maintenanceEntries.isNotEmpty,
    ),
    ResaleReadinessItem(
      label: 'Documents à jour',
      detail: documents.isEmpty
          ? 'Aucun document ajouté'
          : expiredDocs == 0
              ? '${documents.length} document(s), tous à jour'
              : '$expiredDocs document(s) expiré(s) sur ${documents.length}',
      ok: documents.isNotEmpty && expiredDocs == 0,
    ),
    ResaleReadinessItem(
      label: 'Échéances traitées',
      detail: overdue == 0
          ? 'Aucune échéance en retard'
          : '$overdue échéance(s) en retard',
      ok: overdue == 0,
    ),
    ResaleReadinessItem(
      label: 'Suivi kilométrique',
      detail: mileageHistory.length <= 1
          ? 'Kilométrage jamais mis à jour depuis la création'
          : '${mileageHistory.length} relevés enregistrés',
      ok: mileageHistory.length > 1,
    ),
  ];

  final recommendations = <String>[
    for (final item in items)
      if (!item.ok) _recommendationFor(item.label),
  ];

  return ResaleReadiness(
    completeness: completeness,
    maintenanceCount: maintenanceEntries.length,
    documentsCount: documents.length,
    expiredDocumentsCount: expiredDocs,
    overdueReminders: overdue,
    mileageHistoryCount: mileageHistory.length,
    items: items,
    recommendations: recommendations,
  );
}

String _recommendationFor(String label) {
  switch (label) {
    case 'Fiche véhicule complétée':
      return 'Complétez la fiche véhicule (VIN, plaque, motorisation...).';
    case 'Historique d\'entretien':
      return 'Ajoutez au moins un entretien pour montrer un suivi sérieux.';
    case 'Documents à jour':
      return 'Ajoutez ou renouvelez les documents du véhicule.';
    case 'Échéances traitées':
      return 'Traitez les échéances en retard avant de publier l\'annonce.';
    case 'Suivi kilométrique':
      return 'Mettez à jour le kilométrage pour un historique crédible.';
    default:
      return 'Complétez ce point avant la mise en vente.';
  }
}
