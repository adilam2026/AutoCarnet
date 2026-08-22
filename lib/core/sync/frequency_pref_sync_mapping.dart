import 'package:drift/drift.dart' show Value;

import '../database/database.dart';

/// Pure mapping for `public.operation_frequency_preferences` - see
/// vehicle_sync_mapping.dart.
Map<String, dynamic> frequencyPrefToRemoteRow(OperationFrequencyPreference p) {
  return {
    'id': p.id,
    'vehicle_id': p.vehicleId,
    'category': p.category,
    'frequency_km': p.frequencyKm,
    'frequency_months': p.frequencyMonths,
    'updated_at': p.updatedAt.toUtc().toIso8601String(),
  };
}

OperationFrequencyPreferencesCompanion frequencyPrefFromRemoteRow(Map<String, dynamic> row) {
  DateTime? parseDate(Object? value) =>
      value == null ? null : DateTime.parse(value as String).toLocal();

  return OperationFrequencyPreferencesCompanion.insert(
    id: row['id'] as String,
    vehicleId: row['vehicle_id'] as String,
    category: row['category'] as String,
    updatedAt: parseDate(row['updated_at'])!,
    frequencyKm: Value((row['frequency_km'] as num?)?.toDouble()),
    frequencyMonths: Value(row['frequency_months'] as int?),
    syncStatus: const Value('synced'),
    version: Value(row['version'] as int? ?? 0),
    createdBy: Value(row['created_by'] as String?),
    updatedBy: Value(row['updated_by'] as String?),
  );
}
