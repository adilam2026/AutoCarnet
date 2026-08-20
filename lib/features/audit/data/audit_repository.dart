import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/database.dart';
import '../../../core/database/providers.dart';
import '../../../core/utils/id_generator.dart';
import '../../account/data/account_repository.dart';

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

  /// [currentUserId] scopes results the same way as
  /// VehicleRepository.watchAll: an event tied to a vehicle a different
  /// account owns must never surface here just because it's still sitting
  /// in this device's local cache. An event with no vehicleId at all
  /// (account-level, not tied to any vehicle) is always visible.
  Stream<List<AuditEvent>> watchAll({String? currentUserId}) {
    final query = _db.select(_db.auditEvents).join([
      leftOuterJoin(_db.vehicles, _db.vehicles.id.equalsExp(_db.auditEvents.vehicleId)),
    ]);
    if (currentUserId != null) {
      query.where(
        _db.auditEvents.vehicleId.isNull() |
            _db.vehicles.ownerId.isNull() |
            _db.vehicles.ownerId.equals(currentUserId) |
            _db.vehicles.myRole.isNotNull(),
      );
    }
    query.orderBy([OrderingTerm.desc(_db.auditEvents.occurredAt)]);
    return query.watch().map((rows) => rows.map((r) => r.readTable(_db.auditEvents)).toList());
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
  ref.watch(authStateChangesProvider);
  final currentUserId = ref.watch(accountRepositoryProvider).currentUser?.id;
  return ref.watch(auditRepositoryProvider).watchAll(currentUserId: currentUserId);
});
