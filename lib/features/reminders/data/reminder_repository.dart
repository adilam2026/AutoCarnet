import 'dart:async';

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/database.dart';
import '../../../core/database/providers.dart';
import '../../../core/sync/sync_coordinator.dart';
import '../../../core/sync/sync_outbox_repository.dart';
import '../../../core/utils/id_generator.dart';
import '../../account/data/account_repository.dart';

/// Central reminder engine (RG-ALR-001): documents, maintenance, etc. never
/// manage their own notifications, they call [upsertForSource] instead.
class ReminderRepository {
  ReminderRepository(this._db, [this._sync, this._outbox]);
  final AppDatabase _db;
  // Optional (sync-hardening pass, after the GLC data-loss report) - see
  // VehicleRepository's identical fields for the full rationale.
  final SyncCoordinator? _sync;
  final SyncOutboxRepository? _outbox;

  void _nudgeSync() {
    unawaited(_sync?.syncAll());
  }

  // Awaited, unlike _nudgeSync - see VehicleRepository's identical helper
  // for why (a local SQLite write, not a network call).
  Future<void> _enqueueOutbox(String reminderId, String operation) {
    return _outbox?.enqueue(entityType: 'reminder', entityId: reminderId, operation: operation) ??
        Future.value();
  }

  /// Creates or replaces the single reminder tied to a given source
  /// (a document version, a maintenance entry...). Renewing a document or
  /// editing a maintenance's next-due simply calls this again - the old
  /// reminder is superseded automatically (RG-ALR-005).
  ///
  /// [vehicleId] is null for a personal (driver-level) reminder - a permis
  /// de conduire, not tied to any one vehicle. [createdBy] is required in
  /// that case (there's no vehicle-ownership join to scope it by instead -
  /// see [_scopedQuery]); for a vehicle-scoped reminder it's optional and
  /// left to sync to fill in on push, exactly as before.
  Future<void> upsertForSource({
    required String? vehicleId,
    required String sourceType,
    required String sourceId,
    required String title,
    DateTime? dueDate,
    double? dueMileage,
    String priority = 'normal',
    String? createdBy,
  }) async {
    await _db.transaction(() async {
      final existing = await (_db.select(_db.reminders)
            ..where((r) =>
                r.sourceType.equals(sourceType) & r.sourceId.equals(sourceId)))
          .getSingleOrNull();

      if (dueDate == null && dueMileage == null) {
        if (existing != null) {
          await _disable(existing.id);
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
          // Sync-hardening pass: without this, an updated échéance on an
          // already-synced reminder would silently never re-reach the cloud.
          syncStatus: const Value('pendingSync'),
        ));
        await _enqueueOutbox(existing.id, 'update');
      } else {
        final id = newId();
        await _db.into(_db.reminders).insert(
              RemindersCompanion.insert(
                id: id,
                vehicleId: Value(vehicleId),
                sourceType: sourceType,
                sourceId: sourceId,
                title: title,
                dueDate: Value(dueDate),
                dueMileage: Value(dueMileage),
                priority: Value(priority),
                createdBy: Value(createdBy),
                createdAt: DateTime.now(),
                updatedAt: DateTime.now(),
              ),
            );
        await _enqueueOutbox(id, 'create');
      }
    });
    _nudgeSync();
  }

  Future<void> disable(String reminderId) async {
    await _db.transaction(() => _disable(reminderId));
    _nudgeSync();
  }

  Future<void> _disable(String reminderId) async {
    await (_db.update(_db.reminders)..where((r) => r.id.equals(reminderId)))
        .write(RemindersCompanion(
      status: const Value(ReminderStatus.dismissed),
      updatedAt: Value(DateTime.now()),
      syncStatus: const Value('pendingSync'),
    ));
    await _enqueueOutbox(reminderId, 'update');
  }

  /// Disables whichever reminder is tied to a given source (a document
  /// version, a maintenance entry...) without the caller needing to know
  /// the reminder's own id.
  Future<void> disableForSource(String sourceType, String sourceId) async {
    await _db.transaction(() async {
      final existing = await (_db.select(_db.reminders)
            ..where((r) =>
                r.sourceType.equals(sourceType) & r.sourceId.equals(sourceId)))
          .getSingleOrNull();
      await (_db.update(_db.reminders)
            ..where((r) =>
                r.sourceType.equals(sourceType) & r.sourceId.equals(sourceId)))
          .write(RemindersCompanion(
        status: const Value(ReminderStatus.dismissed),
        updatedAt: Value(DateTime.now()),
        syncStatus: const Value('pendingSync'),
      ));
      if (existing != null) await _enqueueOutbox(existing.id, 'update');
    });
    _nudgeSync();
  }

  /// RG-ALR-007: a sold/archived/destroyed vehicle no longer needs future
  /// reminders.
  Future<void> disableAllForVehicle(String vehicleId) async {
    await _db.transaction(() async {
      final affected = await (_db.select(_db.reminders)
            ..where((r) => r.vehicleId.equals(vehicleId)))
          .get();
      await (_db.update(_db.reminders)..where((r) => r.vehicleId.equals(vehicleId)))
          .write(RemindersCompanion(
        status: const Value(ReminderStatus.dismissed),
        updatedAt: Value(DateTime.now()),
        syncStatus: const Value('pendingSync'),
      ));
      for (final r in affected) {
        await _enqueueOutbox(r.id, 'update');
      }
    });
    _nudgeSync();
  }

  Future<void> snooze(String reminderId, DateTime until) async {
    await _db.transaction(() async {
      await (_db.update(_db.reminders)..where((r) => r.id.equals(reminderId)))
          .write(RemindersCompanion(
        status: const Value(ReminderStatus.snoozed),
        snoozedUntil: Value(until),
        updatedAt: Value(DateTime.now()),
        syncStatus: const Value('pendingSync'),
      ));
      await _enqueueOutbox(reminderId, 'update');
    });
    _nudgeSync();
  }

  Stream<List<Reminder>> watchActiveForVehicle(String vehicleId) {
    final query = _db.select(_db.reminders)
      ..where((r) =>
          r.vehicleId.equals(vehicleId) &
          r.status.equalsValue(ReminderStatus.active))
      ..orderBy([(r) => OrderingTerm.asc(r.dueDate)]);
    return query.watch();
  }

  /// [currentUserId] scopes results to vehicles visible to the signed-in
  /// account, the same rule as VehicleRepository.watchAll (owned, unowned/
  /// unsynced, or shared) - every reminder always belongs to exactly one
  /// vehicle, so a reminder for a vehicle a different account owns must
  /// never surface here just because it's still sitting in this device's
  /// local cache.
  Stream<List<Reminder>> watchAllActive({String? currentUserId}) {
    final query = _scopedQuery(currentUserId)
      ..where(_db.reminders.status.equalsValue(ReminderStatus.active));
    query.orderBy([OrderingTerm.asc(_db.reminders.dueDate)]);
    return query.watch().map((rows) => rows.map((r) => r.readTable(_db.reminders)).toList());
  }

  /// Every reminder regardless of status, so the Alertes screen can also
  /// show what's already been handled ("Traitées" filter) instead of only
  /// ever showing what's still outstanding. See [watchAllActive] for
  /// [currentUserId].
  Stream<List<Reminder>> watchAll({String? currentUserId}) {
    final query = _scopedQuery(currentUserId)
      ..orderBy([OrderingTerm.asc(_db.reminders.dueDate)]);
    return query.watch().map((rows) => rows.map((r) => r.readTable(_db.reminders)).toList());
  }

  /// Left join (not inner): a personal reminder (vehicleId null - permis de
  /// conduire) has no matching vehicle row at all, and must still surface
  /// here rather than silently vanishing. It's scoped by [createdBy]
  /// instead of vehicle ownership - the same "unowned/mine" pattern every
  /// other per-account table in this app uses (see VehicleRepository.
  /// watchAll, DocumentRepository.watchDriverDocuments).
  JoinedSelectStatement _scopedQuery(String? currentUserId) {
    final query = _db.select(_db.reminders).join([
      leftOuterJoin(_db.vehicles, _db.vehicles.id.equalsExp(_db.reminders.vehicleId)),
    ]);
    if (currentUserId != null) {
      query.where(
        (_db.reminders.vehicleId.isNull() &
                (_db.reminders.createdBy.isNull() |
                    _db.reminders.createdBy.equals(currentUserId))) |
            (_db.reminders.vehicleId.isNotNull() &
                (_db.vehicles.ownerId.isNull() |
                    _db.vehicles.ownerId.equals(currentUserId) |
                    _db.vehicles.myRole.isNotNull())),
      );
    }
    return query;
  }
}

final reminderRepositoryProvider = Provider<ReminderRepository>((ref) {
  return ReminderRepository(
    ref.watch(appDatabaseProvider),
    ref.watch(syncCoordinatorProvider),
    ref.watch(syncOutboxRepositoryProvider),
  );
});

final vehicleActiveRemindersProvider =
    StreamProvider.family<List<Reminder>, String>((ref, vehicleId) {
  return ref.watch(reminderRepositoryProvider).watchActiveForVehicle(vehicleId);
});

final allActiveRemindersProvider = StreamProvider<List<Reminder>>((ref) {
  ref.watch(authStateChangesProvider);
  final currentUserId = ref.watch(accountRepositoryProvider).currentUser?.id;
  return ref.watch(reminderRepositoryProvider).watchAllActive(currentUserId: currentUserId);
});

final allRemindersProvider = StreamProvider<List<Reminder>>((ref) {
  ref.watch(authStateChangesProvider);
  final currentUserId = ref.watch(accountRepositoryProvider).currentUser?.id;
  return ref.watch(reminderRepositoryProvider).watchAll(currentUserId: currentUserId);
});
