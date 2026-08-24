import 'package:autocarnet/core/database/database.dart';
import 'package:autocarnet/core/database/providers.dart';
import 'package:autocarnet/core/widgets/list_surface.dart';
import 'package:autocarnet/features/account/data/account_repository.dart';
import 'package:autocarnet/features/audit/data/audit_repository.dart';
import 'package:autocarnet/features/dashboard/presentation/vehicles_list_body.dart';
import 'package:autocarnet/features/maintenance/data/maintenance_repository.dart';
import 'package:autocarnet/features/reminders/data/reminder_repository.dart';
import 'package:autocarnet/features/timeline/data/timeline_repository.dart';
import 'package:autocarnet/features/vehicles/data/vehicle_repository.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Signed-in, in-memory stand-in for [AccountRepository] - same minimal
/// pattern as the other widget-test fakes in this suite (see
/// account_management_ux_test.dart).
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
  Future<void> verifyEmailCode({
    required String email,
    required String code,
  }) async {}
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

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
  });

  tearDown(() => db.close());

  List<Override> commonOverrides() => [
    appDatabaseProvider.overrideWithValue(db),
    accountRepositoryProvider.overrideWithValue(
      _FakeSignedInAccountRepository(),
    ),
    // vehicleRepositoryProvider normally also wires vehicleSyncServiceProvider,
    // which reaches for Supabase.instance.client - never initialized in a
    // widget test. Build it without the (optional) sync arg instead, exactly
    // like vehicle_repository_test.dart's direct-construction fixtures do.
    vehicleRepositoryProvider.overrideWith(
      (ref) => VehicleRepository(
        ref.watch(appDatabaseProvider),
        ref.watch(auditRepositoryProvider),
        ref.watch(reminderRepositoryProvider),
      ),
    ),
  ];

  Future<ProviderContainer> pumpDashboard(WidgetTester tester) async {
    final container = ProviderContainer(overrides: commonOverrides());
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: VehiclesListBody())),
      ),
    );
    // Two pumps: vehiclesListProvider is a drift StreamProvider, so its
    // first emission needs an extra frame beyond the initial pumpWidget.
    await tester.pump();
    await tester.pump();
    return container;
  }

  testWidgets(
    'no vehicles: shows the welcome empty state, never a bare blank screen',
    (tester) async {
      await pumpDashboard(tester);

      expect(find.text('Bienvenue dans AutoCarnet'), findsOneWidget);
      expect(find.text('Ajouter mon premier véhicule'), findsOneWidget);
      expect(find.text('Rejoindre un véhicule'), findsOneWidget);
    },
  );

  testWidgets(
    'one vehicle, no reminders: shows its name/mileage and the positive '
    '"tout est à jour" card (spec: the section turns positive, never an empty list)',
    (tester) async {
      final repo = VehicleRepository(
        db,
        AuditRepository(db),
        ReminderRepository(db),
      );
      await repo.createVehicle(
        brand: 'Audi',
        model: 'Q5',
        currentMileage: 86750,
      );

      await pumpDashboard(tester);
      await tester.pump();

      expect(find.textContaining('Audi Q5'), findsOneWidget);
      expect(find.textContaining('86 750'), findsOneWidget);
      expect(find.text('Tout est à jour'), findsOneWidget);
    },
  );

  testWidgets(
    'one vehicle with an overdue reminder: it appears in "À faire prochainement"',
    (tester) async {
      final reminders = ReminderRepository(db);
      final repo = VehicleRepository(db, AuditRepository(db), reminders);
      final vehicleId = await repo.createVehicle(
        brand: 'Renault',
        model: 'Clio',
        currentMileage: 142300,
      );
      await reminders.upsertForSource(
        vehicleId: vehicleId,
        sourceType: 'maintenance',
        sourceId: 'm1',
        title: 'Vidange',
        dueMileage: 142300 + 100,
      );

      await pumpDashboard(tester);
      await tester.pump();

      expect(find.text('Vidange'), findsOneWidget);
      expect(find.text('Tout est à jour'), findsNothing);
    },
  );

  testWidgets(
    'the vehicle summary card never shows "Prochaine échéance" - only '
    '"Prochaine révision", with no reminder title duplicated in it',
    (tester) async {
      final reminders = ReminderRepository(db);
      final repo = VehicleRepository(db, AuditRepository(db), reminders);
      final vehicleId = await repo.createVehicle(
        brand: 'Audi',
        model: 'Q5',
        currentMileage: 86750,
      );
      await reminders.upsertForSource(
        vehicleId: vehicleId,
        sourceType: 'maintenance',
        sourceId: 'm1',
        title: 'Vidange + filtres à prévoir',
        dueMileage: 95400,
      );
      await reminders.upsertForSource(
        vehicleId: vehicleId,
        sourceType: 'document',
        sourceId: 'd1',
        title: 'Assurance à renouveler',
        dueDate: DateTime.now().add(const Duration(days: 260)),
      );

      await pumpDashboard(tester);
      await tester.pump();

      expect(find.textContaining('Prochaine échéance'), findsNothing);
      expect(find.textContaining('PROCHAINE ÉCHÉANCE'), findsNothing);
      expect(find.textContaining('Prochaine révision'), findsOneWidget);
      // The reminder's own title never leaks into this summary slot.
      expect(find.textContaining('Vidange + filtres'), findsNothing);
      expect(find.textContaining('95 400'), findsOneWidget);
    },
  );

  testWidgets(
    'the dashboard renders without a horizontal overflow on a narrow (320px) screen',
    (tester) async {
      final repo = VehicleRepository(
        db,
        AuditRepository(db),
        ReminderRepository(db),
      );
      await repo.createVehicle(
        brand: 'Audi',
        model: 'Q5',
        currentMileage: 86750,
      );

      tester.view.physicalSize = const Size(320, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await pumpDashboard(tester);
      await tester.pump();

      expect(tester.takeException(), isNull);
    },
  );

  // PageView keeps at least the immediately adjacent page alive (off-screen)
  // for a smooth drag, so a bare find.text()/textContaining() can legitimately
  // match the SAME text in a neighbouring, not-currently-visible vehicle's
  // own card once every section lives inside it (the "grande carte" pass).
  // Scoping through this key (see _GrandVehicleCard in
  // vehicles_list_body.dart) targets one specific vehicle's card
  // regardless of how many pages PageView currently keeps built.
  Finder cardFor(String vehicleId) => find.byWidgetPredicate(
    (w) =>
        w is Container &&
        w.key == ValueKey('grandVehicleCardContour-$vehicleId'),
  );

  group('multi-vehicle: every home section is scoped to the active vehicle only', () {
    testWidgets(
      'TEST A: swiping from one vehicle to another recomputes "À faire prochainement" '
      'for the newly active vehicle only',
      (tester) async {
        final reminders = ReminderRepository(db);
        final repo = VehicleRepository(db, AuditRepository(db), reminders);
        final astraId = await repo.createVehicle(
          brand: 'Opel',
          model: 'Astra',
          currentMileage: 270000,
        );
        final q5Id = await repo.createVehicle(
          brand: 'Audi',
          model: 'Q5',
          currentMileage: 86750,
        );
        await reminders.upsertForSource(
          vehicleId: astraId,
          sourceType: 'maintenance',
          sourceId: 'm-astra',
          title: 'Vidange Astra',
          dueMileage: 270000 + 100,
        );
        await reminders.upsertForSource(
          vehicleId: q5Id,
          sourceType: 'maintenance',
          sourceId: 'm-q5',
          title: 'Révision Q5',
          dueMileage: 86750 + 100,
        );

        await pumpDashboard(tester);
        await tester.pump();

        // Opel Astra was created first, so it's the active vehicle by default.
        expect(find.textContaining('Opel Astra'), findsWidgets);
        expect(
          find.descendant(
            of: cardFor(astraId),
            matching: find.text('Vidange Astra'),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: cardFor(astraId),
            matching: find.text('Révision Q5'),
          ),
          findsNothing,
        );

        await tester.drag(find.byType(PageView), const Offset(-400, 0));
        await tester.pumpAndSettle();

        expect(find.textContaining('Audi Q5'), findsWidgets);
        expect(
          find.descendant(
            of: cardFor(q5Id),
            matching: find.text('Révision Q5'),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: cardFor(q5Id),
            matching: find.text('Vidange Astra'),
          ),
          findsNothing,
        );
      },
    );

    testWidgets(
      'TEST B: switching vehicles back and forth repeatedly never leaves a stale '
      'reminder from the previous vehicle on screen',
      (tester) async {
        final reminders = ReminderRepository(db);
        final repo = VehicleRepository(db, AuditRepository(db), reminders);
        final astraId = await repo.createVehicle(
          brand: 'Opel',
          model: 'Astra',
          currentMileage: 270000,
        );
        final q5Id = await repo.createVehicle(
          brand: 'Audi',
          model: 'Q5',
          currentMileage: 86750,
        );
        await reminders.upsertForSource(
          vehicleId: astraId,
          sourceType: 'maintenance',
          sourceId: 'm-astra',
          title: 'Vidange Astra',
          dueMileage: 270000 + 100,
        );
        await reminders.upsertForSource(
          vehicleId: q5Id,
          sourceType: 'maintenance',
          sourceId: 'm-q5',
          title: 'Révision Q5',
          dueMileage: 86750 + 100,
        );

        await pumpDashboard(tester);
        await tester.pump();

        for (var i = 0; i < 3; i++) {
          await tester.drag(find.byType(PageView), const Offset(-400, 0));
          await tester.pumpAndSettle();
          await tester.drag(find.byType(PageView), const Offset(400, 0));
          await tester.pumpAndSettle();
        }

        // Back on the Astra (first vehicle): only its own reminder shows on
        // its own card.
        expect(
          find.descendant(
            of: cardFor(astraId),
            matching: find.text('Vidange Astra'),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: cardFor(astraId),
            matching: find.text('Révision Q5'),
          ),
          findsNothing,
        );
      },
    );

    testWidgets(
      'TEST C: a vehicle with zero alerts shows "Tout est à jour" even while another '
      'vehicle in the garage has several',
      (tester) async {
        final reminders = ReminderRepository(db);
        final repo = VehicleRepository(db, AuditRepository(db), reminders);
        final dusterId = await repo.createVehicle(
          brand: 'Dacia',
          model: 'Duster',
          currentMileage: 50000,
        );
        final busyId = await repo.createVehicle(
          brand: 'Audi',
          model: 'Q5',
          currentMileage: 86750,
        );
        for (var i = 0; i < 5; i++) {
          await reminders.upsertForSource(
            vehicleId: busyId,
            sourceType: 'maintenance',
            sourceId: 'm$i',
            title: 'Opération $i',
            dueMileage: 86750 + 50,
          );
        }

        await pumpDashboard(tester);
        // A second vehicle's own reminders stream (vehicleActiveRemindersProvider
        // family, distinct from the base vehicles list stream) needs its own
        // settle cycle - one extra pump here was occasionally borderline on a
        // slower CI runner, showing the loading spinner instead of the card.
        await tester.pump();
        await tester.pump();

        // Dacia Duster (no reminders) is active by default.
        expect(
          find.descendant(
            of: cardFor(dusterId),
            matching: find.text('Tout est à jour'),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: cardFor(dusterId),
            matching: find.textContaining('Opération 0'),
          ),
          findsNothing,
        );
      },
    );
  });

  group('"Dernières opérations" on the home dashboard', () {
    testWidgets(
      'shows only the 2 most recent operations for the active vehicle (V2.1 pass - was 3), '
      'with a "Voir tout" button for the rest',
      (tester) async {
        final reminders = ReminderRepository(db);
        final timeline = TimelineRepository(db);
        final repo = VehicleRepository(db, AuditRepository(db), reminders);
        final maintenance = MaintenanceRepository(
          db,
          timeline,
          reminders,
          repo,
        );
        final vehicleId = await repo.createVehicle(
          brand: 'Audi',
          model: 'Q5',
          currentMileage: 90000,
        );

        await maintenance.createEntry(
          vehicleId: vehicleId,
          category: 'Vidange + filtres',
          date: DateTime(2026, 8, 9),
          mileage: 88700,
          createLinkedExpense: false,
        );
        await maintenance.createEntry(
          vehicleId: vehicleId,
          category: 'Révision',
          date: DateTime(2025, 10, 16),
          mileage: 78900,
          createLinkedExpense: false,
        );
        await maintenance.createEntry(
          vehicleId: vehicleId,
          category: 'Pneus remplacés',
          date: DateTime(2025, 5, 1),
          mileage: 70000,
          createLinkedExpense: false,
        );
        await maintenance.createEntry(
          vehicleId: vehicleId,
          category: 'Plaquettes de frein',
          date: DateTime(2024, 1, 1),
          mileage: 50000,
          createLinkedExpense: false,
        );

        await pumpDashboard(tester);
        await tester.pump();

        // Scoped to the "Dernières opérations" list surface specifically,
        // in case the same category text ever appears elsewhere on the
        // dashboard.
        final opsList = find.byType(ListSurface);
        expect(
          find.descendant(
            of: opsList,
            matching: find.text('Vidange + filtres'),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(of: opsList, matching: find.text('Révision')),
          findsOneWidget,
        );
        expect(
          find.text('Pneus remplacés'),
          findsNothing,
          reason:
              'only the 2 most recent operations should show on the home dashboard',
        );
        expect(
          find.text('Plaquettes de frein'),
          findsNothing,
          reason:
              'only the 2 most recent operations should show on the home dashboard',
        );
        expect(find.text('Voir tout'), findsOneWidget);
      },
    );

    testWidgets(
      'with no operations yet, shows a friendly empty message and no "Voir tout"',
      (tester) async {
        final repo = VehicleRepository(
          db,
          AuditRepository(db),
          ReminderRepository(db),
        );
        await repo.createVehicle(
          brand: 'Audi',
          model: 'Q5',
          currentMileage: 90000,
        );

        await pumpDashboard(tester);
        await tester.pump();

        expect(find.text('Voir tout'), findsNothing);
        expect(
          find.textContaining('Aucune opération enregistrée'),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'switching to another vehicle shows that vehicle\'s own recent operations, not the '
      'previous one\'s',
      (tester) async {
        final reminders = ReminderRepository(db);
        final timeline = TimelineRepository(db);
        final repo = VehicleRepository(db, AuditRepository(db), reminders);
        final maintenance = MaintenanceRepository(
          db,
          timeline,
          reminders,
          repo,
        );
        final astraId = await repo.createVehicle(
          brand: 'Opel',
          model: 'Astra',
          currentMileage: 270000,
        );
        final q5Id = await repo.createVehicle(
          brand: 'Audi',
          model: 'Q5',
          currentMileage: 86750,
        );
        await maintenance.createEntry(
          vehicleId: astraId,
          category: 'Vidange Astra',
          date: DateTime(2026, 1, 1),
          mileage: 269000,
          createLinkedExpense: false,
        );
        await maintenance.createEntry(
          vehicleId: q5Id,
          category: 'Révision Q5',
          date: DateTime(2026, 1, 1),
          mileage: 85000,
          createLinkedExpense: false,
        );

        await pumpDashboard(tester);
        await tester.pump();

        // Scoped to each vehicle's own card - PageView keeps the adjacent
        // page alive off-screen, so a bare find.text() could otherwise match
        // the other vehicle's own (not currently visible) operation too.
        expect(
          find.descendant(
            of: cardFor(astraId),
            matching: find.text('Vidange Astra'),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: cardFor(astraId),
            matching: find.text('Révision Q5'),
          ),
          findsNothing,
        );

        await tester.drag(find.byType(PageView), const Offset(-400, 0));
        await tester.pumpAndSettle();

        expect(
          find.descendant(
            of: cardFor(q5Id),
            matching: find.text('Révision Q5'),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: cardFor(q5Id),
            matching: find.text('Vidange Astra'),
          ),
          findsNothing,
        );
      },
    );
  });
}
