import 'package:autocarnet/features/vehicles/domain/vehicle_compliance_rules.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('visiteTechniqueMandatoryYet', () {
    final now = DateTime(2026, 6, 1);

    test('a vehicle registered less than 5 years ago is not yet subject to it', () {
      final registered = DateTime(2023, 1, 1); // ~3.4 years old
      expect(visiteTechniqueMandatoryYet(registered, now: now), isFalse);
    });

    test('a vehicle registered exactly 5 years ago is subject to it', () {
      final registered = DateTime(2021, 6, 1); // exactly 5 years old
      expect(visiteTechniqueMandatoryYet(registered, now: now), isTrue);
    });

    test('a vehicle registered well over 5 years ago is subject to it', () {
      final registered = DateTime(2015, 1, 1);
      expect(visiteTechniqueMandatoryYet(registered, now: now), isTrue);
    });

    test('an unknown registration date defaults to mandatory - never '
        'silently hides a real requirement', () {
      expect(visiteTechniqueMandatoryYet(null, now: now), isTrue);
    });
  });
}
