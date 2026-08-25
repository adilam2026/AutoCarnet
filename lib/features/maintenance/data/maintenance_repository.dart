import 'dart:async';

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/database.dart';
import '../../../core/database/providers.dart';
import '../../../core/sync/sync_coordinator.dart';
import '../../../core/sync/sync_outbox_repository.dart';
import '../../../core/utils/id_generator.dart';
import '../../reminders/data/reminder_repository.dart';
import '../../timeline/data/timeline_repository.dart';
import '../../vehicles/data/vehicle_repository.dart';

class NewMaintenancePart {
  final String designation;
  final String? reference;
  final String? brand;
  final double quantity;
  final double unitPrice;
  const NewMaintenancePart({
    required this.designation,
    this.reference,
    this.brand,
    this.quantity = 1,
    this.unitPrice = 0,
  });
}

class MaintenanceRepository {
  MaintenanceRepository(
    this._db,
    this._timeline,
    this._reminders,
    this._vehicles, [
    this._sync,
    this._outbox,
  ]);
  final AppDatabase _db;
  final TimelineRepository _timeline;
  final ReminderRepository _reminders;
  final VehicleRepository _vehicles;
  // Optional (sync-hardening pass, after the GLC data-loss report) - see
  // VehicleRepository's identical fields for the full rationale. Nudges the
  // whole coordinator, not just maintenance_entries: an operation almost
  // always writes a linked expense too.
  final SyncCoordinator? _sync;
  final SyncOutboxRepository? _outbox;

  void _nudgeSync() {
    unawaited(_sync?.syncAll());
  }

  // Awaited, unlike _nudgeSync - see VehicleRepository's identical helper
  // for why (a local SQLite write, not a network call).
  Future<void> _enqueueOutbox(String entityId, String operation, {String entityType = 'maintenance'}) {
    return _outbox?.enqueue(entityType: entityType, entityId: entityId, operation: operation) ??
        Future.value();
  }

  Stream<List<MaintenanceEntry>> watchForVehicle(String vehicleId) {
    final query = _db.select(_db.maintenanceEntries)
      ..where((m) => m.vehicleId.equals(vehicleId) & m.isDeleted.equals(false))
      ..orderBy([(m) => OrderingTerm.desc(m.date)]);
    return query.watch();
  }

  Future<MaintenanceEntry?> getById(String id) {
    return (_db.select(_db.maintenanceEntries)..where((m) => m.id.equals(id)))
        .getSingleOrNull();
  }

  Stream<List<MaintenancePart>> watchParts(String maintenanceEntryId) {
    return (_db.select(_db.maintenanceParts)
          ..where((p) => p.maintenanceEntryId.equals(maintenanceEntryId)))
        .watch();
  }

  /// Creates an operation, optionally its parts, optionally a linked expense
  /// (RG-ENT-006), and always feeds the mileage history, timeline and
  /// reminders engine in one go (Principe 5).
  Future<String> createEntry({
    required String vehicleId,
    required String category,
    required DateTime date,
    required double mileage,
    String currency = 'MAD',
    String? providerId,
    double laborCost = 0,
    String? comments,
    DateTime? nextDueDate,
    double? nextDueMileage,
    List<NewMaintenancePart> parts = const [],
    bool createLinkedExpense = true,
  }) async {
    final id = newId();
    final now = DateTime.now();
    final partsCost =
        parts.fold<double>(0, (sum, p) => sum + p.quantity * p.unitPrice);
    final totalCost = partsCost + laborCost;

    String? linkedExpenseId;
    if (createLinkedExpense && totalCost > 0) {
      linkedExpenseId = newId();
    }

    await _db.into(_db.maintenanceEntries).insert(
          MaintenanceEntriesCompanion.insert(
            id: id,
            vehicleId: vehicleId,
            category: category,
            date: date,
            mileage: mileage,
            providerId: Value(providerId),
            partsCost: Value(partsCost),
            laborCost: Value(laborCost),
            currency: Value(currency),
            comments: Value(comments),
            nextDueDate: Value(nextDueDate),
            nextDueMileage: Value(nextDueMileage),
            linkedExpenseId: Value(linkedExpenseId),
            createdAt: now,
            updatedAt: now,
          ),
        );

    for (final part in parts) {
      await _db.into(_db.maintenanceParts).insert(
            MaintenancePartsCompanion.insert(
              id: newId(),
              maintenanceEntryId: id,
              designation: part.designation,
              reference: Value(part.reference),
              brand: Value(part.brand),
              quantity: Value(part.quantity),
              unitPrice: Value(part.unitPrice),
            ),
          );
    }

    if (linkedExpenseId != null) {
      await _db.into(_db.expenses).insert(
            ExpensesCompanion.insert(
              id: linkedExpenseId,
              vehicleId: vehicleId,
              category: category,
              date: date,
              amount: totalCost,
              currency: Value(currency),
              providerId: Value(providerId),
              mileage: Value(mileage),
              comments: Value('Généré depuis l\'entretien'),
              linkedMaintenanceId: Value(id),
              createdAt: now,
              updatedAt: now,
            ),
          );
    }

    await _vehicles.recordOperationMileage(
      vehicleId: vehicleId,
      value: mileage,
      source: 'maintenance',
      sourceId: id,
    );

    await _timeline.logEvent(
      vehicleId: vehicleId,
      moduleOrigin: 'maintenance',
      eventType: 'maintenance_added',
      title: category,
      description: comments,
      linkedEntityId: id,
      linkedEntityType: 'maintenance',
      occurredAt: date,
    );

    if (nextDueDate != null || nextDueMileage != null) {
      await _reminders.upsertForSource(
        vehicleId: vehicleId,
        sourceType: 'maintenance',
        sourceId: id,
        title: '$category à prévoir',
        dueDate: nextDueDate,
        dueMileage: nextDueMileage,
      );
    }

    await _reconcileCategoryReminders(vehicleId, category);

    await _enqueueOutbox(id, 'create');
    if (linkedExpenseId != null) await _enqueueOutbox(linkedExpenseId, 'create', entityType: 'expense');
    _nudgeSync();
    return id;
  }

  /// RG-ENT-010: for a given (vehicleId, category), only the operation that
  /// was actually performed most recently may drive an active échéance -
  /// never the order entries happened to be typed into the app. The
  /// reference is found from operationMileage/operationDate alone, exactly
  /// like a mechanic reading a paper carnet would: the entry with the
  /// highest mileage wins, ties broken by the latest date. createdAt is
  /// never consulted here - it's an audit detail, not automotive truth.
  ///
  /// Every other entry of that category keeps enriching historique,
  /// intervalles observés and statistiques, but its reminder (if any) is
  /// closed so it can never coexist with, or contradict, the current one.
  Future<void> _reconcileCategoryReminders(
    String vehicleId,
    String category,
  ) async {
    final entries = await (_db.select(_db.maintenanceEntries)
          ..where((m) =>
              m.vehicleId.equals(vehicleId) &
              m.category.equals(category) &
              m.isDeleted.equals(false)))
        .get();
    if (entries.isEmpty) return;

    entries.sort((a, b) {
      final byMileage = a.mileage.compareTo(b.mileage);
      if (byMileage != 0) return byMileage;
      return a.date.compareTo(b.date);
    });
    final reference = entries.last;

    for (final e in entries) {
      if (e.id == reference.id) continue;
      await _reminders.disableForSource('maintenance', e.id);
    }

    if (reference.nextDueDate != null || reference.nextDueMileage != null) {
      await _reminders.upsertForSource(
        vehicleId: vehicleId,
        sourceType: 'maintenance',
        sourceId: reference.id,
        title: '${reference.category} à prévoir',
        dueDate: reference.nextDueDate,
        dueMileage: reference.nextDueMileage,
      );
    }
  }

  /// Edits an existing operation in place: updates the entry, replaces its
  /// parts wholesale, keeps its linked expense (creating or dropping one if
  /// createLinkedExpense/cost changed) and its mileage-history row in sync,
  /// and regenerates its timeline entry and reminder instead of leaving
  /// stale ones behind.
  Future<void> updateEntry({
    required String id,
    required String vehicleId,
    required String category,
    required DateTime date,
    required double mileage,
    String currency = 'MAD',
    String? providerId,
    double laborCost = 0,
    String? comments,
    DateTime? nextDueDate,
    double? nextDueMileage,
    List<NewMaintenancePart> parts = const [],
    bool createLinkedExpense = true,
  }) async {
    final now = DateTime.now();
    final existing = await (_db.select(_db.maintenanceEntries)
          ..where((m) => m.id.equals(id)))
        .getSingle();
    final partsCost =
        parts.fold<double>(0, (sum, p) => sum + p.quantity * p.unitPrice);
    final totalCost = partsCost + laborCost;

    var linkedExpenseId = existing.linkedExpenseId;
    if (createLinkedExpense && totalCost > 0) {
      if (linkedExpenseId != null) {
        await (_db.update(_db.expenses)..where((e) => e.id.equals(linkedExpenseId!)))
            .write(ExpensesCompanion(
          category: Value(category),
          date: Value(date),
          amount: Value(totalCost),
          currency: Value(currency),
          providerId: Value(providerId),
          mileage: Value(mileage),
          updatedAt: Value(now),
        ));
      } else {
        linkedExpenseId = newId();
        await _db.into(_db.expenses).insert(
              ExpensesCompanion.insert(
                id: linkedExpenseId,
                vehicleId: vehicleId,
                category: category,
                date: date,
                amount: totalCost,
                currency: Value(currency),
                providerId: Value(providerId),
                mileage: Value(mileage),
                comments: const Value('Généré depuis l\'entretien'),
                linkedMaintenanceId: Value(id),
                createdAt: now,
                updatedAt: now,
              ),
            );
      }
    } else if (linkedExpenseId != null) {
      await (_db.update(_db.expenses)..where((e) => e.id.equals(linkedExpenseId!)))
          .write(ExpensesCompanion(
        isDeleted: const Value(true),
        updatedAt: Value(now),
      ));
      linkedExpenseId = null;
    }

    await (_db.update(_db.maintenanceEntries)..where((m) => m.id.equals(id)))
        .write(MaintenanceEntriesCompanion(
      category: Value(category),
      date: Value(date),
      mileage: Value(mileage),
      providerId: Value(providerId),
      partsCost: Value(partsCost),
      laborCost: Value(laborCost),
      currency: Value(currency),
      comments: Value(comments),
      nextDueDate: Value(nextDueDate),
      nextDueMileage: Value(nextDueMileage),
      linkedExpenseId: Value(linkedExpenseId),
      updatedAt: Value(now),
      // Sync-hardening pass: without this, editing an already-synced
      // operation would silently never reach the cloud again.
      syncStatus: const Value('pendingSync'),
    ));

    await (_db.delete(_db.maintenanceParts)
          ..where((p) => p.maintenanceEntryId.equals(id)))
        .go();
    for (final part in parts) {
      await _db.into(_db.maintenanceParts).insert(
            MaintenancePartsCompanion.insert(
              id: newId(),
              maintenanceEntryId: id,
              designation: part.designation,
              reference: Value(part.reference),
              brand: Value(part.brand),
              quantity: Value(part.quantity),
              unitPrice: Value(part.unitPrice),
            ),
          );
    }

    await _vehicles.updateOperationMileage(
      vehicleId: vehicleId,
      source: 'maintenance',
      sourceId: id,
      newValue: mileage,
    );

    // Same eventType/linkedEntityId as creation: logEvent upserts in place,
    // so the operation still appears as a single "$category" line reflecting
    // its current data, never a second "modifié" entry next to the original.
    await _timeline.logEvent(
      vehicleId: vehicleId,
      moduleOrigin: 'maintenance',
      eventType: 'maintenance_added',
      title: category,
      description: comments,
      linkedEntityId: id,
      linkedEntityType: 'maintenance',
      occurredAt: date,
    );

    if (nextDueDate != null || nextDueMileage != null) {
      await _reminders.upsertForSource(
        vehicleId: vehicleId,
        sourceType: 'maintenance',
        sourceId: id,
        title: '$category à prévoir',
        dueDate: nextDueDate,
        dueMileage: nextDueMileage,
      );
    } else {
      await _reminders.disableForSource('maintenance', id);
    }

    // The category (or the reference operation within it) may have just
    // changed - re-derive which entry is the true reference before leaving.
    if (existing.category != category) {
      await _reconcileCategoryReminders(vehicleId, existing.category);
    }
    await _reconcileCategoryReminders(vehicleId, category);

    await _enqueueOutbox(id, 'update');
    if (linkedExpenseId != null) await _enqueueOutbox(linkedExpenseId, 'update', entityType: 'expense');
    _nudgeSync();
  }

  Future<void> softDelete(String id) async {
    final entry =
        await (_db.select(_db.maintenanceEntries)..where((m) => m.id.equals(id)))
            .getSingleOrNull();
    final now = DateTime.now();
    await (_db.update(_db.maintenanceEntries)..where((m) => m.id.equals(id)))
        .write(MaintenanceEntriesCompanion(
      isDeleted: const Value(true),
      updatedAt: Value(now),
      syncStatus: const Value('pendingSync'),
    ));
    if (entry?.linkedExpenseId != null) {
      // Never leave the auto-generated expense behind pointing at a
      // deleted operation - it was never independently editable, it
      // shouldn't be independently deletable-and-forgotten either.
      await (_db.update(_db.expenses)
            ..where((e) => e.id.equals(entry!.linkedExpenseId!)))
          .write(ExpensesCompanion(
        isDeleted: const Value(true),
        updatedAt: Value(now),
        syncStatus: const Value('pendingSync'),
      ));
      await _enqueueOutbox(entry!.linkedExpenseId!, 'delete', entityType: 'expense');
    }
    await _reminders.disableForSource('maintenance', id);
    await _timeline.removeForEntity('maintenance', id);
    if (entry != null) {
      await _reconcileCategoryReminders(entry.vehicleId, entry.category);
    }
    await _enqueueOutbox(id, 'delete');
    _nudgeSync();
  }
}

final maintenanceRepositoryProvider = Provider<MaintenanceRepository>((ref) {
  return MaintenanceRepository(
    ref.watch(appDatabaseProvider),
    ref.watch(timelineRepositoryProvider),
    ref.watch(reminderRepositoryProvider),
    ref.watch(vehicleRepositoryProvider),
    ref.watch(syncCoordinatorProvider),
    ref.watch(syncOutboxRepositoryProvider),
  );
});

final vehicleMaintenanceProvider =
    StreamProvider.family<List<MaintenanceEntry>, String>((ref, vehicleId) {
  return ref.watch(maintenanceRepositoryProvider).watchForVehicle(vehicleId);
});

final maintenancePartsProvider =
    StreamProvider.family<List<MaintenancePart>, String>((ref, entryId) {
  return ref.watch(maintenanceRepositoryProvider).watchParts(entryId);
});
