import 'package:drift/drift.dart' show Value;

import '../database/database.dart';

/// Pure mapping for `public.mileage_entries` - append-only history (see
/// MileageSyncService's class doc), so there is no version/updated_by to
/// carry, only who recorded it.
Map<String, dynamic> mileageEntryToRemoteRow(MileageEntry m) {
  return {
    'id': m.id,
    'vehicle_id': m.vehicleId,
    'value': m.value,
    'recorded_at': m.recordedAt.toUtc().toIso8601String(),
    'source': m.source,
    'source_id': m.sourceId,
    'note': m.note,
    'created_at': m.createdAt.toUtc().toIso8601String(),
  };
}

MileageEntriesCompanion mileageEntryFromRemoteRow(Map<String, dynamic> row) {
  DateTime? parseDate(Object? value) =>
      value == null ? null : DateTime.parse(value as String).toLocal();

  return MileageEntriesCompanion.insert(
    id: row['id'] as String,
    vehicleId: row['vehicle_id'] as String,
    value: (row['value'] as num).toDouble(),
    recordedAt: parseDate(row['recorded_at'])!,
    source: row['source'] as String,
    createdAt: parseDate(row['created_at'])!,
    sourceId: Value(row['source_id'] as String?),
    note: Value(row['note'] as String?),
    syncStatus: const Value('synced'),
    createdBy: Value(row['created_by'] as String?),
  );
}
