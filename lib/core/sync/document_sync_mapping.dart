import 'package:drift/drift.dart' show Value;

import '../database/database.dart';

/// Pure mapping for `public.documents` - see vehicle_sync_mapping.dart for
/// the rationale. `Document.ownerId` doubles as this row's "created by"
/// (see its own doc comment in tables.dart), so it is what's sent as
/// `created_by` on a first insert - never re-derived from the session at
/// push time the way every other table's created_by is, since a document's
/// creator was already fixed the moment it was created, offline or not.
Map<String, dynamic> documentToRemoteRow(Document d) {
  return {
    'id': d.id,
    'vehicle_id': d.vehicleId,
    'type': d.type,
    'holder': d.holder,
    'current_version_id': d.currentVersionId,
    'is_deleted': d.isDeleted,
    'created_at': d.createdAt.toUtc().toIso8601String(),
    'updated_at': d.updatedAt.toUtc().toIso8601String(),
  };
}

DocumentsCompanion documentFromRemoteRow(Map<String, dynamic> row) {
  DateTime? parseDate(Object? value) =>
      value == null ? null : DateTime.parse(value as String).toLocal();

  return DocumentsCompanion.insert(
    id: row['id'] as String,
    type: row['type'] as String,
    createdAt: parseDate(row['created_at'])!,
    updatedAt: parseDate(row['updated_at'])!,
    vehicleId: Value(row['vehicle_id'] as String?),
    holder: Value(row['holder'] as String?),
    currentVersionId: Value(row['current_version_id'] as String?),
    isDeleted: Value(row['is_deleted'] as bool? ?? false),
    ownerId: Value(row['created_by'] as String?),
    syncStatus: const Value('synced'),
    version: Value(row['version'] as int? ?? 0),
    updatedBy: Value(row['updated_by'] as String?),
  );
}

Map<String, dynamic> documentVersionToRemoteRow(DocumentVersion v) {
  return {
    'id': v.id,
    'document_id': v.documentId,
    'document_number': v.documentNumber,
    'issue_date': v.issueDate?.toUtc().toIso8601String(),
    'expiry_date': v.expiryDate?.toUtc().toIso8601String(),
    'cost': v.cost,
    'provider_id': v.providerId,
    'comments': v.comments,
    'status': v.status.name,
    'created_at': v.createdAt.toUtc().toIso8601String(),
    'updated_at': (v.updatedAt ?? v.createdAt).toUtc().toIso8601String(),
  };
}

DocumentVersionsCompanion documentVersionFromRemoteRow(Map<String, dynamic> row) {
  DateTime? parseDate(Object? value) =>
      value == null ? null : DateTime.parse(value as String).toLocal();

  return DocumentVersionsCompanion.insert(
    id: row['id'] as String,
    documentId: row['document_id'] as String,
    createdAt: parseDate(row['created_at'])!,
    documentNumber: Value(row['document_number'] as String?),
    issueDate: Value(parseDate(row['issue_date'])),
    expiryDate: Value(parseDate(row['expiry_date'])),
    cost: Value((row['cost'] as num?)?.toDouble()),
    providerId: Value(row['provider_id'] as String?),
    comments: Value(row['comments'] as String?),
    status: Value(_statusFromName(row['status'] as String?)),
    updatedAt: Value(parseDate(row['updated_at'])),
    syncStatus: const Value('synced'),
    version: Value(row['version'] as int? ?? 0),
    createdBy: Value(row['created_by'] as String?),
    updatedBy: Value(row['updated_by'] as String?),
  );
}

DocumentVersionStatus _statusFromName(String? name) {
  for (final v in DocumentVersionStatus.values) {
    if (v.name == name) return v;
  }
  return DocumentVersionStatus.valid;
}
