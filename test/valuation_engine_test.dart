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
    double? purchasePrice,
    DateTime? acquisitionDate,
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
      purchasePrice: purchasePrice,
      acquisitionDate: acquisitionDate,
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

  test('a real purchase price and acquisition date are prioritized over '
      'the internal brand-tier fallback', () {
    final fallbackOnly = engine.compute(baseInput());
    final withPurchase = engine.compute(baseInput(
      purchasePrice: 150000,
      acquisitionDate: DateTime.now().subtract(const Duration(days: 200)),
    ));
    expect(withPurchase.breakdown.first.label, contains('prix d\'achat'));
    expect(fallbackOnly.breakdown.first.label, contains('AutoCarnet'));
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
}
