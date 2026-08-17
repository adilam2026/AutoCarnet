import 'package:autocarnet/core/database/database.dart';
import 'package:autocarnet/features/providers/data/provider_repository.dart';
import 'package:autocarnet/features/providers/domain/provider_matching.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

/// "Mémoriser les garages/prestataires saisis" - a provider typed once must
/// be suggested and reused afterwards, never retyped or duplicated.
void main() {
  group('isLikelyDuplicate (pure matching)', () {
    test('exact match after stripping "garage" / case / accents', () {
      expect(isLikelyDuplicate('Garage Audi Casablanca', 'Audi Casablanca'),
          isTrue);
    });

    test('local abbreviation "Casa" for "Casablanca" is recognized', () {
      expect(isLikelyDuplicate('Audi Casa', 'Garage Audi Casablanca'), isTrue);
    });

    test('different city for the same brand is never treated as a duplicate',
        () {
      expect(isLikelyDuplicate('Audi Rabat', 'Garage Audi Casablanca'),
          isFalse);
    });

    test('unrelated providers are never flagged as duplicates', () {
      expect(isLikelyDuplicate('Total Maarif', 'Assurance Wafa'), isFalse);
    });
  });

  group('ProviderRepository', () {
    late AppDatabase db;
    late ProviderRepository repo;

    setUp(() {
      db = AppDatabase(NativeDatabase.memory());
      repo = ProviderRepository(db);
    });

    tearDown(() => db.close());

    test(
        'TEST 21: typing "Audi" after creating "Garage Audi Casablanca" '
        'surfaces it via search - never forces retyping it', () async {
      await repo.createProvider(name: 'Garage Audi Casablanca');
      final results = await repo.search('Audi');
      expect(results.map((p) => p.name), contains('Garage Audi Casablanca'));
    });

    test(
        'a near-duplicate name reuses the existing provider instead of '
        'creating a second referential row', () async {
      final id = await repo.createProvider(name: 'Garage Audi Casablanca');
      final duplicate = await repo.findLikelyDuplicate('Audi Casa');
      expect(duplicate?.id, id);
    });

    test('a genuinely different provider is still created normally',
        () async {
      await repo.createProvider(name: 'Garage Audi Casablanca');
      final duplicate =
          await repo.findLikelyDuplicate('Station Afriquia Maarif');
      expect(duplicate, isNull);
    });
  });
}
