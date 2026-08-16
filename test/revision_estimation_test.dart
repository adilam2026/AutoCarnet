import 'package:autocarnet/core/database/database.dart';
import 'package:autocarnet/features/maintenance/domain/revision_estimation.dart';
import 'package:flutter_test/flutter_test.dart';

MileageEntry _entry(DateTime date, double value) => MileageEntry(
      id: 'm-${date.toIso8601String()}',
      vehicleId: 'v1',
      value: value,
      recordedAt: date,
      source: 'manual',
      sourceId: null,
      note: null,
      createdAt: date,
    );

void main() {
  group('estimateNextRevision', () {
    test('Cas A: dernière révision 80 000 km, fréquence 10 000 km, actuel '
        '86 000 km → prochaine = 90 000, reste = 4 000', () {
      final result = estimateNextRevision(
        lastRevisionMileage: 80000,
        frequencyKm: 10000,
        currentMileage: 86000,
      );
      expect(result.nextMileage, 90000);
      expect(result.remainingKm, 4000);
      expect(result.isOverdueByMileage, isFalse);
    });

    test('Cas B: à un rythme de 2 000 km/mois avec 4 000 km restants, '
        'l\'estimation tombe environ 2 mois plus tard', () {
      final result = estimateNextRevision(
        lastRevisionMileage: 80000,
        frequencyKm: 10000,
        currentMileage: 86000,
        monthlyPaceKm: 2000,
      );
      expect(result.estimatedDateByPace, isNotNull);
      final daysAhead =
          result.estimatedDateByPace!.difference(DateTime.now()).inDays;
      expect(daysAhead, inInclusiveRange(55, 65)); // ~2 months
    });

    test(
        'Cas C: pas assez de relevés kilométriques → aucune date estimée '
        'inventée, seul le seuil kilométrique (certain) est renvoyé', () {
      final result = estimateNextRevision(
        lastRevisionMileage: 80000,
        frequencyKm: 10000,
        currentMileage: 86000,
        monthlyPaceKm: null,
      );
      expect(result.estimatedDateByPace, isNull);
      expect(result.nextMileage, 90000);
      expect(result.remainingKm, 4000);
    });

    test('Cas D: révision tous les 10 000 km ou 12 mois → retient '
        'l\'échéance estimée la plus proche', () {
      final lastDate = DateTime(2026, 1, 1);
      // Current pace implies the km threshold arrives well before the
      // 12-month calendar deadline.
      final result = estimateNextRevision(
        lastRevisionMileage: 80000,
        lastRevisionDate: lastDate,
        frequencyKm: 10000,
        frequencyMonths: 12,
        currentMileage: 86000,
        monthlyPaceKm: 3000, // reaches 90 000 km in ~2 months
      );
      expect(result.nextDateByFrequency, DateTime(2027, 1, 1));
      expect(result.estimatedDateByPace, isNotNull);
      expect(result.probableDate, result.estimatedDateByPace);
      expect(result.probableDate!.isBefore(result.nextDateByFrequency!), isTrue);
    });

    test('Cas D bis: un usage faible retient l\'échéance annuelle plutôt '
        'que le seuil kilométrique', () {
      final lastDate = DateTime(2026, 1, 1);
      final result = estimateNextRevision(
        lastRevisionMileage: 80000,
        lastRevisionDate: lastDate,
        frequencyKm: 10000,
        frequencyMonths: 12,
        currentMileage: 80500,
        monthlyPaceKm: 100, // very low usage: km threshold is far away
      );
      expect(result.probableDate, result.nextDateByFrequency);
    });

    test('un véhicule déjà au-delà du seuil est marqué en retard', () {
      final result = estimateNextRevision(
        lastRevisionMileage: 80000,
        frequencyKm: 10000,
        currentMileage: 91200,
      );
      expect(result.isOverdueByMileage, isTrue);
      expect(result.remainingKm, lessThan(0));
    });
  });

  group('estimateMonthlyPaceKm', () {
    test('calcule un rythme mensuel à partir de relevés réels espacés dans '
        'le temps', () {
      final now = DateTime.now();
      final history = [
        _entry(now.subtract(const Duration(days: 90)), 80000),
        _entry(now.subtract(const Duration(days: 60)), 81600),
        _entry(now.subtract(const Duration(days: 30)), 83100),
        _entry(now, 84700),
      ];
      final pace = estimateMonthlyPaceKm(history);
      expect(pace, isNotNull);
      expect(pace, inInclusiveRange(1400, 1700));
    });

    test('Cas C: un seul relevé ne permet aucune estimation de rythme', () {
      final history = [_entry(DateTime.now(), 80000)];
      expect(estimateMonthlyPaceKm(history), isNull);
    });

    test('des relevés trop rapprochés dans le temps ne produisent pas de '
        'rythme fiable', () {
      final now = DateTime.now();
      final history = [
        _entry(now.subtract(const Duration(hours: 2)), 80000),
        _entry(now, 80050),
      ];
      expect(estimateMonthlyPaceKm(history), isNull);
    });
  });

  group('observeFrequencyKm', () {
    test('Cas E: plusieurs révisions historiques autour de 10 000 km '
        'suggèrent une fréquence proche de 10 000 km sans l\'imposer', () {
      final observed = observeFrequencyKm([40000, 50100, 60200]);
      expect(observed, isNotNull);
      expect(observed, inInclusiveRange(9500, 10500));
    });

    test('moins de trois révisions ne permet aucune suggestion', () {
      expect(observeFrequencyKm([40000, 50100]), isNull);
    });
  });
}
