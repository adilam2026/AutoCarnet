import 'package:autocarnet/core/database/database.dart';
import 'package:autocarnet/core/database/providers.dart';
import 'package:autocarnet/core/theme/app_theme.dart';
import 'package:autocarnet/features/audit/data/audit_repository.dart';
import 'package:autocarnet/features/dashboard/presentation/widgets/vehicle_hero_card.dart';
import 'package:autocarnet/features/reminders/data/reminder_repository.dart';
import 'package:autocarnet/features/vehicles/data/vehicle_repository.dart';
import 'package:autocarnet/features/vehicles/domain/vehicle_card_color.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Regression coverage for the card-contour "coupure" reported on recette
/// (mission point 8-10, 12g): a Container with both a `border` and a
/// `child` auto-insets that child by the border's own width (Flutter's
/// BoxDecoration.padding), but the inset content still had SQUARE corners
/// of its own - near the card's corners the outer border's rounded arc
/// curves inward by up to AppRadius.lg, far more than the thin uniform
/// inset, so the flat content rectangle's square corner poked past that
/// curve and let the card's own `surfaceContainerLowest` background show
/// through as a small triangular gap right at the corner.
///
/// The fix (vehicle_hero_card.dart) wraps the inner content in a second,
/// CONCENTRIC ClipRRect sized to the border's own inset
/// (`radius - borderWidth`), so its rounded corners land exactly flush
/// against the inside of the border with no gap and no overlap. That
/// concentricity is an exact geometric invariant, not something that needs
/// probabilistic/visual sampling to confirm - this test asserts it
/// directly against the real widget tree for every step of the palette
/// (bleu pétrole, bordeaux, and every other available colour), and asserts
/// the whole card renders as ONE Container/border pair (never three
/// independently-bordered pieces).
void main() {
  Future<Vehicle> buildVehicle(AppDatabase db, VehicleCardColor color) async {
    final vehicles = VehicleRepository(db, AuditRepository(db), ReminderRepository(db));
    final vehicleId = await vehicles.createVehicle(
      brand: 'Audi',
      model: 'Q5',
      currentMileage: 85450,
    );
    await (db.update(db.vehicles)..where((v) => v.id.equals(vehicleId))).write(
      VehiclesCompanion(cardColorKey: Value(color.storageKey)),
    );
    return (db.select(db.vehicles)..where((v) => v.id.equals(vehicleId))).getSingle();
  }

  for (final color in VehicleCardColor.values) {
    testWidgets(
        'card contour (${color.label}): the inner content clip is exactly '
        'concentric with the outer border - no corner gap possible',
        (tester) async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final vehicle = await buildVehicle(db, color);

      final container = ProviderContainer(overrides: [
        appDatabaseProvider.overrideWithValue(db),
        vehicleRepositoryProvider.overrideWithValue(
          VehicleRepository(db, AuditRepository(db), ReminderRepository(db)),
        ),
      ]);
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: AppTheme.light(),
            home: Scaffold(
              body: SizedBox(
                width: 340,
                child: VehicleHeroCard(vehicle: vehicle, reminders: const [], onTap: () {}),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      // Never a rendering exception (the exact class of bug that made the
      // Dépenses screen go blank elsewhere in this pass): the whole card
      // subtree must actually build and paint.
      expect(tester.takeException(), isNull);

      final outerContainer = tester.widget<Container>(
        find.byKey(ValueKey('vehicleHeroCardContour-${vehicle.id}')),
      );
      final outerDecoration = outerContainer.decoration! as BoxDecoration;
      final borderWidth = outerDecoration.border!.top.width;
      final outerRadius =
          (outerDecoration.borderRadius! as BorderRadius).topLeft.x;

      final innerClip = tester.widget<ClipRRect>(
        find.descendant(
          of: find.byKey(ValueKey('vehicleHeroCardContour-${vehicle.id}')),
          matching: find.byType(ClipRRect),
        ),
      );
      final innerRadius = (innerClip.borderRadius as BorderRadius).topLeft.x;

      expect(
        innerRadius,
        closeTo(outerRadius - borderWidth, 0.01),
        reason: 'the inner clip radius must be exactly outerRadius - '
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
    });
  }

  testWidgets(
      'the card is ONE Container/border pair, never three independently-'
      'bordered pieces stacked together', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final vehicle = await buildVehicle(db, VehicleCardColor.bluePetrole);

    final container = ProviderContainer(overrides: [
      appDatabaseProvider.overrideWithValue(db),
      vehicleRepositoryProvider.overrideWithValue(
        VehicleRepository(db, AuditRepository(db), ReminderRepository(db)),
      ),
    ]);
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: SizedBox(
              width: 340,
              child: VehicleHeroCard(vehicle: vehicle, reminders: const [], onTap: () {}),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    // isUniform excludes the Divider between zones 2 and 3 - it also
    // renders internally as a Container with a border, but only on one
    // side (a plain separator line, never an outer contour of its own).
    final cardContainers = find
        .descendant(
          of: find.byType(VehicleHeroCard),
          matching: find.byWidgetPredicate(
            (w) =>
                w is Container &&
                ((w.decoration as BoxDecoration?)?.border?.isUniform ?? false),
          ),
        )
        .evaluate()
        .length;
    expect(cardContainers, 1,
        reason: 'exactly one Container carries a border - the 3 internal '
            'zones (identity band / facts / CTA) are plain children with no '
            'border of their own, so there is only ever one outer contour '
            'to go wrong');
  });
}
