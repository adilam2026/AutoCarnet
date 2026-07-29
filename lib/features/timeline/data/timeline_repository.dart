import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/database.dart';
import '../../../core/database/providers.dart';
import '../../../core/utils/id_generator.dart';

/// Timeline never receives writes from the UI (RG-TIME-002). Other
/// repositories call [logEvent] right after they persist their own change,
/// which is the only place TimelineEvents rows are created.
class TimelineRepository {
  TimelineRepository(this._db);
  final AppDatabase _db;

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
  }) {
    return _db.into(_db.timelineEvents).insert(
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
