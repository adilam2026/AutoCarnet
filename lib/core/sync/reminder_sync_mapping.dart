import 'package:drift/drift.dart' show Value;

import '../database/database.dart';

/// Pure mapping for `public.reminders` - see vehicle_sync_mapping.dart.
Map<String, dynamic> reminderToRemoteRow(Reminder r) {
  return {
    'id': r.id,
    'vehicle_id': r.vehicleId,
    'source_type': r.sourceType,
    'source_id': r.sourceId,
    'title': r.title,
    'due_date': r.dueDate?.toUtc().toIso8601String(),
    'due_mileage': r.dueMileage,
    'priority': r.priority,
    'status': r.status.name,
    'snoozed_until': r.snoozedUntil?.toUtc().toIso8601String(),
    'created_at': r.createdAt.toUtc().toIso8601String(),
    'updated_at': r.updatedAt.toUtc().toIso8601String(),
  };
}

RemindersCompanion reminderFromRemoteRow(Map<String, dynamic> row) {
  DateTime? parseDate(Object? value) =>
      value == null ? null : DateTime.parse(value as String).toLocal();

  return RemindersCompanion.insert(
    id: row['id'] as String,
    vehicleId: Value(row['vehicle_id'] as String?),
    sourceType: row['source_type'] as String,
    sourceId: row['source_id'] as String,
    title: row['title'] as String,
    createdAt: parseDate(row['created_at'])!,
    updatedAt: parseDate(row['updated_at'])!,
    dueDate: Value(parseDate(row['due_date'])),
    dueMileage: Value((row['due_mileage'] as num?)?.toDouble()),
    priority: Value(row['priority'] as String? ?? 'normal'),
    status: Value(_statusFromName(row['status'] as String?)),
    snoozedUntil: Value(parseDate(row['snoozed_until'])),
    syncStatus: const Value('synced'),
    version: Value(row['version'] as int? ?? 0),
    createdBy: Value(row['created_by'] as String?),
    updatedBy: Value(row['updated_by'] as String?),
  );
}

ReminderStatus _statusFromName(String? name) {
  for (final v in ReminderStatus.values) {
    if (v.name == name) return v;
  }
  return ReminderStatus.active;
}
