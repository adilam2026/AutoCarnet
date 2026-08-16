import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../../core/database/database.dart';
import '../../documents/data/document_repository.dart';
import 'resale_estimation.dart';
import 'resale_health.dart';
import 'resale_readiness.dart';

/// Builds the resale dossier PDF (bloc 18 §18.4) entirely from data already
/// collected in the carnet - vehicle sheet, health score, readiness
/// checklist and maintenance/expense history. No market price is printed
/// unless [estimate] carries real amounts (see [ResaleEstimator]).
class ResalePdfReport {
  const ResalePdfReport();

  Future<Uint8List> build({
    required Vehicle vehicle,
    required VehicleHealthScore health,
    required ResaleEstimate estimate,
    required ResaleReadiness readiness,
    required List<MaintenanceEntry> maintenanceEntries,
    required List<DocumentWithVersion> documents,
    String? ownerName,
  }) async {
    final doc = pw.Document();
    final now = DateTime.now();

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        header: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              'Dossier de revente — ${vehicle.brand} ${vehicle.model}',
              style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold),
            ),
            pw.Text(
              'Généré le ${_fmt(now)} avec AutoCarnet',
              style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600),
            ),
            pw.Divider(),
          ],
        ),
        build: (context) => [
          _sectionTitle('Fiche véhicule'),
          _vehicleTable(vehicle, ownerName),
          pw.SizedBox(height: 16),
          _sectionTitle('Santé du carnet — ${health.score}/100'),
          pw.Bullet(
            text: 'Score calculé à partir des échéances, entretiens, '
                'documents et de la complétude de la fiche.',
            style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
          ),
          for (final factor in health.factors)
            pw.Bullet(text: '${factor.label} — ${factor.detail}'),
          pw.SizedBox(height: 16),
          _sectionTitle('Estimation de revente'),
          if (!estimate.isAvailable)
            pw.Text(estimate.message, style: const pw.TextStyle(fontSize: 10))
          else
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                for (final tier in resaleEstimateTierDefinitions)
                  if (estimate.amountsByTier.containsKey(tier.label))
                    pw.Text(
                      '${tier.label} : '
                      '${estimate.amountsByTier[tier.label]!.toStringAsFixed(0)}',
                    ),
                pw.SizedBox(height: 4),
                pw.Text(estimate.message, style: const pw.TextStyle(fontSize: 9)),
              ],
            ),
          pw.SizedBox(height: 16),
          _sectionTitle('Préparation à la vente'),
          pw.Table(
            border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
            columnWidths: {0: const pw.FlexColumnWidth(2), 1: const pw.FlexColumnWidth(3)},
            children: [
              for (final item in readiness.items)
                pw.TableRow(children: [
                  pw.Padding(
                    padding: const pw.EdgeInsets.all(4),
                    child: pw.Text(
                      '${item.ok ? 'OK' : '!'} ${item.label}',
                      style: pw.TextStyle(
                        fontSize: 9,
                        fontWeight: pw.FontWeight.bold,
                        color: item.ok ? PdfColors.green800 : PdfColors.orange800,
                      ),
                    ),
                  ),
                  pw.Padding(
                    padding: const pw.EdgeInsets.all(4),
                    child: pw.Text(item.detail, style: const pw.TextStyle(fontSize: 9)),
                  ),
                ]),
            ],
          ),
          if (readiness.recommendations.isNotEmpty) ...[
            pw.SizedBox(height: 8),
            pw.Text('Recommandations :', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
            for (final r in readiness.recommendations) pw.Bullet(text: r, style: const pw.TextStyle(fontSize: 9)),
          ],
          pw.SizedBox(height: 16),
          _sectionTitle('Historique d\'entretien (${maintenanceEntries.length})'),
          if (maintenanceEntries.isEmpty)
            pw.Text('Aucun entretien enregistré.', style: const pw.TextStyle(fontSize: 10))
          else
            pw.Table(
              border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
              columnWidths: {
                0: const pw.FlexColumnWidth(1.2),
                1: const pw.FlexColumnWidth(2),
                2: const pw.FlexColumnWidth(1.2),
                3: const pw.FlexColumnWidth(1.2),
              },
              children: [
                pw.TableRow(
                  decoration: const pw.BoxDecoration(color: PdfColors.grey200),
                  children: [
                    _cellHeader('Date'),
                    _cellHeader('Catégorie'),
                    _cellHeader('Km'),
                    _cellHeader('Coût'),
                  ],
                ),
                for (final m in [...maintenanceEntries]..sort((a, b) => b.date.compareTo(a.date)))
                  pw.TableRow(children: [
                    _cell(_fmt(m.date)),
                    _cell(m.category),
                    _cell(m.mileage.toStringAsFixed(0)),
                    _cell((m.partsCost + m.laborCost).toStringAsFixed(0)),
                  ]),
              ],
            ),
          pw.SizedBox(height: 16),
          _sectionTitle('Documents (${documents.length})'),
          if (documents.isEmpty)
            pw.Text('Aucun document ajouté.', style: const pw.TextStyle(fontSize: 10))
          else
            for (final d in documents)
              pw.Bullet(
                text: '${d.document.type} — ${_docStatusLabel(d.computedStatus)}'
                    '${d.version?.expiryDate != null ? ' (expire le ${_fmt(d.version!.expiryDate!)})' : ''}',
                style: const pw.TextStyle(fontSize: 9),
              ),
        ],
        footer: (context) => pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.Text(
            'Page ${context.pageNumber}/${context.pagesCount}',
            style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey500),
          ),
        ),
      ),
    );

    return doc.save();
  }

  pw.Widget _sectionTitle(String title) => pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 6),
        child: pw.Text(title, style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold)),
      );

  pw.Widget _vehicleTable(Vehicle v, String? ownerName) {
    final rows = <List<String>>[
      ['Marque / Modèle', '${v.brand} ${v.model}${v.trim != null ? ' ${v.trim}' : ''}'],
      if (v.year != null) ['Année', '${v.year}'],
      ['Kilométrage', '${v.currentMileage.toStringAsFixed(0)} km'],
      if (v.vin != null) ['VIN', v.vin!],
      if (v.plate != null) ['Immatriculation', v.plate!],
      if (v.fuelType != null) ['Carburant', v.fuelType!],
      if (v.transmission != null) ['Boîte', v.transmission!],
      if (v.color != null) ['Couleur', v.color!],
      if (ownerName != null) ['Propriétaire', ownerName],
    ];
    return pw.Table(
      columnWidths: {0: const pw.FlexColumnWidth(1.3), 1: const pw.FlexColumnWidth(2.5)},
      children: [
        for (final r in rows)
          pw.TableRow(children: [
            pw.Padding(
              padding: const pw.EdgeInsets.symmetric(vertical: 2),
              child: pw.Text(r[0], style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
            ),
            pw.Padding(
              padding: const pw.EdgeInsets.symmetric(vertical: 2),
              child: pw.Text(r[1], style: const pw.TextStyle(fontSize: 9)),
            ),
          ]),
      ],
    );
  }

  pw.Widget _cellHeader(String text) => pw.Padding(
        padding: const pw.EdgeInsets.all(4),
        child: pw.Text(text, style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
      );

  pw.Widget _cell(String text) => pw.Padding(
        padding: const pw.EdgeInsets.all(4),
        child: pw.Text(text, style: const pw.TextStyle(fontSize: 9)),
      );

  String _fmt(DateTime d) => '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  String _docStatusLabel(DocumentVersionStatus s) => switch (s) {
        DocumentVersionStatus.valid => 'valide',
        DocumentVersionStatus.expiringSoon => 'expire bientôt',
        DocumentVersionStatus.expired => 'expiré',
        DocumentVersionStatus.archived => 'archivé',
        DocumentVersionStatus.replaced => 'remplacé',
      };
}
