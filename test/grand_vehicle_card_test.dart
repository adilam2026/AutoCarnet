import 'package:autocarnet/core/database/database.dart';
import 'package:autocarnet/core/database/providers.dart';
import 'package:autocarnet/features/account/data/account_repository.dart';
import 'package:autocarnet/features/audit/data/audit_repository.dart';
import 'package:autocarnet/features/dashboard/presentation/vehicles_list_body.dart';
import 'package:autocarnet/features/maintenance/data/maintenance_repository.dart';
import 'package:autocarnet/features/reminders/data/reminder_repository.dart';
import 'package:autocarnet/features/timeline/data/timeline_repository.dart';
import 'package:autocarnet/features/vehicles/data/vehicle_repository.dart';
import 'package:autocarnet/features/vehicles/domain/vehicle_card_color.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:simple_icons/simple_icons.dart';
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

/// Regression coverage for the "grande carte véhicule" pass (2026): the
/// identity band, santé/révision, à faire prochainement, dernières
/// opérations, actions rapides and the closing CTA are all merged into a
/// single swipeable card, with the old thin "Voir la fiche du véhicule"
/// row replaced by a full-bleed CTA at the very bottom - this suite checks
/// the parts home_dashboard_test.dart doesn't: that CTA taps still reach
/// the fiche, that inner buttons still fire their own action (never
/// swallowed by the new swipe gesture), and that both the single- and
/// multi-vehicle paths render one continuous card.
void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
  });

  tearDown(() => db.close());

  List<Override> commonOverrides(VehicleRepository vehicles) => [
    appDatabaseProvider.overrideWithValue(db),
    accountRepositoryProvider.overrideWithValue(
      _FakeSignedInAccountRepository(),
    ),
    vehicleRepositoryProvider.overrideWithValue(vehicles),
  ];

  Future<void> pumpWithRouter(
    WidgetTester tester,
    VehicleRepository vehicles,
  ) async {
    final router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => const Scaffold(body: VehiclesListBody()),
        ),
        GoRoute(
          path: '/vehicles/:id',
          builder: (context, state) =>
              Scaffold(body: Text('FICHE-${state.pathParameters['id']}')),
        ),
      ],
    );
    final container = ProviderContainer(overrides: commonOverrides(vehicles));
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  testWidgets(
    'single vehicle: tapping the bottom CTA opens the fiche véhicule',
    (tester) async {
      final vehicles = VehicleRepository(
        db,
        AuditRepository(db),
        ReminderRepository(db),
      );
      final vehicleId = await vehicles.createVehicle(
        brand: 'Audi',
        model: 'Q5',
        currentMileage: 86750,
      );

      await pumpWithRouter(tester, vehicles);

      expect(find.text('Voir la fiche complète du véhicule'), findsOneWidget);
      await tester.tap(find.text('Voir la fiche complète du véhicule'));
      await tester.pumpAndSettle();

      expect(find.text('FICHE-$vehicleId'), findsOneWidget);
    },
  );

  // PageView keeps at least the adjacent page alive off-screen, and the CTA/
  // quick-action labels are the SAME literal text on every vehicle's card -
  // find.text() alone can match an off-screen page's own copy, so every tap
  // here is scoped to one specific vehicle's card (see cardFor in
  // home_dashboard_test.dart for the same pattern).
  Finder cardFor(String vehicleId) => find.byWidgetPredicate(
    (w) =>
        w is Container &&
        w.key == ValueKey('grandVehicleCardContour-$vehicleId'),
  );

  testWidgets(
    'multi-vehicle: tapping the active page\'s CTA opens THAT vehicle\'s '
    'fiche, never the other one\'s',
    (tester) async {
      final vehicles = VehicleRepository(
        db,
        AuditRepository(db),
        ReminderRepository(db),
      );
      await vehicles.createVehicle(
        brand: 'Opel',
        model: 'Astra',
        currentMileage: 270000,
      );
      final q5Id = await vehicles.createVehicle(
        brand: 'Audi',
        model: 'Q5',
        currentMileage: 86750,
      );

      await pumpWithRouter(tester, vehicles);

      await tester.drag(find.byType(PageView), const Offset(-400, 0));
      await tester.pumpAndSettle();

      await tester.tap(
        find.descendant(
          of: cardFor(q5Id),
          matching: find.text('Voir la fiche complète du véhicule'),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('FICHE-$q5Id'), findsOneWidget);
    },
  );

  testWidgets(
    'multi-vehicle: tapping a quick-action tile fires its own action, '
    'never mistaken for a swipe',
    (tester) async {
      final vehicles = VehicleRepository(
        db,
        AuditRepository(db),
        ReminderRepository(db),
      );
      final astraId = await vehicles.createVehicle(
        brand: 'Opel',
        model: 'Astra',
        currentMileage: 270000,
      );
      await vehicles.createVehicle(
        brand: 'Audi',
        model: 'Q5',
        currentMileage: 86750,
      );

      await pumpWithRouter(tester, vehicles);

      // Astra (first vehicle) is active - tapping "Mettre à jour le
      // kilométrage" on ITS OWN card must open its update sheet, not
      // silently do nothing or change the active vehicle. The sheet's own
      // title is identical text to the tile that opened it (both read
      // "Mettre à jour le kilométrage" - V2 pass: full label, no more
      // truncated "Kilomét..."), so the sheet having genuinely opened is
      // asserted via its own input field instead of a now-ambiguous text
      // finder.
      await tester.tap(
        find.descendant(
          of: cardFor(astraId),
          matching: find.text('Mettre à jour le kilométrage'),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.widgetWithText(TextField, 'Nouveau kilométrage'), findsOneWidget);
    },
  );

  testWidgets('multi-vehicle: tapping "Voir tout" opens the timeline for the '
      'active vehicle only', (tester) async {
    final reminders = ReminderRepository(db);
    final timeline = TimelineRepository(db);
    final vehicles = VehicleRepository(db, AuditRepository(db), reminders);
    final maintenance = MaintenanceRepository(
      db,
      timeline,
      reminders,
      vehicles,
    );
    final astraId = await vehicles.createVehicle(
      brand: 'Opel',
      model: 'Astra',
      currentMileage: 270000,
    );
    await vehicles.createVehicle(
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

    final router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => const Scaffold(body: VehiclesListBody()),
        ),
        GoRoute(
          path: '/vehicles/:id/timeline',
          builder: (context, state) =>
              Scaffold(body: Text('TIMELINE-${state.pathParameters['id']}')),
        ),
      ],
    );
    final container = ProviderContainer(overrides: commonOverrides(vehicles));
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pump();
    await tester.pump();

    await tester.tap(find.text('Voir tout'));
    await tester.pumpAndSettle();

    expect(find.text('TIMELINE-$astraId'), findsOneWidget);
  });

  // Coverage for the carousel-affordance pass (2026): "Véhicule X sur Y",
  // left/right chevrons, the 2+1 quick-actions grid, the CTA band's fixed
  // neutral colour, and the brand-logo size boost.
  Color ctaBandColorFor(WidgetTester tester, Finder card) {
    final ctaText = find.descendant(
      of: card,
      matching: find.text('Voir la fiche complète du véhicule'),
    );
    final material = find.ancestor(of: ctaText, matching: find.byType(Material)).first;
    return tester.widget<Material>(material).color!;
  }

  testWidgets('single vehicle: no "Véhicule X sur Y" indicator - it would be noise for a '
      'one-vehicle garage', (tester) async {
    final vehicles = VehicleRepository(db, AuditRepository(db), ReminderRepository(db));
    await vehicles.createVehicle(brand: 'Audi', model: 'Q5', currentMileage: 86750);

    await pumpWithRouter(tester, vehicles);

    expect(find.textContaining('Véhicule'), findsNothing);
  });

  testWidgets(
      'multi-vehicle: "Véhicule 1 sur 3" / "2 sur 3" / "3 sur 3" tracks the active page as the '
      'carousel is swiped', (tester) async {
    final vehicles = VehicleRepository(db, AuditRepository(db), ReminderRepository(db));
    await vehicles.createVehicle(brand: 'Audi', model: 'Q5', currentMileage: 86750);
    await vehicles.createVehicle(brand: 'Volkswagen', model: 'Tiguan', currentMileage: 110000);
    await vehicles.createVehicle(brand: 'Opel', model: 'Astra', currentMileage: 270000);

    await pumpWithRouter(tester, vehicles);
    expect(find.text('Véhicule 1 sur 3'), findsOneWidget);

    await tester.drag(find.byType(PageView), const Offset(-400, 0));
    await tester.pumpAndSettle();
    expect(find.text('Véhicule 2 sur 3'), findsOneWidget);

    await tester.drag(find.byType(PageView), const Offset(-400, 0));
    await tester.pumpAndSettle();
    expect(find.text('Véhicule 3 sur 3'), findsOneWidget);
  });

  testWidgets('multi-vehicle: tapping the right chevron advances to the next vehicle, the left '
      'chevron returns to the previous one', (tester) async {
    final vehicles = VehicleRepository(db, AuditRepository(db), ReminderRepository(db));
    await vehicles.createVehicle(brand: 'Audi', model: 'Q5', currentMileage: 86750);
    await vehicles.createVehicle(brand: 'Volkswagen', model: 'Tiguan', currentMileage: 110000);

    await pumpWithRouter(tester, vehicles);
    expect(find.text('Véhicule 1 sur 2'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.chevron_right_rounded));
    await tester.pumpAndSettle();
    expect(find.text('Véhicule 2 sur 2'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.chevron_left_rounded));
    await tester.pumpAndSettle();
    expect(find.text('Véhicule 1 sur 2'), findsOneWidget);
  });

  testWidgets(
      'quick actions render as a 2+1 grid with full, untruncated labels - never the old '
      'standalone "Kilométrage" tile', (tester) async {
    final vehicles = VehicleRepository(db, AuditRepository(db), ReminderRepository(db));
    await vehicles.createVehicle(brand: 'Audi', model: 'Q5', currentMileage: 86750);

    await pumpWithRouter(tester, vehicles);

    expect(find.text('Entretien'), findsOneWidget);
    expect(find.text('Plein'), findsOneWidget);
    expect(find.text('Mettre à jour le kilométrage'), findsOneWidget);
    // The old three-tiles-in-a-row layout used the bare word as its own
    // tile label - that exact standalone string must be gone.
    expect(find.text('Kilométrage'), findsNothing);
  });

  testWidgets(
      'the bottom CTA band is a fixed neutral colour, independent of - and visibly different '
      'from - each vehicle\'s own card colour, never a near-duplicate of the identity header',
      (tester) async {
    final vehicles = VehicleRepository(db, AuditRepository(db), ReminderRepository(db));
    final q5Id = await vehicles.createVehicle(brand: 'Audi', model: 'Q5', currentMileage: 86750);
    final tiguanId =
        await vehicles.createVehicle(brand: 'Volkswagen', model: 'Tiguan', currentMileage: 110000);
    final q5 = await vehicles.getOne(q5Id);
    final tiguan = await vehicles.getOne(tiguanId);

    await pumpWithRouter(tester, vehicles);

    final ctaColorQ5 = ctaBandColorFor(tester, cardFor(q5Id));
    expect(ctaColorQ5, isNot(VehicleCardColor.fromKey(q5.cardColorKey).color));

    await tester.drag(find.byType(PageView), const Offset(-400, 0));
    await tester.pumpAndSettle();
    final ctaColorTiguan = ctaBandColorFor(tester, cardFor(tiguanId));
    expect(ctaColorTiguan, isNot(VehicleCardColor.fromKey(tiguan.cardColorKey).color));

    // Same fixed tone for every vehicle, regardless of that vehicle's own
    // (here, necessarily different - see vehicle_repository_test.dart)
    // identity colour.
    expect(ctaColorQ5, ctaColorTiguan);
  });

  testWidgets(
      'brand logos render clearly larger than the pre-existing 16px size, and a glyph known to '
      'be under-filled (Audi\'s wide rings) is boosted past a plain, well-filled mark '
      '(Volkswagen\'s circular badge)', (tester) async {
    final vehicles = VehicleRepository(db, AuditRepository(db), ReminderRepository(db));
    await vehicles.createVehicle(brand: 'Audi', model: 'Q5', currentMileage: 86750);
    await vehicles.createVehicle(brand: 'Volkswagen', model: 'Tiguan', currentMileage: 110000);

    await pumpWithRouter(tester, vehicles);

    final audiIcon = tester.widget<Icon>(find.byIcon(SimpleIcons.audi));
    expect(audiIcon.size, greaterThan(20));

    await tester.drag(find.byType(PageView), const Offset(-400, 0));
    await tester.pumpAndSettle();
    final vwIcon = tester.widget<Icon>(find.byIcon(SimpleIcons.volkswagen));
    expect(vwIcon.size, greaterThan(20));
    expect(audiIcon.size, greaterThan(vwIcon.size!));
  });
}
