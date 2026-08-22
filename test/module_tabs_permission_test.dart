import 'package:autocarnet/core/database/database.dart';
import 'package:autocarnet/core/database/providers.dart';
import 'package:autocarnet/features/account/data/account_repository.dart';
import 'package:autocarnet/features/audit/data/audit_repository.dart';
import 'package:autocarnet/features/documents/presentation/documents_tab.dart';
import 'package:autocarnet/features/expenses/presentation/expenses_tab.dart';
import 'package:autocarnet/features/fuel/presentation/fuel_tab.dart';
import 'package:autocarnet/features/maintenance/presentation/maintenance_tab.dart';
import 'package:autocarnet/features/reminders/data/reminder_repository.dart';
import 'package:autocarnet/features/vehicles/data/vehicle_repository.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// A viewer collaborator must never see any way to add/edit/delete a
/// module's data on a vehicle shared with them - RG: a viewer's local
/// write would otherwise appear to succeed offline-first and then simply
/// never be able to sync, silently diverging forever (see
/// vehicle_ownership.dart's canEditVehicle doc). This covers the four
/// module tabs gated in this phase 4 batch.
class _FakeSignedInAccountRepository implements AccountRepository {
  @override
  User? get currentUser => User(
        id: 'me',
        appMetadata: const {},
        userMetadata: null,
        aud: 'authenticated',
        email: 'me@example.com',
        createdAt: DateTime.now().toIso8601String(),
      );
  @override
  Session? get currentSession => null;
  @override
  bool get isSignedIn => true;
  @override
  Stream<AuthState> get onAuthStateChange => const Stream.empty();
  @override
  Future<String?> tryRestoreDeviceSession(String email) async => null;
  @override
  Future<void> sendEmailCode(String email) async {}
  @override
  Future<void> verifyEmailCode({required String email, required String code}) async {}
  @override
  Future<String> installationId() async => 'test-device';
  @override
  Future<String?> deviceAuthorizedUserId() async => 'me';
  @override
  Future<String?> lastDeviceUserId() async => 'me';
  @override
  Future<String?> deviceAuthorizedEmail() async => 'me@example.com';
  @override
  Future<void> registerThisDevice() async {}
  @override
  Future<bool> isDeviceStillAuthorized({required String userId}) async => true;
  @override
  Future<List<AuthorizedDevice>> listMyDevices() async => const [];
  @override
  Future<void> revokeDevice(String deviceRowId) async {}
  @override
  Future<void> disconnectFromThisDevice() async {}
  @override
  Future<void> disconnectFromAllDevices() async {}
}

void main() {
  late AppDatabase db;
  late VehicleRepository vehicles;
  late String vehicleId;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    vehicles = VehicleRepository(db, AuditRepository(db), ReminderRepository(db));
    vehicleId = await vehicles.createVehicle(brand: 'Audi', model: 'Q5', currentMileage: 40000);
  });

  tearDown(() => db.close());

  Future<void> makeSharedWith(String role) {
    return (db.update(db.vehicles)..where((v) => v.id.equals(vehicleId))).write(
      VehiclesCompanion(ownerId: const Value('someone-else'), myRole: Value(role)),
    );
  }

  List<Override> overrides() => [
        appDatabaseProvider.overrideWithValue(db),
        accountRepositoryProvider.overrideWithValue(_FakeSignedInAccountRepository()),
        vehicleRepositoryProvider.overrideWith((ref) => vehicles),
      ];

  Future<ProviderContainer> pump(WidgetTester tester, Widget child) async {
    final container = ProviderContainer(overrides: overrides());
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(home: child),
      ),
    );
    await tester.pump();
    await tester.pump();
    return container;
  }

  group('MaintenanceTab', () {
    testWidgets('a viewer sees no "Ajouter" FAB', (tester) async {
      await makeSharedWith('viewer');
      await pump(tester, MaintenanceTab(vehicleId: vehicleId));
      expect(find.text('Ajouter un entretien'), findsNothing);
    });

    testWidgets('an editor sees the "Ajouter" FAB', (tester) async {
      await makeSharedWith('editor');
      await pump(tester, MaintenanceTab(vehicleId: vehicleId));
      expect(find.text('Ajouter un entretien'), findsWidgets);
    });
  });

  group('FuelTab', () {
    testWidgets('a viewer sees no "Ajouter" FAB', (tester) async {
      await makeSharedWith('viewer');
      await pump(tester, FuelTab(vehicleId: vehicleId));
      expect(find.text('Ajouter un plein'), findsNothing);
    });

    testWidgets('an editor sees the "Ajouter" FAB', (tester) async {
      await makeSharedWith('editor');
      await pump(tester, FuelTab(vehicleId: vehicleId));
      expect(find.text('Ajouter un plein'), findsWidgets);
    });
  });

  group('ExpensesTab', () {
    testWidgets('a viewer sees no "Ajouter" FAB', (tester) async {
      await makeSharedWith('viewer');
      await pump(tester, ExpensesTab(vehicleId: vehicleId));
      expect(find.text('Ajouter une dépense'), findsNothing);
    });

    testWidgets('an editor sees the "Ajouter" FAB', (tester) async {
      await makeSharedWith('editor');
      await pump(tester, ExpensesTab(vehicleId: vehicleId));
      expect(find.text('Ajouter une dépense'), findsWidgets);
    });
  });

  group('DocumentsTab', () {
    testWidgets('a viewer sees no "Ajouter" FAB', (tester) async {
      await makeSharedWith('viewer');
      await pump(tester, DocumentsTab(vehicleId: vehicleId));
      expect(find.text('Ajouter un document'), findsNothing);
    });

    testWidgets('an editor sees the "Ajouter" FAB', (tester) async {
      await makeSharedWith('editor');
      await pump(tester, DocumentsTab(vehicleId: vehicleId));
      expect(find.text('Ajouter un document'), findsWidgets);
    });
  });
}
