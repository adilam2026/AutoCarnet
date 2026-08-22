import 'package:drift/drift.dart' show Value;

import '../database/database.dart';

/// Pure mapping for `public.expenses` - see vehicle_sync_mapping.dart.
Map<String, dynamic> expenseToRemoteRow(Expense e) {
  return {
    'id': e.id,
    'vehicle_id': e.vehicleId,
    'category': e.category,
    'date': e.date.toUtc().toIso8601String(),
    'amount': e.amount,
    'currency': e.currency,
    'provider_id': e.providerId,
    'mileage': e.mileage,
    'payment_method': e.paymentMethod,
    'comments': e.comments,
    'linked_maintenance_id': e.linkedMaintenanceId,
    'linked_fuel_id': e.linkedFuelId,
    'linked_document_version_id': e.linkedDocumentVersionId,
    'created_at': e.createdAt.toUtc().toIso8601String(),
    'updated_at': e.updatedAt.toUtc().toIso8601String(),
    'is_deleted': e.isDeleted,
  };
}

ExpensesCompanion expenseFromRemoteRow(Map<String, dynamic> row) {
  DateTime? parseDate(Object? value) =>
      value == null ? null : DateTime.parse(value as String).toLocal();

  return ExpensesCompanion.insert(
    id: row['id'] as String,
    vehicleId: row['vehicle_id'] as String,
    category: row['category'] as String,
    date: parseDate(row['date'])!,
    amount: (row['amount'] as num).toDouble(),
    createdAt: parseDate(row['created_at'])!,
    updatedAt: parseDate(row['updated_at'])!,
    currency: Value(row['currency'] as String? ?? 'MAD'),
    providerId: Value(row['provider_id'] as String?),
    mileage: Value((row['mileage'] as num?)?.toDouble()),
    paymentMethod: Value(row['payment_method'] as String?),
    comments: Value(row['comments'] as String?),
    linkedMaintenanceId: Value(row['linked_maintenance_id'] as String?),
    linkedFuelId: Value(row['linked_fuel_id'] as String?),
    linkedDocumentVersionId: Value(row['linked_document_version_id'] as String?),
    isDeleted: Value(row['is_deleted'] as bool? ?? false),
    syncStatus: const Value('synced'),
    version: Value(row['version'] as int? ?? 0),
    createdBy: Value(row['created_by'] as String?),
    updatedBy: Value(row['updated_by'] as String?),
  );
}
