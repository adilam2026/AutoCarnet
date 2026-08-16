import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/database.dart';
import '../../../core/database/providers.dart';
import '../../../core/utils/id_generator.dart';

/// Timeline never receives writes from the UI (RG-TIME-002). Other
/// repositories call [logEvent] right after they persist their own change,
/// which is the only place TimelineEvents rows are created. This is the
/// driver-facing BUSINESS history - the life of the vehicle - never a CRUD
/// log; technical/audit facts belong in AuditRepository instead.
class TimelineRepository {
  TimelineRepository(this._db);
  final AppDatabase _db;

  /// Upserts by (linkedEntityType, linkedEntityId) when both are given: an
  /// operation's business event always reflects its current state, editing
  /// it must never leave a second stale "created" row next to it (RG:
  /// "éviter les doublons" - one intervention, one line).
  Future<void> logEvent({
    required String vehicleId,
    required String moduleOrigin,
    required String eventType,
    required String title,
    String? description,
    String importance = 'normal',
    String? linkedEntityId,
    String? linkedEntityType,
    DateTime? occurredAt,
  }) async {
    if (linkedEntityId != null && linkedEntityType != null) {
      final existing = await (_db.select(_db.timelineEvents)
            ..where((t) =>
                t.linkedEntityType.equals(linkedEntityType) &
                t.linkedEntityId.equals(linkedEntityId)))
          .getSingleOrNull();
      if (existing != null) {
        await (_db.update(_db.timelineEvents)..where((t) => t.id.equals(existing.id)))
            .write(TimelineEventsCompanion(
          eventType: Value(eventType),
          title: Value(title),
          description: Value(description),
          occurredAt: Value(occurredAt ?? DateTime.now()),
          importance: Value(importance),
        ));
        return;
      }
    }
    await _db.into(_db.timelineEvents).insert(
          TimelineEventsCompanion.insert(
            id: newId(),
            vehicleId: vehicleId,
            moduleOrigin: moduleOrigin,
            eventType: eventType,
            title: title,
            description: Value(description),
            occurredAt: occurredAt ?? DateTime.now(),
            importance: Value(importance),
            linkedEntityId: Value(linkedEntityId),
            linkedEntityType: Value(linkedEntityType),
            createdAt: DateTime.now(),
          ),
        );
  }

  Future<void> removeForEntity(String linkedEntityType, String linkedEntityId) {
    return (_db.delete(_db.timelineEvents)
          ..where((t) =>
              t.linkedEntityType.equals(linkedEntityType) &
              t.linkedEntityId.equals(linkedEntityId)))
        .go();
  }

  Stream<List<TimelineEvent>> watchForVehicle(String vehicleId) {
    final query = _db.select(_db.timelineEvents)
      ..where((t) => t.vehicleId.equals(vehicleId))
      ..orderBy([(t) => OrderingTerm.desc(t.occurredAt)]);
    return query.watch();
  }
}

final timelineRepositoryProvider = Provider<TimelineRepository>((ref) {
  return TimelineRepository(ref.watch(appDatabaseProvider));
});

final vehicleTimelineProvider =
    StreamProvider.family<List<TimelineEvent>, String>((ref, vehicleId) {
  return ref.watch(timelineRepositoryProvider).watchForVehicle(vehicleId);
});
