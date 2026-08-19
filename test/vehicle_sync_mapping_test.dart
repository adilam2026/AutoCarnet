import 'package:autocarnet/core/database/database.dart';
import 'package:autocarnet/core/sync/vehicle_sync_mapping.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('vehicle_sync_mapping (pure)', () {
    late AppDatabase db;

    setUp(() => db = AppDatabase(NativeDatabase.memory()));
    tearDown(() => db.close());

    test('a fully-filled vehicle round-trips through remote row shape without loss', () async {
      final now = DateTime.utc(2026, 6, 1, 10, 30);
      const id = 'veh-1';
      await db.into(db.vehicles).insert(
            VehiclesCompanion.insert(
              id: id,
              brand: 'Renault',
              model: 'Clio',
              currentMileage: 42000,
              createdAt: now,
              updatedAt: now,
              trim: const Value('RS Line'),
              year: const Value(2019),
              firstRegistrationDate: Value(DateTime.utc(2019, 3, 15)),
              vin: const Value('VF1AB000012345678'),
              plate: const Value('AB-123-CD'),
              motorization: const Value('1.3 TCe'),
              fiscalPower: const Value('6 CV'),
              fuelType: const Value('Essence'),
              transmission: const Value('Manuelle'),
              color: const Value('Bleu'),
              acquisitionDate: Value(DateTime.utc(2020, 1, 10)),
              purchasePrice: const Value(15000),
              condition: const Value(VehicleCondition.good),
              comments: const Value('RAS'),
              status: const Value(VehicleStatus.active),
            ),
          );
      final local = await (db.select(db.vehicles)..where((v) => v.id.equals(id))).getSingle();

      final row = vehicleToRemoteRow(local);
      expect(row['id'], id);
      expect(row['brand'], 'Renault');
      expect(row['vin'], 'VF1AB000012345678');
      expect(row['condition'], 'good');
      expect(row['status'], 'active');
      expect(row['is_deleted'], false);
      // photo_path is deliberately never synced (local filesystem path).
      expect(row.containsKey('photo_path'), isFalse);

      final companion = vehicleFromRemoteRow(row);
      expect(companion.id.value, local.id);
      expect(companion.brand.value, local.brand);
      expect(companion.model.value, local.model);
      expect(companion.currentMileage.value, local.currentMileage);
      expect(companion.trim.value, local.trim);
      expect(companion.year.value, local.year);
      expect(companion.vin.value, local.vin);
      expect(companion.plate.value, local.plate);
      expect(companion.condition.value, local.condition);
      expect(companion.status.value, local.status);
      expect(companion.isDeleted.value, local.isDeleted);
      // A row that just came from the cloud is by definition already in
      // sync - never re-marked pending, or every pull would trigger a
      // needless push right back.
      expect(companion.syncStatus.value, 'synced');
    });

    test('a minimal vehicle with only required fields maps nulls cleanly both ways', () async {
      final now = DateTime.utc(2026, 1, 1);
      const id = 'veh-2';
      await db.into(db.vehicles).insert(
            VehiclesCompanion.insert(
              id: id,
              brand: 'Peugeot',
              model: '208',
              currentMileage: 0,
              createdAt: now,
              updatedAt: now,
            ),
          );
      final local = await (db.select(db.vehicles)..where((v) => v.id.equals(id))).getSingle();

      final row = vehicleToRemoteRow(local);
      expect(row['vin'], isNull);
      expect(row['condition'], isNull);
      expect(row['first_registration_date'], isNull);

      final companion = vehicleFromRemoteRow(row);
      expect(companion.vin.value, isNull);
      expect(companion.condition.value, isNull);
      expect(companion.firstRegistrationDate.value, isNull);
      // status has no server-side default equivalent in the companion, so
      // the mapping must fall back to active rather than crash on null.
      expect(companion.status.value, VehicleStatus.active);
    });

    test('an unknown condition/status name from the cloud degrades safely instead of throwing', () {
      final row = {
        'id': 'veh-3',
        'brand': 'Fiat',
        'model': 'Panda',
        'current_mileage': 1000,
        'created_at': DateTime.utc(2026, 1, 1).toIso8601String(),
        'updated_at': DateTime.utc(2026, 1, 1).toIso8601String(),
        'condition': 'not_a_real_condition',
        'status': null,
        'is_deleted': null,
      };
      final companion = vehicleFromRemoteRow(row);
      expect(companion.condition.value, isNull);
      expect(companion.status.value, VehicleStatus.active);
      expect(companion.isDeleted.value, false);
    });
  });
}
