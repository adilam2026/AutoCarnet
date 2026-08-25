import 'package:autocarnet/core/database/database.dart';
import 'package:autocarnet/core/database/providers.dart';
import 'package:autocarnet/features/audit/data/audit_repository.dart';
import 'package:autocarnet/features/reminders/data/reminder_repository.dart';
import 'package:autocarnet/features/vehicles/data/vehicle_repository.dart';
import 'package:autocarnet/features/vehicles/presentation/widgets/add_operation_sheet.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// TEST 5 (mission 2026): "une voiture essence ne reçoit pas d'alerte
/// AdBlue" - since the only way to ever create an AdBlue entry (and
/// therefore the reminder that follows from it) is through this sheet's
/// "Plein AdBlue" tile, the real guarantee to test is that the tile itself
/// is simply never reachable for a non-Diesel vehicle.
void main() {
  late AppDatabase db;
  late VehicleRepository vehicles;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    vehicles = VehicleRepository(db, AuditRepository(db), ReminderRepository(db));
  });

  tearDown(() => db.close());

  Future<void> pumpSheetFor(WidgetTester tester, Vehicle vehicle) async {
    final container = ProviderContainer(
      overrides: [appDatabaseProvider.overrideWithValue(db)],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Consumer(
            builder: (context, ref, _) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () => showAddOperationSheet(context, ref, vehicle: vehicle),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('a Diesel vehicle IS offered the "Plein AdBlue" quick action', (tester) async {
    final id = await vehicles.createVehicle(
      brand: 'Peugeot',
      model: '3008',
      currentMileage: 80000,
      fuelType: 'Diesel',
    );
    final vehicle = await vehicles.getOne(id);

    await pumpSheetFor(tester, vehicle);

    expect(find.text('Plein AdBlue'), findsOneWidget);
  });

  testWidgets(
    'TEST 5: an Essence vehicle is NEVER offered "Plein AdBlue" - there is '
    'no path left to ever create the alert for it',
    (tester) async {
      final id = await vehicles.createVehicle(
        brand: 'Renault',
        model: 'Clio',
        currentMileage: 40000,
        fuelType: 'Essence',
      );
      final vehicle = await vehicles.getOne(id);

      await pumpSheetFor(tester, vehicle);

      expect(find.text('Plein AdBlue'), findsNothing);
    },
  );

  testWidgets('a vehicle with no declared fuel type stays neutral - no '
      'AdBlue tile is guessed into existence', (tester) async {
    final id = await vehicles.createVehicle(
      brand: 'Dacia',
      model: 'Duster',
      currentMileage: 10000,
    );
    final vehicle = await vehicles.getOne(id);

    await pumpSheetFor(tester, vehicle);

    expect(find.text('Plein AdBlue'), findsNothing);
  });
}
