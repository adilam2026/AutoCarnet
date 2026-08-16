import 'package:autocarnet/features/maintenance/domain/operation_recurrence_rules.dart';
import 'package:autocarnet/features/maintenance/domain/revision_estimation.dart';
import 'package:flutter_test/flutter_test.dart';

/// Cahier des charges bloc 21 - the five mandated CAS.
void main() {
  test('CAS 1: vidange without a vehicle-specific frequency defaults to '
      '+10 000 km', () {
    final resolved = resolveFrequency(category: 'Vidange');
    expect(resolved.isRecurrent, isTrue);
    expect(resolved.frequencyKm, 10000);
    expect(resolved.isVehicleSpecific, isFalse);

    final estimate = estimateNextRevision(
      lastRevisionMileage: 86700,
      frequencyKm: resolved.frequencyKm,
      currentMileage: 86700,
    );
    expect(estimate.nextMileage, 96700);
  });

  test('CAS 2: révision uses the vehicle\'s configured 15 000 km frequency '
      'instead of the AutoCarnet default', () {
    final resolved = resolveFrequency(category: 'Révision', vehicleFrequencyKm: 15000);
    expect(resolved.frequencyKm, 15000);
    expect(resolved.isVehicleSpecific, isTrue);

    final estimate = estimateNextRevision(
      lastRevisionMileage: 90000,
      frequencyKm: resolved.frequencyKm,
      currentMileage: 90000,
    );
    expect(estimate.nextMileage, 105000);
  });

  test('CAS 3: a diagnostic never gets an automatic next-due échéance', () {
    final resolved = resolveFrequency(category: 'Contrôle / diagnostic');
    expect(resolved.isRecurrent, isFalse);
    expect(resolved.frequencyKm, isNull);
    expect(resolved.frequencyMonths, isNull);
  });

  test('CAS 4: a bodywork repair never gets an automatic échéance', () {
    final resolved = resolveFrequency(category: 'Carrosserie');
    expect(resolved.isRecurrent, isFalse);
    final resolvedReparation = resolveFrequency(category: 'Réparation');
    expect(resolvedReparation.isRecurrent, isFalse);
  });

  test('CAS 5: a 10 000 km OU 12 mois révision considers both rules and '
      'retains whichever threshold comes first', () {
    final resolved = resolveFrequency(
      category: 'Révision',
      vehicleFrequencyKm: 10000,
      vehicleFrequencyMonths: 12,
    );
    expect(resolved.frequencyKm, 10000);
    expect(resolved.frequencyMonths, 12);

    final lastDate = DateTime(2026, 1, 1);
    final fastPace = estimateNextRevision(
      lastRevisionMileage: 80000,
      lastRevisionDate: lastDate,
      frequencyKm: resolved.frequencyKm,
      frequencyMonths: resolved.frequencyMonths,
      currentMileage: 86000,
      monthlyPaceKm: 3000, // reaches the km threshold well before 12 months
    );
    expect(fastPace.nextDateByFrequency, DateTime(2027, 1, 1));
    expect(fastPace.estimatedDateByPace, isNotNull);
    expect(fastPace.probableDate, fastPace.estimatedDateByPace);

    final slowPace = estimateNextRevision(
      lastRevisionMileage: 80000,
      lastRevisionDate: lastDate,
      frequencyKm: resolved.frequencyKm,
      frequencyMonths: resolved.frequencyMonths,
      currentMileage: 80200,
      monthlyPaceKm: 50, // km threshold is far away, calendar deadline wins
    );
    expect(slowPace.probableDate, slowPace.nextDateByFrequency);
  });

  test('a vehicle-specific frequency is never applied without being '
      'explicitly passed in - no silent override of the built-in default', () {
    final withoutOverride = resolveFrequency(category: 'Vidange');
    expect(withoutOverride.isVehicleSpecific, isFalse);
    expect(withoutOverride.frequencyKm, 10000);
  });
}
