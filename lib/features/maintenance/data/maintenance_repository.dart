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

  Future<void> softDelete(String id) async {
    await (_db.update(_db.maintenanceEntries)..where((m) => m.id.equals(id)))
        .write(MaintenanceEntriesCompanion(
      isDeleted: const Value(true),
      updatedAt: Value(DateTime.now()),
    ));
    await _reminders.disableForSource('maintenance', id);
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
