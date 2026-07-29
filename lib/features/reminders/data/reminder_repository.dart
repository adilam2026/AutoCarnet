import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/database.dart';
import '../../../core/database/providers.dart';
import '../../../core/utils/id_generator.dart';

/// Central reminder engine (RG-ALR-001): documents, maintenance, etc. never
/// manage their own notifications, they call [upsertForSource] instead.
class ReminderRepository {
  ReminderRepository(this._db);
  final AppDatabase _db;

  /// Creates or replaces the single reminder tied to a given source
  /// (a document version, a maintenance entry...). Renewing a document or
  /// editing a maintenance's next-due simply calls this again - the old
  /// reminder is superseded automatically (RG-ALR-005).
  Future<void> upsertForSource({
    required String vehicleId,
    required String sourceType,
    required String sourceId,
    required String title,
    DateTime? dueDate,
    double? dueMileage,
    String priority = 'normal',
  }) async {
    final existing = await (_db.select(_db.reminders)
          ..where((r) =>
              r.sourceType.equals(sourceType) & r.sourceId.equals(sourceId)))
        .getSingleOrNull();

    if (dueDate == null && dueMileage == null) {
      if (existing != null) {
        await disable(existing.id);
      }
      return;
    }

    if (existing != null) {
      await (_db.update(_db.reminders)..where((r) => r.id.equals(existing.id)))
          .write(RemindersCompanion(
        title: Value(title),
        dueDate: Value(dueDate),
        dueMileage: Value(dueMileage),
        priority: Value(priority),
        status: const Value(ReminderStatus.active),
        updatedAt: Value(DateTime.now()),
      ));
    } else {
      await _db.into(_db.reminders).insert(
            RemindersCompanion.insert(
              id: newId(),
              vehicleId: vehicleId,
              sourceType: sourceType,
              sourceId: sourceId,
              title: title,
              dueDate: Value(dueDate),
              dueMileage: Value(dueMileage),
              priority: Value(priority),
              createdAt: DateTime.now(),
              updatedAt: DateTime.now(),
            ),
          );
    }
  }

  Future<void> disable(String reminderId) {
    return (_db.update(_db.reminders)..where((r) => r.id.equals(reminderId)))
        .write(RemindersCompanion(
      status: const Value(ReminderStatus.dismissed),
      updatedAt: Value(DateTime.now()),
    ));
  }

  /// Disables whichever reminder is tied to a given source (a document
  /// version, a maintenance entry...) without the caller needing to know
  /// the reminder's own id.
  Future<void> disableForSource(String sourceType, String sourceId) {
    return (_db.update(_db.reminders)
          ..where((r) =>
              r.sourceType.equals(sourceType) & r.sourceId.equals(sourceId)))
        .write(RemindersCompanion(
      status: const Value(ReminderStatus.dismissed),
      updatedAt: Value(DateTime.now()),
    ));
  }

  /// RG-ALR-007: a sold/archived/destroyed vehicle no longer needs future
  /// reminders.
  Future<void> disableAllForVehicle(String vehicleId) {
    return (_db.update(_db.reminders)..where((r) => r.vehicleId.equals(vehicleId)))
        .write(RemindersCompanion(
      status: const Value(ReminderStatus.dismissed),
      updatedAt: Value(DateTime.now()),
    ));
  }

  Future<void> snooze(String reminderId, DateTime until) {
    return (_db.update(_db.reminders)..where((r) => r.id.equals(reminderId)))
        .write(RemindersCompanion(
      status: const Value(ReminderStatus.snoozed),
      snoozedUntil: Value(until),
      updatedAt: Value(DateTime.now()),
    ));
  }

  Stream<List<Reminder>> watchActiveForVehicle(String vehicleId) {
    final query = _db.select(_db.reminders)
      ..where((r) =>
          r.vehicleId.equals(vehicleId) &
          r.status.equalsValue(ReminderStatus.active))
      ..orderBy([(r) => OrderingTerm.asc(r.dueDate)]);
    return query.watch();
  }

  Stream<List<Reminder>> watchAllActive() {
    final query = _db.select(_db.reminders)
      ..where((r) => r.status.equalsValue(ReminderStatus.active))
      ..orderBy([(r) => OrderingTerm.asc(r.dueDate)]);
    return query.watch();
  }
}

final reminderRepositoryProvider = Provider<ReminderRepository>((ref) {
  return ReminderRepository(ref.watch(appDatabaseProvider));
});

final vehicleActiveRemindersProvider =
    StreamProvider.family<List<Reminder>, String>((ref, vehicleId) {
  return ref.watch(reminderRepositoryProvider).watchActiveForVehicle(vehicleId);
});

final allActiveRemindersProvider = StreamProvider<List<Reminder>>((ref) {
  return ref.watch(reminderRepositoryProvider).watchAllActive();
});
