import 'package:autocarnet/core/database/database.dart';
import 'package:autocarnet/core/database/providers.dart';
import 'package:autocarnet/features/account/data/account_repository.dart';
import 'package:autocarnet/features/audit/data/audit_repository.dart';
import 'package:autocarnet/features/reminders/data/reminder_repository.dart';
import 'package:autocarnet/features/vehicles/data/vehicle_repository.dart';
import 'package:autocarnet/features/vehicles/domain/vehicle_card_color.dart';
import 'package:autocarnet/features/vehicles/presentation/screens/vehicle_create_screen.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _FakeSignedInAccountRepository implements AccountRepository {
  @override
  User? get currentUser => User(
    id: 'user-1',
    appMetadata: const {},
    userMetadata: null,
    aud: 'authenticated',
    email: 'a@example.com',
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
  Future<String?> deviceAuthorizedUserId() async => 'user-1';
  @override
  Future<String?> lastDeviceUserId() async => 'user-1';
  @override
  Future<String?> deviceAuthorizedEmail() async => 'a@example.com';
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

/// Regression coverage for the "Nouveau véhicule" quick-create redesign
/// (2026, "palette plus vive" pass): finition is gone from this screen
/// (moved to the fiche complète, never dropped from the data model), a
/// "Couleur de la carte" picker takes its place, pre-filled with the same
/// deterministic least-used-first colour [VehicleRepository.createVehicle]
/// would otherwise pick on its own, and the tapped colour is what actually
/// gets saved.
void main() {
  late AppDatabase db;
  late VehicleRepository vehicles;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    vehicles = VehicleRepository(db, AuditRepository(db), ReminderRepository(db));
  });

  tearDown(() => db.close());

  Future<String?> pumpAndCreate(
    WidgetTester tester, {
    required String brand,
    required String model,
    required String mileage,
    VehicleCardColor? tapColor,
  }) async {
    String? createdId;
    final router = GoRouter(
      initialLocation: '/new',
      routes: [
        GoRoute(path: '/new', builder: (context, state) => const VehicleCreateScreen()),
        GoRoute(
          path: '/vehicles/:id',
          builder: (context, state) {
            createdId = state.pathParameters['id'];
            return Scaffold(body: Text('FICHE-$createdId'));
          },
        ),
      ],
    );
    final container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        accountRepositoryProvider.overrideWithValue(_FakeSignedInAccountRepository()),
        vehicleRepositoryProvider.overrideWithValue(vehicles),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pump();
    await tester.pump();

    await tester.enterText(find.widgetWithText(TextFormField, 'Marque *'), brand);
    await tester.enterText(find.widgetWithText(TextFormField, 'Modèle *'), model);
    await tester.enterText(find.widgetWithText(TextFormField, 'Kilométrage actuel *'), mileage);

    if (tapColor != null) {
      final swatch = find.bySemanticsLabel(tapColor.label, skipOffstage: false);
      await tester.ensureVisible(swatch);
      await tester.pump();
      await tester.tap(swatch);
      await tester.pump();
    }

    // The colour picker's 17 swatches push the save button below the fold
    // on the default test viewport - a real, scrollable ListView, not an
    // offstage bug, so the button must be scrolled into view like a user
    // would before it can be tapped.
    final saveButton = find.widgetWithText(FilledButton, 'Enregistrer', skipOffstage: false);
    await tester.ensureVisible(saveButton);
    await tester.pump();
    await tester.tap(saveButton);
    await tester.pumpAndSettle();
    return createdId;
  }

  testWidgets('finition is no longer asked on the quick-create screen, a colour picker is', (
    tester,
  ) async {
    final router = GoRouter(
      routes: [GoRoute(path: '/', builder: (context, state) => const VehicleCreateScreen())],
    );
    final container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        accountRepositoryProvider.overrideWithValue(_FakeSignedInAccountRepository()),
        vehicleRepositoryProvider.overrideWithValue(vehicles),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.textContaining('Finition'), findsNothing);
    expect(find.text('Couleur de la carte'), findsOneWidget);
    // Every palette entry is offered as a tappable swatch.
    for (final c in VehicleCardColor.values) {
      expect(find.bySemanticsLabel(c.label), findsOneWidget);
    }
  });

  testWidgets(
    'the very first vehicle in an empty garage is proposed - and saved with - the same '
    'deterministic colour createVehicle would have picked on its own (never a random draw)',
    (tester) async {
      final id = await pumpAndCreate(
        tester,
        brand: 'Audi',
        model: 'Q5',
        mileage: '86750',
      );
      expect(id, isNotNull);
      final saved = await vehicles.getOne(id!);
      expect(VehicleCardColor.fromKey(saved.cardColorKey), VehicleCardColor.bluePetrole);
    },
  );

  testWidgets(
    'a second vehicle is proposed a colour different from the first one already in the '
    'garage (spec: "essayer d\'attribuer automatiquement une couleur différente")',
    (tester) async {
      await vehicles.createVehicle(brand: 'Renault', model: 'Clio', currentMileage: 40000);

      final id = await pumpAndCreate(
        tester,
        brand: 'Peugeot',
        model: '308',
        mileage: '15000',
      );
      final saved = await vehicles.getOne(id!);
      expect(VehicleCardColor.fromKey(saved.cardColorKey), isNot(VehicleCardColor.bluePetrole));
    },
  );

  testWidgets('tapping a swatch overrides the proposed colour and that choice is what gets saved', (
    tester,
  ) async {
    final id = await pumpAndCreate(
      tester,
      brand: 'BMW',
      model: 'X3',
      mileage: '52000',
      tapColor: VehicleCardColor.rougeGrenat,
    );
    final saved = await vehicles.getOne(id!);
    expect(VehicleCardColor.fromKey(saved.cardColorKey), VehicleCardColor.rougeGrenat);
  });

  testWidgets('finition stays untouched at null after a quick creation - never silently guessed', (
    tester,
  ) async {
    final id = await pumpAndCreate(tester, brand: 'Audi', model: 'A4', mileage: '10000');
    final saved = await vehicles.getOne(id!);
    expect(saved.finishLevel, isNull);
  });
}
