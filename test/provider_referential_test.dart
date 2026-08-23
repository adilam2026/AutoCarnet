import 'package:autocarnet/core/database/database.dart';
import 'package:autocarnet/features/providers/data/provider_repository.dart';
import 'package:autocarnet/features/providers/domain/insurance_companies.dart';
import 'package:autocarnet/features/providers/domain/provider_matching.dart';
import 'package:autocarnet/features/providers/domain/service_provider_category.dart';
import 'package:drift/drift.dart' show Value;
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

    test(
        'CAS mission: "Audi Casablanca" / "AUDI CASABLANCA" / "Audi  Casablanca" '
        '(double space) never become three different prestataires', () async {
      final id = await repo.createProvider(name: 'Audi Casablanca');
      final upper = await repo.findLikelyDuplicate('AUDI CASABLANCA');
      final spaced = await repo.findLikelyDuplicate('Audi  Casablanca');
      expect(upper?.id, id);
      expect(spaced?.id, id);
    });

    test('createProvider persists a category, and it comes back untouched', () async {
      final id = await repo.createProvider(
        name: 'Audi Casablanca',
        category: ServiceProviderCategory.concessionnaire,
      );
      final saved = await repo.getById(id);
      expect(saved!.category, ServiceProviderCategory.concessionnaire);
    });

    test('updateProvider changes name/category/contact fields on an '
        'existing prestataire', () async {
      final id = await repo.createProvider(
        name: 'Garage X',
        category: ServiceProviderCategory.centreMecanique,
      );
      await repo.updateProvider(
        id: id,
        name: 'Garage X Renommé',
        category: const Value(ServiceProviderCategory.garageAgree),
        city: const Value('Rabat'),
        phone: const Value('0600000000'),
      );
      final saved = await repo.getById(id);
      expect(saved!.name, 'Garage X Renommé');
      expect(saved.category, ServiceProviderCategory.garageAgree);
      expect(saved.city, 'Rabat');
      expect(saved.phone, '0600000000');
    });

    test('deleteProvider soft-deletes: it disappears from watchAll but the '
        'row (and anything referencing it) still exists', () async {
      final id = await repo.createProvider(name: 'Garage Y');
      await repo.deleteProvider(id);
      final all = await repo.watchAll().first;
      expect(all.where((p) => p.id == id), isEmpty);
      final stillThere = await repo.getById(id);
      expect(stillThere, isNotNull);
      expect(stillThere!.isArchived, isTrue);
    });

    test('search with a category filter includes matching-category and '
        'uncategorised providers, but excludes a different category',
        () async {
      await repo.createProvider(
          name: 'Station Afriquia', category: ServiceProviderCategory.stationService);
      await repo.createProvider(
          name: 'Station Total', category: ServiceProviderCategory.concessionnaire);
      await repo.createProvider(name: 'Station Legacy');

      final results = await repo.search('Station',
          category: ServiceProviderCategory.stationService);
      final names = results.map((p) => p.name).toSet();
      expect(names, contains('Station Afriquia'));
      expect(names, contains('Station Legacy'));
      expect(names, isNot(contains('Station Total')));
    });
  });

  group('ProviderFilter (pure)', () {
    test('"Entretien" matches concessionnaire/garageAgree/centreMecanique, '
        'never assurance or stationService', () {
      expect(ProviderFilter.maintenance.matches(ServiceProviderCategory.concessionnaire),
          isTrue);
      expect(ProviderFilter.maintenance.matches(ServiceProviderCategory.garageAgree), isTrue);
      expect(
          ProviderFilter.maintenance.matches(ServiceProviderCategory.centreMecanique), isTrue);
      expect(ProviderFilter.maintenance.matches(ServiceProviderCategory.assurance), isFalse);
      expect(
          ProviderFilter.maintenance.matches(ServiceProviderCategory.stationService), isFalse);
    });

    test('"Autres" matches a null category and ServiceProviderCategory.autre only', () {
      expect(ProviderFilter.other.matches(null), isTrue);
      expect(ProviderFilter.other.matches(ServiceProviderCategory.autre), isTrue);
      expect(ProviderFilter.other.matches(ServiceProviderCategory.assurance), isFalse);
    });

    test('"Tous" matches every category and null', () {
      expect(ProviderFilter.all.matches(null), isTrue);
      for (final c in ServiceProviderCategory.values) {
        expect(ProviderFilter.all.matches(c), isTrue);
      }
    });
  });

  group('moroccanAutoInsurers (pure)', () {
    test('is a non-empty list of distinct, non-blank names, "Saham" nowhere '
        'in it (rebranded to Sanlam)', () {
      expect(moroccanAutoInsurers, isNotEmpty);
      expect(moroccanAutoInsurers.toSet().length, moroccanAutoInsurers.length,
          reason: 'no duplicate entries');
      for (final name in moroccanAutoInsurers) {
        expect(name.trim(), name, reason: 'no leading/trailing whitespace');
        expect(name, isNotEmpty);
      }
      expect(moroccanAutoInsurers, isNot(contains('Saham Assurance')));
      expect(moroccanAutoInsurers, contains('Sanlam Maroc'));
      // "Autre" is deliberately never a preset entry - free typing already
      // covers it (mission point 4).
      expect(moroccanAutoInsurers, isNot(contains('Autre')));
    });
  });
}
