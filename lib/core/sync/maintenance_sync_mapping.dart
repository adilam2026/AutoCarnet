import 'package:drift/drift.dart' show Value;

import '../database/database.dart';

/// Pure mapping between the local Drift [MaintenanceEntry]/[MaintenancePart]
/// rows and the JSON shape `public.maintenance_entries`/`maintenance_parts`
/// expect/return - see vehicle_sync_mapping.dart for why this stays
/// dependency-free. `version`/`created_by`/`updated_by` are deliberately
/// not set here, same reason as vehicles: only the sync service knows the
/// signed-in account id and the row's expected version.
Map<String, dynamic> maintenanceEntryToRemoteRow(MaintenanceEntry e) {
  return {
    'id': e.id,
    'vehicle_id': e.vehicleId,
    'category': e.category,
    'date': e.date.toUtc().toIso8601String(),
    'mileage': e.mileage,
    'provider_id': e.providerId,
    'parts_cost': e.partsCost,
    'labor_cost': e.laborCost,
    'currency': e.currency,
    'warranty_months': e.warrantyMonths,
    'comments': e.comments,
    'next_due_date': e.nextDueDate?.toUtc().toIso8601String(),
    'next_due_mileage': e.nextDueMileage,
    'linked_expense_id': e.linkedExpenseId,
    'created_at': e.createdAt.toUtc().toIso8601String(),
    'updated_at': e.updatedAt.toUtc().toIso8601String(),
    'is_deleted': e.isDeleted,
  };
}

MaintenanceEntriesCompanion maintenanceEntryFromRemoteRow(Map<String, dynamic> row) {
  DateTime? parseDate(Object? value) =>
      value == null ? null : DateTime.parse(value as String).toLocal();

  return MaintenanceEntriesCompanion.insert(
    id: row['id'] as String,
    vehicleId: row['vehicle_id'] as String,
    category: row['category'] as String,
    date: parseDate(row['date'])!,
    mileage: (row['mileage'] as num).toDouble(),
    createdAt: parseDate(row['created_at'])!,
    updatedAt: parseDate(row['updated_at'])!,
    providerId: Value(row['provider_id'] as String?),
    partsCost: Value((row['parts_cost'] as num?)?.toDouble() ?? 0),
    laborCost: Value((row['labor_cost'] as num?)?.toDouble() ?? 0),
    currency: Value(row['currency'] as String? ?? 'MAD'),
    warrantyMonths: Value(row['warranty_months'] as int?),
    comments: Value(row['comments'] as String?),
    nextDueDate: Value(parseDate(row['next_due_date'])),
    nextDueMileage: Value((row['next_due_mileage'] as num?)?.toDouble()),
    linkedExpenseId: Value(row['linked_expense_id'] as String?),
    isDeleted: Value(row['is_deleted'] as bool? ?? false),
    syncStatus: const Value('synced'),
    version: Value(row['version'] as int? ?? 0),
    createdBy: Value(row['created_by'] as String?),
    updatedBy: Value(row['updated_by'] as String?),
  );
}

Map<String, dynamic> maintenancePartToRemoteRow(MaintenancePart p) {
  return {
    'id': p.id,
    'maintenance_entry_id': p.maintenanceEntryId,
    'designation': p.designation,
    'reference': p.reference,
    'brand': p.brand,
    'quantity': p.quantity,
    'unit_price': p.unitPrice,
    'comments': p.comments,
  };
}

MaintenancePartsCompanion maintenancePartFromRemoteRow(Map<String, dynamic> row) {
  return MaintenancePartsCompanion.insert(
    id: row['id'] as String,
    maintenanceEntryId: row['maintenance_entry_id'] as String,
    designation: row['designation'] as String,
    reference: Value(row['reference'] as String?),
    brand: Value(row['brand'] as String?),
    quantity: Value((row['quantity'] as num?)?.toDouble() ?? 1),
    unitPrice: Value((row['unit_price'] as num?)?.toDouble() ?? 0),
    comments: Value(row['comments'] as String?),
  );
}
