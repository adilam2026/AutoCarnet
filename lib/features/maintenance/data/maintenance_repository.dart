import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/database.dart';
import '../../../core/database/providers.dart';
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
    this._vehicles,
  );
  final AppDatabase _db;
  final TimelineRepository _timeline;
  final ReminderRepository _reminders;
  final VehicleRepository _vehicles;

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

    return id;
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
    ));
    if (entry?.linkedExpenseId != null) {
      // Never leave the auto-generated expense behind pointing at a
      // deleted operation - it was never independently editable, it
      // shouldn't be independently deletable-and-forgotten either.
      await (_db.update(_db.expenses)
            ..where((e) => e.id.equals(entry!.linkedExpenseId!)))
          .write(ExpensesCompanion(isDeleted: const Value(true), updatedAt: Value(now)));
    }
    await _reminders.disableForSource('maintenance', id);
    await _timeline.removeForEntity('maintenance', id);
  }
}

final maintenanceRepositoryProvider = Provider<MaintenanceRepository>((ref) {
  return MaintenanceRepository(
    ref.watch(appDatabaseProvider),
    ref.watch(timelineRepositoryProvider),
    ref.watch(reminderRepositoryProvider),
    ref.watch(vehicleRepositoryProvider),
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
