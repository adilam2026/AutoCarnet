import 'package:drift/drift.dart' show Value;

import '../database/database.dart';

/// Pure mapping between the local Drift [ServiceProvider] row and the JSON
/// shape Supabase's `public.service_providers` table expects/returns - same
/// philosophy as vehicle_sync_mapping.dart (dependency-free, unit-testable
/// without a network). `user_id` (the owner) is deliberately never sent,
/// same reasoning as vehicles: it defaults to auth.uid() on insert and
/// PostgREST leaves it untouched on update. `version`/`created_by`/
/// `updated_by` are stamped by the sync service itself, not here.
Map<String, dynamic> providerToRemoteRow(ServiceProvider p) {
  return {
    'id': p.id,
    'name': p.name,
    'type': p.type,
    'category': p.category?.name,
    'address': p.address,
    'city': p.city,
    'country': p.country,
    'phone': p.phone,
    'email': p.email,
    'website': p.website,
    'comments': p.comments,
    'is_archived': p.isArchived,
    'created_at': p.createdAt.toUtc().toIso8601String(),
    'updated_at': p.updatedAt.toUtc().toIso8601String(),
  };
}

ServiceProvidersCompanion providerFromRemoteRow(Map<String, dynamic> row) {
  DateTime? parseDate(Object? value) =>
      value == null ? null : DateTime.parse(value as String).toLocal();

  return ServiceProvidersCompanion.insert(
    id: row['id'] as String,
    name: row['name'] as String,
    type: Value(row['type'] as String?),
    category: Value(_enumFromName(ServiceProviderCategory.values, row['category'] as String?)),
    address: Value(row['address'] as String?),
    city: Value(row['city'] as String?),
    country: Value(row['country'] as String?),
    phone: Value(row['phone'] as String?),
    email: Value(row['email'] as String?),
    website: Value(row['website'] as String?),
    comments: Value(row['comments'] as String?),
    isArchived: Value(row['is_archived'] as bool? ?? false),
    createdAt: parseDate(row['created_at'])!,
    updatedAt: parseDate(row['updated_at'])!,
    ownerId: Value(row['user_id'] as String?),
    // This row just came from the cloud - it's already in sync by
    // definition, never mark it pending again.
    syncStatus: const Value('synced'),
    version: Value(row['version'] as int? ?? 0),
    createdBy: Value(row['created_by'] as String?),
    updatedBy: Value(row['updated_by'] as String?),
  );
}

T? _enumFromName<T extends Enum>(List<T> values, String? name) {
  if (name == null) return null;
  for (final v in values) {
    if (v.name == name) return v;
  }
  return null;
}
