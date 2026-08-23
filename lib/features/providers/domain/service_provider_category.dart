import '../../../core/database/database.dart';

/// French label for each [ServiceProviderCategory] - centralized here since
/// it's needed everywhere a category is shown or picked (Prestataires
/// screen, the provider form, the reusable picker).
extension ServiceProviderCategoryLabel on ServiceProviderCategory {
  String get label => switch (this) {
        ServiceProviderCategory.concessionnaire => 'Concessionnaire',
        ServiceProviderCategory.garageAgree => 'Garage agréé',
        ServiceProviderCategory.centreMecanique => 'Centre mécanique',
        ServiceProviderCategory.assurance => 'Assurance',
        ServiceProviderCategory.stationService => 'Station-service',
        ServiceProviderCategory.autre => 'Autre',
      };

  String get storageKey => name;

  static ServiceProviderCategory? fromKey(String? key) {
    for (final c in ServiceProviderCategory.values) {
      if (c.name == key) return c;
    }
    return null;
  }
}

/// Categories relevant to an entretien/révision (mission point 3) - used to
/// both populate the category dropdown on the provider form and to bias the
/// picker's suggestions when logging a maintenance operation.
const maintenanceProviderCategories = [
  ServiceProviderCategory.concessionnaire,
  ServiceProviderCategory.garageAgree,
  ServiceProviderCategory.centreMecanique,
  ServiceProviderCategory.autre,
];

/// The Prestataires screen's own filter groups (mission point 7: "Tous /
/// Entretien / Assurance / Carburant / Autres") - "Entretien" groups three
/// categories into one filter chip since they're all workshop-shaped, while
/// Assurance and Carburant each map to exactly one category.
enum ProviderFilter { all, maintenance, assurance, fuel, other }

extension ProviderFilterLabel on ProviderFilter {
  String get label => switch (this) {
        ProviderFilter.all => 'Tous',
        ProviderFilter.maintenance => 'Entretien',
        ProviderFilter.assurance => 'Assurance',
        ProviderFilter.fuel => 'Carburant',
        ProviderFilter.other => 'Autres',
      };

  bool matches(ServiceProviderCategory? category) => switch (this) {
        ProviderFilter.all => true,
        ProviderFilter.maintenance => maintenanceProviderCategories.contains(category) &&
            category != ServiceProviderCategory.autre,
        ProviderFilter.assurance => category == ServiceProviderCategory.assurance,
        ProviderFilter.fuel => category == ServiceProviderCategory.stationService,
        ProviderFilter.other =>
          category == null || category == ServiceProviderCategory.autre,
      };
}
