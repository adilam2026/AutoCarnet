import 'package:drift/drift.dart' show Value;

import '../database/database.dart';

/// Pure mapping for `public.fuel_entries` - see vehicle_sync_mapping.dart.
Map<String, dynamic> fuelEntryToRemoteRow(FuelEntry f) {
  return {
    'id': f.id,
    'vehicle_id': f.vehicleId,
    'date': f.date.toUtc().toIso8601String(),
    'mileage': f.mileage,
    'provider_id': f.providerId,
    'fuel_type': f.fuelType,
    'quantity_liters': f.quantityLiters,
    'price_per_liter': f.pricePerLiter,
    'total_amount': f.totalAmount,
    'is_full_tank': f.isFullTank,
    'comments': f.comments,
    'linked_expense_id': f.linkedExpenseId,
    'created_at': f.createdAt.toUtc().toIso8601String(),
    'updated_at': f.updatedAt.toUtc().toIso8601String(),
    'is_deleted': f.isDeleted,
  };
}

FuelEntriesCompanion fuelEntryFromRemoteRow(Map<String, dynamic> row) {
  DateTime? parseDate(Object? value) =>
      value == null ? null : DateTime.parse(value as String).toLocal();

  return FuelEntriesCompanion.insert(
    id: row['id'] as String,
    vehicleId: row['vehicle_id'] as String,
    date: parseDate(row['date'])!,
    mileage: (row['mileage'] as num).toDouble(),
    fuelType: row['fuel_type'] as String,
    quantityLiters: (row['quantity_liters'] as num).toDouble(),
    pricePerLiter: (row['price_per_liter'] as num).toDouble(),
    totalAmount: (row['total_amount'] as num).toDouble(),
    createdAt: parseDate(row['created_at'])!,
    updatedAt: parseDate(row['updated_at'])!,
    providerId: Value(row['provider_id'] as String?),
    isFullTank: Value(row['is_full_tank'] as bool? ?? true),
    comments: Value(row['comments'] as String?),
    linkedExpenseId: Value(row['linked_expense_id'] as String?),
    isDeleted: Value(row['is_deleted'] as bool? ?? false),
    syncStatus: const Value('synced'),
    version: Value(row['version'] as int? ?? 0),
    createdBy: Value(row['created_by'] as String?),
    updatedBy: Value(row['updated_by'] as String?),
  );
}
