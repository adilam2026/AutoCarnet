import 'package:autocarnet/features/vehicles/domain/brand_logos.dart';
import 'package:autocarnet/features/vehicles/domain/brand_normalization.dart';
import 'package:autocarnet/features/vehicles/domain/vehicle_reference_data.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('normalizeBrand', () {
    test('VW / Volkswagen both resolve to the canonical "Volkswagen"', () {
      expect(normalizeBrand('VW'), 'Volkswagen');
      expect(normalizeBrand('Volkswagen'), 'Volkswagen');
      expect(normalizeBrand('volkswagen'), 'Volkswagen');
    });

    test('Mercedes / Mercedes-Benz both resolve to "Mercedes-Benz"', () {
      expect(normalizeBrand('Mercedes'), 'Mercedes-Benz');
      expect(normalizeBrand('Mercedes-Benz'), 'Mercedes-Benz');
      expect(normalizeBrand('mercedes benz'), 'Mercedes-Benz');
    });

    test('Citroen (no diaeresis) resolves to "Citroën"', () {
      expect(normalizeBrand('Citroen'), 'Citroën');
      expect(normalizeBrand('citroën'), 'Citroën');
    });

    test('Skoda (no caron) resolves to "Škoda"', () {
      expect(normalizeBrand('Skoda'), 'Škoda');
    });

    test('an unrecognised free-text brand is returned unchanged, never guessed at', () {
      expect(normalizeBrand('MaBrandInventee'), 'MaBrandInventee');
    });

    test('every carBrands entry normalizes to itself', () {
      for (final brand in carBrands) {
        expect(normalizeBrand(brand), brand, reason: brand);
      }
    });
  });

  group('brandLogoFor', () {
    test('a covered brand (any spelling variant) returns a non-null glyph', () {
      expect(brandLogoFor('Audi'), isNotNull);
      expect(brandLogoFor('VW'), isNotNull);
      expect(brandLogoFor('Volkswagen'), isNotNull);
      expect(brandLogoFor('Opel'), isNotNull);
      expect(brandLogoFor('citroen'), isNotNull);
    });

    test('VW and Volkswagen resolve to the exact same glyph', () {
      expect(brandLogoFor('VW'), brandLogoFor('Volkswagen'));
    });

    test('an uncovered brand (no simple_icons glyph, e.g. Jaguar) returns null - the '
        'caller falls back to a generic icon, never a guessed logo', () {
      expect(brandLogoFor('Jaguar'), isNull);
    });

    test('a genuinely unknown brand returns null, never throws', () {
      expect(brandLogoFor('MaBrandInventee'), isNull);
    });
  });
}
