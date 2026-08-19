import 'package:drift/drift.dart' show Value;

import '../database/database.dart';

/// Pure mapping between the local Drift [Vehicle] row and the JSON shape
/// Supabase's `public.vehicles` table expects/returns - kept dependency-free
/// (no Supabase import) so it's trivially unit-testable without a network.
/// `photo_path` is deliberately never synced: it's a local filesystem path,
/// meaningless on another device (real photo sync needs Supabase Storage,
/// not built yet - see supabase/README.md).
/// `user_id` (the owner) is deliberately never sent: it defaults to
/// auth.uid() on a real insert, and on an upsert-as-update PostgREST leaves
/// omitted columns untouched - so a collaborator's push can never
/// accidentally reassign ownership, and the owner's own push never needs
/// to re-assert it either.
Map<String, dynamic> vehicleToRemoteRow(Vehicle v) {
  return {
    'id': v.id,
    'brand': v.brand,
    'model': v.model,
    'trim': v.trim,
    'year': v.year,
    'first_registration_date': v.firstRegistrationDate?.toUtc().toIso8601String(),
    'vin': v.vin,
    'plate': v.plate,
    'motorization': v.motorization,
    'fiscal_power': v.fiscalPower,
    'fuel_type': v.fuelType,
    'transmission': v.transmission,
    'color': v.color,
    'acquisition_date': v.acquisitionDate?.toUtc().toIso8601String(),
    'purchase_price': v.purchasePrice,
    'condition': v.condition?.name,
    'comments': v.comments,
    'current_mileage': v.currentMileage,
    'status': v.status.name,
    'created_at': v.createdAt.toUtc().toIso8601String(),
    'updated_at': v.updatedAt.toUtc().toIso8601String(),
    'is_deleted': v.isDeleted,
  };
}

VehiclesCompanion vehicleFromRemoteRow(Map<String, dynamic> row) {
  DateTime? parseDate(Object? value) =>
      value == null ? null : DateTime.parse(value as String).toLocal();

  return VehiclesCompanion.insert(
    id: row['id'] as String,
    brand: row['brand'] as String,
    model: row['model'] as String,
    ownerId: Value(row['user_id'] as String?),
    currentMileage: (row['current_mileage'] as num).toDouble(),
    createdAt: parseDate(row['created_at'])!,
    updatedAt: parseDate(row['updated_at'])!,
    trim: Value(row['trim'] as String?),
    year: Value(row['year'] as int?),
    firstRegistrationDate: Value(parseDate(row['first_registration_date'])),
    vin: Value(row['vin'] as String?),
    plate: Value(row['plate'] as String?),
    motorization: Value(row['motorization'] as String?),
    fiscalPower: Value(row['fiscal_power'] as String?),
    fuelType: Value(row['fuel_type'] as String?),
    transmission: Value(row['transmission'] as String?),
    color: Value(row['color'] as String?),
    acquisitionDate: Value(parseDate(row['acquisition_date'])),
    purchasePrice: Value((row['purchase_price'] as num?)?.toDouble()),
    condition: Value(_enumFromName(VehicleCondition.values, row['condition'] as String?)),
    comments: Value(row['comments'] as String?),
    status: Value(
        _enumFromName(VehicleStatus.values, row['status'] as String?) ?? VehicleStatus.active),
    isDeleted: Value(row['is_deleted'] as bool? ?? false),
    // This row just came from the cloud - it's already in sync by
    // definition, never mark it pending again.
    syncStatus: const Value('synced'),
  );
}

T? _enumFromName<T extends Enum>(List<T> values, String? name) {
  if (name == null) return null;
  for (final v in values) {
    if (v.name == name) return v;
  }
  return null;
}
