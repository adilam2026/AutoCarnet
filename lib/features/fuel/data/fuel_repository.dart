import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/database.dart';
import '../../../core/database/providers.dart';
import '../../../core/utils/id_generator.dart';
import '../../timeline/data/timeline_repository.dart';
import '../../vehicles/data/vehicle_repository.dart';

class FuelStats {
  /// L/100km, computed only between consecutive full tanks (RG-CARB-005).
  final double? averageConsumption;
  final double totalLiters;
  final double totalCost;
  const FuelStats({
    this.averageConsumption,
    required this.totalLiters,
    required this.totalCost,
  });
}

class FuelRepository {
  FuelRepository(this._db, this._timeline, this._vehicles);
  final AppDatabase _db;
  final TimelineRepository _timeline;
  final VehicleRepository _vehicles;

  Stream<List<FuelEntry>> watchForVehicle(String vehicleId) {
    final query = _db.select(_db.fuelEntries)
      ..where((f) => f.vehicleId.equals(vehicleId) & f.isDeleted.equals(false))
      ..orderBy([(f) => OrderingTerm.desc(f.date)]);
    return query.watch();
  }

  Future<String> createEntry({
    required String vehicleId,
    required DateTime date,
    required double mileage,
    required String fuelType,
    required double quantityLiters,
    required double pricePerLiter,
    String? providerId,
    bool isFullTank = true,
    String? comments,
    bool createLinkedExpense = true,
  }) async {
    final id = newId();
    final now = DateTime.now();
    final totalAmount = quantityLiters * pricePerLiter;

    String? linkedExpenseId;
    if (createLinkedExpense) linkedExpenseId = newId();

    await _db.into(_db.fuelEntries).insert(
          FuelEntriesCompanion.insert(
            id: id,
            vehicleId: vehicleId,
            date: date,
            mileage: mileage,
            providerId: Value(providerId),
            fuelType: fuelType,
            quantityLiters: quantityLiters,
            pricePerLiter: pricePerLiter,
            totalAmount: totalAmount,
            isFullTank: Value(isFullTank),
            comments: Value(comments),
            linkedExpenseId: Value(linkedExpenseId),
            createdAt: now,
            updatedAt: now,
          ),
        );

    if (linkedExpenseId != null) {
      await _db.into(_db.expenses).insert(
            ExpensesCompanion.insert(
              id: linkedExpenseId,
              vehicleId: vehicleId,
              category: 'Carburant',
              date: date,
              amount: totalAmount,
              providerId: Value(providerId),
              mileage: Value(mileage),
              comments: const Value('Généré depuis un plein'),
              linkedFuelId: Value(id),
              createdAt: now,
              updatedAt: now,
            ),
          );
    }

    await _vehicles.recordOperationMileage(
      vehicleId: vehicleId,
      value: mileage,
      source: 'fuel',
      sourceId: id,
    );

    await _timeline.logEvent(
      vehicleId: vehicleId,
      moduleOrigin: 'fuel',
      eventType: 'fuel_added',
      title: 'Plein ${isFullTank ? 'complet' : 'partiel'} — '
          '${quantityLiters.toStringAsFixed(1)} L',
      linkedEntityId: id,
      linkedEntityType: 'fuel',
      occurredAt: date,
    );

    return id;
  }

  Future<void> softDelete(String id) {
    return (_db.update(_db.fuelEntries)..where((f) => f.id.equals(id))).write(
      FuelEntriesCompanion(
        isDeleted: const Value(true),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  /// RG-CARB-005: consumption is only computed between two consecutive full
  /// tanks. A partial fill between them still counts towards the liters
  /// consumed over that distance (it just tops up before the cycle closes),
  /// but a cycle is never opened or closed on a partial fill itself.
  FuelStats computeStats(List<FuelEntry> entries) {
    final chronological = [...entries]..sort((a, b) => a.date.compareTo(b.date));
    final totalLiters =
        chronological.fold<double>(0, (s, e) => s + e.quantityLiters);
    final totalCost =
        chronological.fold<double>(0, (s, e) => s + e.totalAmount);

    final fullTankIndices = <int>[
      for (var i = 0; i < chronological.length; i++)
        if (chronological[i].isFullTank) i,
    ];
    if (fullTankIndices.length < 2) {
      return FuelStats(totalLiters: totalLiters, totalCost: totalCost);
    }

    double litersConsumed = 0;
    double distanceCovered = 0;
    for (var c = 0; c < fullTankIndices.length - 1; c++) {
      final startIndex = fullTankIndices[c];
      final endIndex = fullTankIndices[c + 1];
      final start = chronological[startIndex];
      final end = chronological[endIndex];
      final distance = end.mileage - start.mileage;
      if (distance <= 0) continue;
      final litersInCycle = chronological
          .sublist(startIndex + 1, endIndex + 1)
          .fold<double>(0, (s, e) => s + e.quantityLiters);
      litersConsumed += litersInCycle;
      distanceCovered += distance;
    }

    final avg = distanceCovered > 0
        ? (litersConsumed / distanceCovered) * 100
        : null;

    return FuelStats(
      averageConsumption: avg,
      totalLiters: totalLiters,
      totalCost: totalCost,
    );
  }
}

final fuelRepositoryProvider = Provider<FuelRepository>((ref) {
  return FuelRepository(
    ref.watch(appDatabaseProvider),
    ref.watch(timelineRepositoryProvider),
    ref.watch(vehicleRepositoryProvider),
  );
});

final vehicleFuelEntriesProvider =
    StreamProvider.family<List<FuelEntry>, String>((ref, vehicleId) {
  return ref.watch(fuelRepositoryProvider).watchForVehicle(vehicleId);
});

final vehicleFuelStatsProvider =
    Provider.family<AsyncValue<FuelStats>, String>((ref, vehicleId) {
  final entries = ref.watch(vehicleFuelEntriesProvider(vehicleId));
  return entries.whenData(
    (list) => ref.watch(fuelRepositoryProvider).computeStats(list),
  );
});
