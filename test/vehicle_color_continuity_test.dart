import 'package:autocarnet/core/database/database.dart';
import 'package:autocarnet/core/database/providers.dart';
import 'package:autocarnet/core/theme/app_theme.dart';
import 'package:autocarnet/features/account/data/account_repository.dart';
import 'package:autocarnet/features/audit/data/audit_repository.dart';
import 'package:autocarnet/features/dashboard/presentation/vehicles_list_body.dart';
import 'package:autocarnet/features/reminders/data/reminder_repository.dart';
import 'package:autocarnet/features/vehicles/data/vehicle_repository.dart';
import 'package:autocarnet/features/vehicles/domain/vehicle_card_color.dart';
import 'package:autocarnet/features/vehicles/presentation/screens/vehicle_home_screen.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Same minimal signed-in fake used across the other widget-test files in
/// this suite (see home_dashboard_test.dart / account_management_ux_test.dart).
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

/// Regression + integration coverage for the "cohérence visuelle" pass
/// (2026): the vehicle's own identity colour must be the accueil card's
/// full outer contour, the same colour must reappear as the fiche
/// véhicule header's compact identity chip and the fiche's main summary
/// card contour, and the fiche header's vehicle name must never again
/// render unreadable (the reported "Audi Q5 en blanc sur fond blanc" bug)
/// - this suite pumps the real [AppTheme.light] rather than Flutter's bare
/// default theme, since that bug only reproduced under AutoCarnet's own
/// theme.
void main() {
  late AppDatabase db;
  late VehicleRepository repo;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    repo = VehicleRepository(db, AuditRepository(db), ReminderRepository(db));
  });

  tearDown(() => db.close());

  List<Override> commonOverrides() => [
        appDatabaseProvider.overrideWithValue(db),
        accountRepositoryProvider.overrideWithValue(_FakeSignedInAccountRepository()),
        vehicleRepositoryProvider.overrideWithValue(repo),
      ];

  // Each helper mounts its own screen, and a single test runs both in
  // sequence to compare them - a plain ProviderScope (not a manually-owned
  // UncontrolledProviderScope) so tearing the tree down via
  // pumpWidget(SizedBox()) also disposes its container and gives Drift's
  // debounced query-stream-close Timer a chance to fire before the next
  // pumpWidget call, matching the equivalent teardown in
  // vehicle_home_screen_sync_test.dart.
  Future<void> settle(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(Duration.zero);
  }

  Future<Color> pumpAccueilContour(WidgetTester tester, String vehicleId) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: commonOverrides(),
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const Scaffold(body: VehiclesListBody()),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    final contour = tester.widget<Container>(
      find.byKey(ValueKey('vehicleHeroCardContour-$vehicleId')),
    );
    final color = ((contour.decoration as BoxDecoration).border as Border).top.color;
    await settle(tester);
    return color;
  }

  Future<(Color chipColor, Color chipTextColor, Color summaryCardColor)> pumpFiche(
      WidgetTester tester, String vehicleId) async {
    final router = GoRouter(
      initialLocation: '/vehicles/$vehicleId',
      routes: [
        GoRoute(path: '/', builder: (context, state) => const Scaffold(body: Text('ACCUEIL'))),
        GoRoute(
          path: '/vehicles/:id',
          builder: (context, state) => VehicleHomeScreen(vehicleId: state.pathParameters['id']!),
        ),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: commonOverrides(),
        child: MaterialApp.router(theme: AppTheme.light(), routerConfig: router),
      ),
    );
    await tester.pump();
    await tester.pump();

    final chip = tester.widget<Container>(find.byKey(const Key('vehicleIdentityChip')));
    final chipColor = ((chip.decoration as BoxDecoration).border as Border).top.color;
    final nameText = tester.widget<Text>(
      find.descendant(of: find.byKey(const Key('vehicleIdentityChip')), matching: find.byType(Text)),
    );
    final summary = tester.widget<Container>(find.byKey(const Key('vehicleSummaryCardContour')));
    final summaryColor = ((summary.decoration as BoxDecoration).border as Border).top.color;
    final nameColor = nameText.style!.color!;

    await settle(tester);
    return (chipColor, nameColor, summaryColor);
  }

  testWidgets(
      'a single auto-assigned vehicle: the accueil card contour, the fiche header identity '
      'chip and the fiche main card all use the SAME colour', (tester) async {
    final vehicleId =
        await repo.createVehicle(brand: 'Audi', model: 'Q5', currentMileage: 86750);

    final accueilContour = await pumpAccueilContour(tester, vehicleId);
    final expected = VehicleCardColor.bluePetrole.onLightSurface;
    expect(accueilContour, expected,
        reason: 'first vehicle in an empty garage is auto-assigned bluePetrole');

    final (chipColor, nameColor, summaryColor) = await pumpFiche(tester, vehicleId);
    // The chip's own border is deliberately drawn at reduced alpha (a
    // softer, more compact accent than the accueil card's full-strength
    // contour) - same hue, not the same literal Color value.
    expect(chipColor.withValues(alpha: 1), expected);
    expect(summaryColor, expected);
    expect(nameColor, isNot(Colors.white),
        reason: 'regression: the vehicle name must never render white-on-white again');
    expect(nameColor, AppTheme.light().colorScheme.onSurface);
  });

  testWidgets(
      'after a manual colour change from the fiche, the new colour is reflected on both the '
      'accueil card and the fiche itself', (tester) async {
    final vehicleId =
        await repo.createVehicle(brand: 'Opel', model: 'Astra', currentMileage: 270000);
    await repo.updateVehicleCardColor(vehicleId, VehicleCardColor.terracotta);

    final accueilContour = await pumpAccueilContour(tester, vehicleId);
    final expected = VehicleCardColor.terracotta.onLightSurface;
    expect(accueilContour, expected);

    final (chipColor, nameColor, summaryColor) = await pumpFiche(tester, vehicleId);
    expect(chipColor.withValues(alpha: 1), expected);
    expect(summaryColor, expected);
    expect(nameColor, isNot(Colors.white));
  });
}
