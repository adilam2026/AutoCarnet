import 'package:autocarnet/core/database/database.dart';
import 'package:autocarnet/features/resale/domain/valuation/valuation_engine.dart';
import 'package:autocarnet/features/resale/domain/valuation/valuation_models.dart';
import 'package:flutter_test/flutter_test.dart';

/// Cahier des charges bloc 22 - the resale valuation scenarios A-G.
/// (G - "modifier le kilométrage recalcule sans créer une fausse opération"
/// - is covered in business_history_test.dart since it's about the
/// timeline, not the engine itself.)
void main() {
  const engine = InternalValuationProvider();
  final threeYearsAgo = DateTime.now().subtract(const Duration(days: 365 * 3));

  ValuationInput baseInput({
    double currentMileage = 60000,
    DateTime? firstRegistrationDate,
    String? trim,
    String? fuelType,
    String? transmission,
    VehicleCondition? condition,
    int maintenanceEntryCount = 0,
  }) {
    return ValuationInput(
      brand: 'Renault',
      model: 'Clio',
      trim: trim,
      firstRegistrationDate: firstRegistrationDate ?? threeYearsAgo,
      currentMileage: currentMileage,
      fuelType: fuelType,
      transmission: transmission,
      condition: condition,
      maintenanceEntryCount: maintenanceEntryCount,
    );
  }

  test('A. same vehicle, same age, higher mileage never scores a better '
      'estimate without reason', () {
    final lowMileage = engine.compute(baseInput(currentMileage: 40000));
    final highMileage = engine.compute(baseInput(currentMileage: 90000));
    expect(highMileage.fairPrice, lessThan(lowMileage.fairPrice));
  });

  test('B. registration in January vs December of the same year yields a '
      'different precise age, and therefore a different estimate', () {
    final now = DateTime.now();
    final registeredJanuary = DateTime(now.year - 3, 1, 15);
    final registeredDecember = DateTime(now.year - 3, 12, 15);
    final januaryResult =
        engine.compute(baseInput(firstRegistrationDate: registeredJanuary));
    final decemberResult =
        engine.compute(baseInput(firstRegistrationDate: registeredDecember));
    expect(januaryResult.fairPrice, isNot(equals(decemberResult.fairPrice)));
    // The vehicle registered earlier in the year is older today, so it's
    // worth strictly less, all else being equal.
    expect(januaryResult.fairPrice, lessThan(decemberResult.fairPrice));
  });

  test('C. complete maintenance history improves confidence; the central '
      'value only moves if a rule actually says so (it doesn\'t here)', () {
    final unknownHistory = engine.compute(baseInput(maintenanceEntryCount: 0));
    final completeHistory = engine.compute(baseInput(maintenanceEntryCount: 6));

    final unknownFactor = unknownHistory.confidenceFactors
        .firstWhere((f) => f.label == 'Historique d\'entretien disponible');
    final completeFactor = completeHistory.confidenceFactors
        .firstWhere((f) => f.label == 'Historique d\'entretien disponible');
    expect(unknownFactor.satisfied, isFalse);
    expect(completeFactor.satisfied, isTrue);
    // No maintenance-based pricing rule exists, so the price must not
    // silently change just because more history is available.
    expect(completeHistory.fairPrice, unknownHistory.fairPrice);
  });

  test('D. missing version/motorisation still produces an estimate, with '
      'lower confidence rather than a blocked screen', () {
    final sparse = engine.compute(baseInput());
    final detailed = engine.compute(baseInput(
      trim: 'Intens',
      fuelType: 'Diesel',
      transmission: 'Automatique',
      condition: VehicleCondition.good,
    ));
    expect(sparse.fairPrice, greaterThan(0));
    expect(sparse.confidenceFactors.where((f) => f.satisfied).length,
        lessThan(detailed.confidenceFactors.where((f) => f.satisfied).length));
  });

  test('E. never claims to be a real market quote anywhere in the '
      'engine\'s own output', () {
    final result = engine.compute(baseInput());
    for (final line in result.breakdown) {
      final label = line.label.toLowerCase();
      expect(label, isNot(contains('argus')));
      expect(label, isNot(contains('cote de marché')));
      expect(label, isNot(contains('cote marché')));
      expect(label, isNot(contains('marché réel')));
    }
  });

  test('F. adding information (e.g. condition) immediately changes the '
      'recomputed estimate', () {
    final before = engine.compute(baseInput());
    final after = engine.compute(baseInput(condition: VehicleCondition.excellent));
    expect(after.fairPrice, isNot(equals(before.fairPrice)));
    expect(after.fairPrice, greaterThan(before.fairPrice));
  });

  test('always starts from AutoCarnet\'s own reference price - there is no '
      'real purchase price input (Acquisition was removed from the vehicle '
      'sheet)', () {
    final result = engine.compute(baseInput());
    expect(result.breakdown.first.label, contains('AutoCarnet'));
  });

  test('the three tiers are always derived from the same central value', () {
    final result = engine.compute(baseInput());
    expect(result.quickSale, lessThan(result.fairPrice));
    expect(result.highPrice, greaterThan(result.fairPrice));
  });

  group('Revente - référentiel fin (segment-aware, cas Audi Q5)', () {
    ValuationInput q5Input({
      required double currentMileage,
      required DateTime firstRegistrationDate,
      VehicleCondition? condition,
    }) {
      return ValuationInput(
        brand: 'Audi',
        model: 'Q5',
        firstRegistrationDate: firstRegistrationDate,
        currentMileage: currentMileage,
        condition: condition,
        maintenanceEntryCount: 4,
      );
    }

    final mecDec2021 = DateTime(2021, 12, 15);
    final mecDec2019 = DateTime(2019, 12, 15);

    test('A. a mid-size premium SUV with no purchase price lands in the '
        'realistic order of magnitude for its segment, never at the same '
        'level as a generic mainstream car', () {
      final q5 = engine.compute(q5Input(
        currentMileage: 89000,
        firstRegistrationDate: mecDec2021,
        condition: VehicleCondition.veryGood,
      ));
      final genericMainstream = engine.compute(baseInput(
        currentMileage: 89000,
        firstRegistrationDate: mecDec2021,
        condition: VehicleCondition.veryGood,
      ));
      // Order of magnitude only - the exact figure depends on finition/
      // motorisation/état, never a hardcoded target for this one vehicle.
      expect(q5.quickSale, greaterThan(300000));
      expect(q5.quickSale, lessThan(460000));
      expect(q5.fairPrice, lessThan(q5.highPrice));
      expect(q5.quickSale, greaterThan(genericMainstream.quickSale * 1.5));
    });

    test('B. more mileage never scores a better resale value, all else '
        'equal', () {
      final a = engine.compute(q5Input(
        currentMileage: 89000,
        firstRegistrationDate: mecDec2021,
        condition: VehicleCondition.veryGood,
      ));
      final b = engine.compute(q5Input(
        currentMileage: 150000,
        firstRegistrationDate: mecDec2021,
        condition: VehicleCondition.veryGood,
      ));
      expect(a.fairPrice, greaterThan(b.fairPrice));
    });

    test('C. a worse declared condition never scores a better resale '
        'value, all else equal', () {
      final a = engine.compute(q5Input(
        currentMileage: 89000,
        firstRegistrationDate: mecDec2021,
        condition: VehicleCondition.veryGood,
      ));
      final c = engine.compute(q5Input(
        currentMileage: 89000,
        firstRegistrationDate: mecDec2021,
        condition: VehicleCondition.average,
      ));
      expect(a.fairPrice, greaterThan(c.fairPrice));
    });

    test('D. an older first-registration date never scores a better resale '
        'value, all else equal', () {
      final a = engine.compute(q5Input(
        currentMileage: 89000,
        firstRegistrationDate: mecDec2021,
        condition: VehicleCondition.veryGood,
      ));
      final d = engine.compute(q5Input(
        currentMileage: 89000,
        firstRegistrationDate: mecDec2019,
        condition: VehicleCondition.veryGood,
      ));
      expect(a.fairPrice, greaterThan(d.fairPrice));
    });
  });

  group('Revente - référentiel sourcé (cas Opel Astra 2012, contrôle du moteur générique)', () {
    ValuationInput astraInput({
      required double currentMileage,
      required DateTime firstRegistrationDate,
      VehicleCondition? condition,
    }) {
      return ValuationInput(
        brand: 'Opel',
        model: 'Astra',
        year: firstRegistrationDate.year,
        firstRegistrationDate: firstRegistrationDate,
        currentMileage: currentMileage,
        condition: condition,
        maintenanceEntryCount: 3,
      );
    }

    final mecJune2012 = DateTime(2012, 6, 15);

    test(
        'A. a high-mileage 2012 compact anchored on a real, sourced 2012-era new price '
        'lands well above what the old, unsourced generic estimate produced - never at '
        '45 000 DH for a car that still has real resale value', () {
      final astra = engine.compute(astraInput(
        currentMileage: 270000,
        firstRegistrationDate: mecJune2012,
        condition: VehicleCondition.average,
      ));
      // Order of magnitude only, never a hardcoded target for this one
      // vehicle (RG: le calcul doit rester générique) - just a sanity band
      // around the real sourced reference price after 14 years and very
      // high mileage.
      expect(astra.fairPrice, greaterThan(50000));
      expect(astra.fairPrice, lessThan(90000));
      expect(astra.quickSale, lessThan(astra.fairPrice));
      expect(astra.highPrice, greaterThan(astra.fairPrice));
    });

    test('B. the base reference line is explicitly marked as a sourced price, not a '
        'generic approximation, for a vehicle/year covered by the sourced table', () {
      final astra = engine.compute(astraInput(
        currentMileage: 270000,
        firstRegistrationDate: mecJune2012,
      ));
      expect(astra.breakdown.first.label, contains('sourcé'));
      final sourcedFactor = astra.confidenceFactors
          .firstWhere((f) => f.label == 'Prix neuf de référence tracé à une source réelle');
      expect(sourcedFactor.satisfied, isTrue);
    });

    test('C. more mileage never scores a better resale value, all else equal - the '
        'generic mileage rule still applies untouched on top of the sourced base price', () {
      final lower = engine.compute(astraInput(currentMileage: 150000, firstRegistrationDate: mecJune2012));
      final higher = engine.compute(astraInput(currentMileage: 270000, firstRegistrationDate: mecJune2012));
      expect(higher.fairPrice, lessThan(lower.fairPrice));
    });

    test(
        'D. a brand/model/year the sourced table does NOT cover falls back to the generic '
        'estimate and is never claimed as sourced', () {
      final unsourced = engine.compute(astraInput(
        currentMileage: 90000,
        firstRegistrationDate: DateTime(2018, 6, 15),
      ));
      expect(unsourced.breakdown.first.label, contains('approximatif'));
      final sourcedFactor = unsourced.confidenceFactors
          .firstWhere((f) => f.label == 'Prix neuf de référence tracé à une source réelle');
      expect(sourcedFactor.satisfied, isFalse);
    });

    test(
        'E. a vehicle resting on the generic (unsourced) reference price never reaches '
        '"bonne confiance", no matter how complete the rest of its data is', () {
      final result = engine.compute(ValuationInput(
        brand: 'Opel',
        model: 'Astra',
        year: 2018,
        trim: 'Cosmo',
        firstRegistrationDate: DateTime(2018, 6, 15),
        currentMileage: 90000,
        fuelType: 'Diesel',
        transmission: 'Automatique',
        condition: VehicleCondition.excellent,
        maintenanceEntryCount: 8,
      ));
      expect(result.confidence, isNot(ConfidenceLevel.good));
    });
  });
}
