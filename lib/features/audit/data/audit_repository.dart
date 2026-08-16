import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/database.dart';
import '../../../core/database/providers.dart';
import '../../../core/utils/id_generator.dart';

/// Technical/CRUD trail, kept strictly separate from the driver-facing
/// business history (TimelineRepository) - see bloc "Journal d'audit".
/// Data-entry facts (a field changed, a record was created) live here;
/// real automobile interventions never do.
class AuditRepository {
  AuditRepository(this._db);
  final AppDatabase _db;

  Future<void> log({
    String? vehicleId,
    required String entityType,
    String? entityId,
    required String action,
    required String summary,
    DateTime? occurredAt,
  }) {
    return _db.into(_db.auditEvents).insert(
          AuditEventsCompanion.insert(
            id: newId(),
            vehicleId: Value(vehicleId),
            entityType: entityType,
            entityId: Value(entityId),
            action: action,
            summary: summary,
            occurredAt: occurredAt ?? DateTime.now(),
            createdAt: DateTime.now(),
          ),
        );
  }

  Stream<List<AuditEvent>> watchAll() {
    final query = _db.select(_db.auditEvents)
      ..orderBy([(a) => OrderingTerm.desc(a.occurredAt)]);
    return query.watch();
  }

  Stream<List<AuditEvent>> watchForVehicle(String vehicleId) {
    final query = _db.select(_db.auditEvents)
      ..where((a) => a.vehicleId.equals(vehicleId))
      ..orderBy([(a) => OrderingTerm.desc(a.occurredAt)]);
    return query.watch();
  }
}

final auditRepositoryProvider = Provider<AuditRepository>((ref) {
  return AuditRepository(ref.watch(appDatabaseProvider));
});

final allAuditEventsProvider = StreamProvider<List<AuditEvent>>((ref) {
  return ref.watch(auditRepositoryProvider).watchAll();
});
