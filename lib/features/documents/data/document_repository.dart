import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/database.dart';
import '../../../core/database/providers.dart';
import '../../../core/utils/id_generator.dart';
import '../../reminders/data/reminder_repository.dart';
import '../../timeline/data/timeline_repository.dart';
import '../domain/document_renewal_rules.dart';

/// A document + the state of its currently active version, joined for
/// convenient display (list screens never need to know about the
/// version/attachment split).
class DocumentWithVersion {
  final Document document;
  final DocumentVersion? version;
  DocumentWithVersion(this.document, this.version);

  DocumentVersionStatus get computedStatus {
    final v = version;
    if (v == null) return DocumentVersionStatus.valid;
    if (v.status == DocumentVersionStatus.replaced ||
        v.status == DocumentVersionStatus.archived) {
      return v.status;
    }
    final expiry = v.expiryDate;
    if (expiry == null) return DocumentVersionStatus.valid;
    final now = DateTime.now();
    if (expiry.isBefore(now)) return DocumentVersionStatus.expired;
    if (expiry.difference(now).inDays <= 30) {
      return DocumentVersionStatus.expiringSoon;
    }
    return DocumentVersionStatus.valid;
  }
}

class DocumentRepository {
  DocumentRepository(this._db, this._timeline, this._reminders);
  final AppDatabase _db;
  final TimelineRepository _timeline;
  final ReminderRepository _reminders;

  Future<DocumentWithVersion?> getById(String id) async {
    final doc = await (_db.select(_db.documents)..where((d) => d.id.equals(id)))
        .getSingleOrNull();
    if (doc == null) return null;
    DocumentVersion? version;
    if (doc.currentVersionId != null) {
      version = await (_db.select(_db.documentVersions)
            ..where((v) => v.id.equals(doc.currentVersionId!)))
          .getSingleOrNull();
    }
    return DocumentWithVersion(doc, version);
  }

  Stream<List<DocumentWithVersion>> watchForVehicle(String vehicleId) {
    final query = _db.select(_db.documents)
      ..where((d) => d.vehicleId.equals(vehicleId) & d.isDeleted.equals(false))
      ..orderBy([(d) => OrderingTerm.desc(d.updatedAt)]);
    return query.watch().asyncMap(_withVersions);
  }

  /// Driver documents (permis de conduire, pièce d'identité...) are not
  /// tied to a single vehicle - they belong to the profile and are shared
  /// across the whole garage.
  Stream<List<DocumentWithVersion>> watchDriverDocuments() {
    final query = _db.select(_db.documents)
      ..where((d) => d.vehicleId.isNull() & d.isDeleted.equals(false))
      ..orderBy([(d) => OrderingTerm.desc(d.updatedAt)]);
    return query.watch().asyncMap(_withVersions);
  }

  Future<List<DocumentWithVersion>> _withVersions(List<Document> docs) async {
    final result = <DocumentWithVersion>[];
    for (final d in docs) {
      DocumentVersion? version;
      if (d.currentVersionId != null) {
        version = await (_db.select(_db.documentVersions)
              ..where((v) => v.id.equals(d.currentVersionId!)))
            .getSingleOrNull();
      }
      result.add(DocumentWithVersion(d, version));
    }
    return result;
  }

  Future<List<DocumentAttachment>> attachmentsFor(String versionId) {
    return (_db.select(_db.documentAttachments)
          ..where((a) => a.documentVersionId.equals(versionId)))
        .get();
  }

  /// Creates a brand new logical document with its first version.
  Future<String> createDocument({
    required String? vehicleId,
    required String type,
    String? holder,
    String? documentNumber,
    DateTime? issueDate,
    DateTime? expiryDate,
    double? cost,
    String? providerId,
    String? comments,
  }) async {
    final docId = newId();
    final versionId = newId();
    final now = DateTime.now();
    await _db.into(_db.documents).insert(
          DocumentsCompanion.insert(
            id: docId,
            vehicleId: Value(vehicleId),
            type: type,
            holder: Value(holder),
            currentVersionId: Value(versionId),
            createdAt: now,
            updatedAt: now,
          ),
        );
    await _db.into(_db.documentVersions).insert(
          DocumentVersionsCompanion.insert(
            id: versionId,
            documentId: docId,
            documentNumber: Value(documentNumber),
            issueDate: Value(issueDate),
            expiryDate: Value(expiryDate),
            cost: Value(cost),
            providerId: Value(providerId),
            comments: Value(comments),
            createdAt: now,
          ),
        );
    if (vehicleId != null) {
      await _timeline.logEvent(
        vehicleId: vehicleId,
        moduleOrigin: 'documents',
        eventType: 'document_added',
        title: '$type ajouté',
        linkedEntityId: docId,
        linkedEntityType: 'document',
        occurredAt: now,
      );
      if (expiryDate != null) {
        await _reminders.upsertForSource(
          vehicleId: vehicleId,
          sourceType: 'document',
          sourceId: versionId,
          title: _reminderTitle(type, expiryDate),
          dueDate: expiryDate,
        );
      }
    }
    return docId;
  }

  /// A civil-year-bound document (vignette) reads better as "Vignette 2027
  /// à payer" than a generic "à renouveler" - every other type keeps the
  /// generic wording.
  String _reminderTitle(String type, DateTime expiryDate) {
    if (isCivilYearBound(type)) return '$type ${expiryDate.year} à payer';
    return '$type à renouveler';
  }

  /// Renewal creates a new version and flips the previous one to "replaced"
  /// - history is never overwritten (RG-DOC-002/003) and reminders are
  /// regenerated automatically (RG-ALR-005).
  Future<void> renewDocument({
    required String documentId,
    String? documentNumber,
    DateTime? issueDate,
    DateTime? expiryDate,
    double? cost,
    String? providerId,
    String? comments,
  }) async {
    final doc = await (_db.select(_db.documents)
          ..where((d) => d.id.equals(documentId)))
        .getSingle();
    final now = DateTime.now();

    if (doc.currentVersionId != null) {
      await (_db.update(_db.documentVersions)
            ..where((v) => v.id.equals(doc.currentVersionId!)))
          .write(const DocumentVersionsCompanion(
        status: Value(DocumentVersionStatus.replaced),
      ));
      if (doc.vehicleId != null) {
        await _reminders.disableForSource('document', doc.currentVersionId!);
      }
    }

    final newVersionId = newId();
    await _db.into(_db.documentVersions).insert(
          DocumentVersionsCompanion.insert(
            id: newVersionId,
            documentId: documentId,
            documentNumber: Value(documentNumber),
            issueDate: Value(issueDate),
            expiryDate: Value(expiryDate),
            cost: Value(cost),
            providerId: Value(providerId),
            comments: Value(comments),
            createdAt: now,
          ),
        );
    await (_db.update(_db.documents)..where((d) => d.id.equals(documentId)))
        .write(DocumentsCompanion(
      currentVersionId: Value(newVersionId),
      updatedAt: Value(now),
    ));

    if (doc.vehicleId != null) {
      await _timeline.logEvent(
        vehicleId: doc.vehicleId!,
        moduleOrigin: 'documents',
        eventType: 'document_renewed',
        title: '${doc.type} renouvelé',
        linkedEntityId: documentId,
        linkedEntityType: 'document',
        occurredAt: now,
      );
      if (expiryDate != null) {
        await _reminders.upsertForSource(
          vehicleId: doc.vehicleId!,
          sourceType: 'document',
          sourceId: newVersionId,
          title: _reminderTitle(doc.type, expiryDate),
          dueDate: expiryDate,
        );
      }
    }
  }

  Future<void> softDelete(String documentId) async {
    await (_db.update(_db.documents)..where((d) => d.id.equals(documentId)))
        .write(DocumentsCompanion(
      isDeleted: const Value(true),
      updatedAt: Value(DateTime.now()),
    ));
    await _timeline.removeForEntity('document', documentId);
  }
}

final documentRepositoryProvider = Provider<DocumentRepository>((ref) {
  return DocumentRepository(
    ref.watch(appDatabaseProvider),
    ref.watch(timelineRepositoryProvider),
    ref.watch(reminderRepositoryProvider),
  );
});

final vehicleDocumentsProvider =
    StreamProvider.family<List<DocumentWithVersion>, String>((ref, vehicleId) {
  return ref.watch(documentRepositoryProvider).watchForVehicle(vehicleId);
});

final driverDocumentsProvider = StreamProvider<List<DocumentWithVersion>>((ref) {
  return ref.watch(documentRepositoryProvider).watchDriverDocuments();
});
