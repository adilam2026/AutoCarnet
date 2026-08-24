import 'package:autocarnet/core/database/database.dart';
import 'package:autocarnet/core/database/providers.dart';
import 'package:autocarnet/core/theme/app_theme.dart';
import 'package:autocarnet/features/account/data/account_repository.dart';
import 'package:autocarnet/features/audit/data/audit_repository.dart';
import 'package:autocarnet/features/dashboard/presentation/vehicles_list_body.dart';
import 'package:autocarnet/features/reminders/data/reminder_repository.dart';
import 'package:autocarnet/features/vehicles/data/vehicle_repository.dart';
import 'package:autocarnet/features/vehicles/domain/vehicle_card_color.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
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

/// Regression coverage for the card-contour "coupure" reported on recette
/// (mission point 8-10, 12g), now re-targeted at `_GrandVehicleCard`
/// (vehicles_list_body.dart) after the "grande carte" pass, 2026: the
/// identity band, santé/révision and every section below it (à faire
/// prochainement, dernières opérations, actions rapides, CTA) were merged
/// into ONE continuously-bordered card - [VehicleHeroCard] itself no
/// longer owns any border/radius/clip at all, only the identity band and
/// facts line. A Container with both a `border` and a `child` auto-insets
/// that child by the border's own width (Flutter's BoxDecoration.padding),
/// but the inset content still had SQUARE corners of its own - near the
/// card's corners the outer border's rounded arc curves inward by up to
/// AppRadius.lg, far more than the thin uniform inset, so the flat content
/// rectangle's square corner poked past that curve and let the card's own
/// `surfaceContainerLowest` background show through as a small triangular
/// gap right at the corner.
///
/// The fix wraps the inner content in a second, CONCENTRIC ClipRRect sized
/// to the border's own inset (`radius - borderWidth`), so its rounded
/// corners land exactly flush against the inside of the border with no gap
/// and no overlap. That concentricity is an exact geometric invariant, not
/// something that needs probabilistic/visual sampling to confirm - this
/// test asserts it directly against the real widget tree for every step of
/// the palette (bleu pétrole, bordeaux, and every other available colour).
void main() {
  Future<ProviderContainer> pumpOneVehicle(
    WidgetTester tester,
    AppDatabase db,
    VehicleCardColor color,
  ) async {
    final vehicles = VehicleRepository(
      db,
      AuditRepository(db),
      ReminderRepository(db),
    );
    final vehicleId = await vehicles.createVehicle(
      brand: 'Audi',
      model: 'Q5',
      currentMileage: 85450,
    );
    await (db.update(db.vehicles)..where((v) => v.id.equals(vehicleId))).write(
      VehiclesCompanion(cardColorKey: Value(color.storageKey)),
    );

    final container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        accountRepositoryProvider.overrideWithValue(
          _FakeSignedInAccountRepository(),
        ),
        vehicleRepositoryProvider.overrideWithValue(vehicles),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const Scaffold(body: VehiclesListBody()),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    return container;
  }

  for (final color in VehicleCardColor.values) {
    testWidgets(
      'card contour (${color.label}): the inner content clip is exactly '
      'concentric with the outer border - no corner gap possible',
      (tester) async {
        final db = AppDatabase(NativeDatabase.memory());
        addTearDown(db.close);
        await pumpOneVehicle(tester, db, color);

        // Never a rendering exception (the exact class of bug that made the
        // Dépenses screen go blank elsewhere in this pass): the whole card
        // subtree must actually build and paint.
        expect(tester.takeException(), isNull);

        final contourFinder = find.byWidgetPredicate(
          (w) =>
              w is Container &&
              w.key is ValueKey &&
              (w.key! as ValueKey).value.toString().startsWith(
                'grandVehicleCardContour-',
              ),
        );
        final outerContainer = tester.widget<Container>(contourFinder);
        final outerDecoration = outerContainer.decoration! as BoxDecoration;
        final borderWidth = outerDecoration.border!.top.width;
        final outerRadius =
            (outerDecoration.borderRadius! as BorderRadius).topLeft.x;

        final innerClip = tester.widget<ClipRRect>(
          find
              .descendant(of: contourFinder, matching: find.byType(ClipRRect))
              .first,
        );
        final innerRadius = (innerClip.borderRadius as BorderRadius).topLeft.x;

        expect(
          innerRadius,
          closeTo(outerRadius - borderWidth, 0.01),
          reason:
              'the inner clip radius must be exactly outerRadius - '
              'borderWidth to land flush against the inside of the border - '
              'any other value reopens the corner gap',
        );

        // The border itself must be the vehicle's own colour (mission point
        // 8-10: bleu pétrole -> contour entirely bleu pétrole, bordeaux ->
        // contour entirely bordeaux, never a generic app colour).
        expect(
          (outerDecoration.border!.top.color.toARGB32()),
          color.onLightSurface.toARGB32(),
        );
      },
    );
  }

  testWidgets(
    'the identity band and facts line (VehicleHeroCard) carry no border '
    'or corner radius of their own - only the grand card that wraps them '
    'does, so a competing outer frame can never reappear around just the '
    'vehicle header',
    (tester) async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      await pumpOneVehicle(tester, db, VehicleCardColor.bluePetrole);

      final headerFinder = find.byWidgetPredicate(
        (w) =>
            w is Column &&
            w.key is ValueKey &&
            (w.key! as ValueKey).value.toString().startsWith(
              'vehicleHeroCardHeader-',
            ),
      );
      expect(headerFinder, findsOneWidget);

      final borderedDescendants = find
          .descendant(
            of: headerFinder,
            matching: find.byWidgetPredicate(
              (w) =>
                  w is Container &&
                  (w.decoration as BoxDecoration?)?.border != null,
            ),
          )
          .evaluate()
          .length;
      expect(
        borderedDescendants,
        0,
        reason:
            'the identity band/facts header must stay a plain, '
            'unbordered header - any border here would draw a second, '
            'competing outer frame around it',
      );
    },
  );
}
