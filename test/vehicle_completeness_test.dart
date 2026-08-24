import 'package:autocarnet/core/database/database.dart';
import 'package:autocarnet/features/audit/data/audit_repository.dart';
import 'package:autocarnet/features/reminders/data/reminder_repository.dart';
import 'package:autocarnet/features/vehicles/data/vehicle_repository.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('VehicleRepository.completeness', () {
    late AppDatabase db;
    late VehicleRepository repo;

    setUp(() {
      db = AppDatabase(NativeDatabase.memory());
      repo = VehicleRepository(db, AuditRepository(db), ReminderRepository(db));
    });
    tearDown(() => db.close());

    test('an empty comment never keeps an otherwise fully-filled sheet from reaching 100%',
        () async {
      final id = await repo.createVehicle(brand: 'Audi', model: 'Q5', currentMileage: 40000);
      var vehicle = await repo.getOne(id);
      await repo.updateVehicle(vehicle.copyWith(
        trim: const Value('S line'),
        year: const Value(2021),
        plate: const Value('12345-A-6'),
        motorization: const Value('2.0 TDI'),
        fuelType: const Value('Diesel'),
        transmission: const Value('Automatique'),
        color: const Value('Noir'),
        firstRegistrationDate: Value(DateTime(2021, 3, 1)),
        condition: const Value(VehicleCondition.veryGood),
        finishLevel: const Value(VehicleFinishLevel.highEnd),
        comments: const Value(null),
      ));
      vehicle = await repo.getOne(id);
      expect(repo.completeness(vehicle), 1.0);
    });

    test('a filled-in comment does not push completeness above what the real fields already give',
        () async {
      final id = await repo.createVehicle(brand: 'Audi', model: 'Q5', currentMileage: 40000);
      var vehicle = await repo.getOne(id);
      await repo.updateVehicle(vehicle.copyWith(
        trim: const Value('S line'),
        year: const Value(2021),
        plate: const Value('12345-A-6'),
        motorization: const Value('2.0 TDI'),
        fuelType: const Value('Diesel'),
        transmission: const Value('Automatique'),
        color: const Value('Noir'),
        firstRegistrationDate: Value(DateTime(2021, 3, 1)),
        condition: const Value(VehicleCondition.veryGood),
        finishLevel: const Value(VehicleFinishLevel.highEnd),
        comments: const Value('RAS'),
      ));
      vehicle = await repo.getOne(id);
      expect(repo.completeness(vehicle), 1.0);
    });

    test('a brand new vehicle with only the 3 required fields is not yet 100% complete',
        () async {
      final id = await repo.createVehicle(brand: 'Audi', model: 'Q5', currentMileage: 40000);
      final vehicle = await repo.getOne(id);
      expect(repo.completeness(vehicle), lessThan(1.0));
    });
  });
}
