import 'dart:async';

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/database.dart';
import '../../../core/database/providers.dart';
import '../../../core/sync/sync_coordinator.dart';
import '../../../core/sync/sync_outbox_repository.dart';
import '../../../core/utils/id_generator.dart';
import '../../account/data/account_repository.dart';
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
  DocumentRepository(
    this._db,
    this._timeline,
    this._reminders, [
    this._sync,
    this._outbox,
  ]);
  final AppDatabase _db;
  final TimelineRepository _timeline;
  final ReminderRepository _reminders;
  // Optional (sync-hardening pass, after the GLC data-loss report) - see
  // VehicleRepository's identical fields for the full rationale.
  final SyncCoordinator? _sync;
  final SyncOutboxRepository? _outbox;

  void _nudgeSync() {
    unawaited(_sync?.syncAll());
  }

  // Awaited, unlike _nudgeSync - see VehicleRepository's identical helper
  // for why (a local SQLite write, not a network call).
  Future<void> _enqueueOutbox(String entityId, String operation, {String entityType = 'document'}) {
    return _outbox?.enqueue(entityType: entityType, entityId: entityId, operation: operation) ??
        Future.value();
  }

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
  /// across the whole garage. [currentUserId] keeps two different accounts
  /// that have used the same physical device from seeing each other's
  /// identity documents - these carry no vehicle to scope by, so they're
  /// tagged with their creator's account id directly (see
  /// [createDocument]/[handleAccountSwitch]).
  Stream<List<DocumentWithVersion>> watchDriverDocuments({String? currentUserId}) {
    final query = _db.select(_db.documents)
      ..where((d) => d.vehicleId.isNull() & d.isDeleted.equals(false));
    if (currentUserId != null) {
      query.where((d) => d.ownerId.isNull() | d.ownerId.equals(currentUserId));
    }
    query.orderBy([(d) => OrderingTerm.desc(d.updatedAt)]);
    return query.watch().asyncMap(_withVersions);
  }

  /// Account-switch safety net for driver documents only - a
  /// vehicle-scoped document's visibility already follows its vehicle
  /// (see VehicleRepository.handleAccountSwitch). Nothing is ever
  /// deleted.
  Future<void> handleAccountSwitch(String previousOwnerId) async {
    await (_db.update(_db.documents)..where((d) => d.vehicleId.isNull() & d.ownerId.isNull()))
        .write(DocumentsCompanion(ownerId: Value(previousOwnerId)));
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
    String? currentUserId,
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
            ownerId: Value(currentUserId),
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
      // A driver document (permis...) never appears in a vehicle's own
      // timeline - it doesn't belong to one, so there's nothing to log
      // here for that case.
      await _timeline.logEvent(
        vehicleId: vehicleId,
        moduleOrigin: 'documents',
        eventType: 'document_added',
        title: '$type ajouté',
        linkedEntityId: docId,
        linkedEntityType: 'document',
        occurredAt: now,
      );
    }
    if (expiryDate != null) {
      // A driver document's reminder is personal (no vehicleId), scoped by
      // its creator instead - see ReminderRepository._scopedQuery. This is
      // the ONE reminder for this document regardless of how many vehicles
      // the owner has (mission: never duplicated per vehicle).
      await _reminders.upsertForSource(
        vehicleId: vehicleId,
        sourceType: 'document',
        sourceId: versionId,
        title: _reminderTitle(type, expiryDate),
        dueDate: expiryDate,
        createdBy: currentUserId,
      );
    }
    await _enqueueOutbox(docId, 'create');
    await _enqueueOutbox(versionId, 'create', entityType: 'document_version');
    _nudgeSync();
    return docId;
  }

  /// A civil-year-bound document (vignette) reads better as "Vignette 2026
  /// à payer" than a generic "à renouveler" - every other type keeps the
  /// generic wording. [expiryDate] is the grace-period end (31/01 of the
  /// year after the vignette's own year - see civilYearDueDate), so the
  /// vignette's year is always expiryDate.year - 1.
  String _reminderTitle(String type, DateTime expiryDate) {
    if (isCivilYearBound(type)) return '$type ${expiryDate.year - 1} à payer';
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
    String? currentUserId,
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
        // Sync-hardening pass: without this, replacing an already-synced
        // version would silently never push that "replaced" status.
        syncStatus: Value('pendingSync'),
      ));
      await _reminders.disableForSource('document', doc.currentVersionId!);
      await _enqueueOutbox(doc.currentVersionId!, 'update', entityType: 'document_version');
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
      syncStatus: const Value('pendingSync'),
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
    }
    if (expiryDate != null) {
      await _reminders.upsertForSource(
        vehicleId: doc.vehicleId,
        sourceType: 'document',
        sourceId: newVersionId,
        title: _reminderTitle(doc.type, expiryDate),
        dueDate: expiryDate,
        createdBy: currentUserId ?? doc.ownerId,
      );
    }

    await _enqueueOutbox(documentId, 'update');
    await _enqueueOutbox(newVersionId, 'create', entityType: 'document_version');
    _nudgeSync();
  }

  Future<void> softDelete(String documentId) async {
    await (_db.update(_db.documents)..where((d) => d.id.equals(documentId)))
        .write(DocumentsCompanion(
      isDeleted: const Value(true),
      updatedAt: Value(DateTime.now()),
      syncStatus: const Value('pendingSync'),
    ));
    await _timeline.removeForEntity('document', documentId);
    await _enqueueOutbox(documentId, 'delete');
    _nudgeSync();
  }
}

final documentRepositoryProvider = Provider<DocumentRepository>((ref) {
  return DocumentRepository(
    ref.watch(appDatabaseProvider),
    ref.watch(timelineRepositoryProvider),
    ref.watch(reminderRepositoryProvider),
    ref.watch(syncCoordinatorProvider),
    ref.watch(syncOutboxRepositoryProvider),
  );
});

final vehicleDocumentsProvider =
    StreamProvider.family<List<DocumentWithVersion>, String>((ref, vehicleId) {
  return ref.watch(documentRepositoryProvider).watchForVehicle(vehicleId);
});

final driverDocumentsProvider = StreamProvider<List<DocumentWithVersion>>((ref) {
  ref.watch(authStateChangesProvider);
  final currentUserId = ref.watch(accountRepositoryProvider).currentUser?.id;
  return ref.watch(documentRepositoryProvider).watchDriverDocuments(currentUserId: currentUserId);
});
