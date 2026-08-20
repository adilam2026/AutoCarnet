import 'package:drift/drift.dart';

/// Local profile - AutoCarnet is offline-first: a single local profile is
/// enough until a cloud account/backend is introduced (see onboarding_lock).
class LocalProfiles extends Table {
  TextColumn get id => text()();
  TextColumn get displayName => text()();
  TextColumn get avatarPath => text().nullable()();
  TextColumn get currency => text().withDefault(const Constant('MAD'))();
  TextColumn get distanceUnit => text().withDefault(const Constant('km'))();
  DateTimeColumn get createdAt => dateTime()();
  // Which cloud account this profile's preferences belong to - null for a
  // profile created before any account ever signed in on this device (pure
  // offline use, or the brief window before AppGate reattributes/claims it).
  // Without this, displayName/currency/distanceUnit were device-wide: a
  // second account signing in on the same phone would silently inherit the
  // first account's name and currency instead of getting its own.
  TextColumn get ownerId => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

enum VehicleStatus { active, archived, sold, destroyed }

/// How precisely [Vehicles.firstRegistrationDate] is actually known - an
/// age-dependent calculation (depreciation, reminders) must never pretend a
/// day/month the owner never entered.
enum DatePrecision { full, monthYear, yearOnly }

enum VehicleCondition { excellent, veryGood, good, average, needsWork }

class Vehicles extends Table {
  TextColumn get id => text()();
  TextColumn get brand => text()();
  TextColumn get model => text()();
  TextColumn get trim => text().nullable()();
  IntColumn get year => integer().nullable()();
  DateTimeColumn get firstRegistrationDate => dateTime().nullable()();
  TextColumn get firstRegistrationDatePrecision =>
      textEnum<DatePrecision>().nullable()();
  TextColumn get vin => text().nullable()();
  TextColumn get plate => text().nullable()();
  TextColumn get motorization => text().nullable()();
  TextColumn get fiscalPower => text().nullable()();
  TextColumn get fuelType => text().nullable()();
  TextColumn get transmission => text().nullable()();
  TextColumn get color => text().nullable()();
  TextColumn get photoPath => text().nullable()();
  DateTimeColumn get acquisitionDate => dateTime().nullable()();
  RealColumn get purchasePrice => real().nullable()();
  TextColumn get condition => textEnum<VehicleCondition>().nullable()();
  TextColumn get comments => text().nullable()();
  RealColumn get currentMileage => real()();
  TextColumn get status =>
      textEnum<VehicleStatus>().withDefault(const Constant('active'))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();
  TextColumn get syncStatus =>
      text().withDefault(const Constant('pendingSync'))();
  // The cloud account id (Supabase auth.users.id) that owns this vehicle -
  // mirrors the cloud `vehicles.user_id` column once pulled. Null for a
  // vehicle that has never been synced (created offline, or the app has
  // no cloud account at all): the current device's user is its de facto
  // sole owner either way. Used purely to gate owner-only UI (delete,
  // "Partage et accès") - the real enforcement is server-side RLS.
  TextColumn get ownerId => text().nullable()();
  // This device's own access level on a shared (not owned) vehicle -
  // 'viewer' or 'editor', mirrored from the cloud `vehicle_members` table
  // on every pull so it's known offline too (needed to gate edit actions
  // for a viewer entirely client-side, since a viewer's local edit would
  // otherwise "succeed" locally and then just fail to ever sync). Null for
  // an owned vehicle (ownerId null or == the signed-in account).
  TextColumn get myRole => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Mileage is critical data (RG-VEH-005/006/007): every change is versioned,
/// never overwritten in place.
class MileageEntries extends Table {
  TextColumn get id => text()();
  TextColumn get vehicleId => text().references(Vehicles, #id)();
  RealColumn get value => real()();
  DateTimeColumn get recordedAt => dateTime()();
  TextColumn get source => text()(); // manual, maintenance, fuel, document, odometer_replacement
  TextColumn get sourceId => text().nullable()();
  TextColumn get note => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

class ServiceProviders extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get type => text().nullable()();
  TextColumn get address => text().nullable()();
  TextColumn get city => text().nullable()();
  TextColumn get country => text().nullable()();
  TextColumn get phone => text().nullable()();
  TextColumn get email => text().nullable()();
  TextColumn get website => text().nullable()();
  TextColumn get comments => text().nullable()();
  BoolColumn get isArchived => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  // The cloud account id signed in when this provider was created - this
  // référentiel has no cloud sync of its own (purely local), so unlike
  // Vehicles.ownerId this is set directly at creation time, never by a
  // pull. Null for a provider created with no cloud account at all. Used
  // to keep two different accounts that have used the same physical
  // device from seeing each other's private contacts (RG audit - see
  // ProviderRepository.watchAll).
  TextColumn get ownerId => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Logical document. Each renewal creates a new DocumentVersions row and the
/// previous one is flipped to "replaced" - history is never overwritten
/// (RG-DOC-002/003).
class Documents extends Table {
  TextColumn get id => text()();
  TextColumn get vehicleId =>
      text().nullable().references(Vehicles, #id)(); // null for driver docs (e.g. permis)
  TextColumn get type => text()();
  TextColumn get holder => text().nullable()();
  TextColumn get currentVersionId => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();
  // Only meaningful (and only ever checked) for a driver document
  // (vehicleId null): a vehicle-scoped document's visibility already
  // follows the vehicle it belongs to. Set directly at creation time from
  // whichever account is signed in then - documents have no cloud sync of
  // their own yet. See DocumentRepository.watchDriverDocuments.
  TextColumn get ownerId => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

enum DocumentVersionStatus { valid, expiringSoon, expired, archived, replaced }

class DocumentVersions extends Table {
  TextColumn get id => text()();
  TextColumn get documentId => text().references(Documents, #id)();
  TextColumn get documentNumber => text().nullable()();
  DateTimeColumn get issueDate => dateTime().nullable()();
  DateTimeColumn get expiryDate => dateTime().nullable()();
  RealColumn get cost => real().nullable()();
  TextColumn get providerId => text().nullable().references(ServiceProviders, #id)();
  TextColumn get comments => text().nullable()();
  TextColumn get status =>
      textEnum<DocumentVersionStatus>().withDefault(const Constant('valid'))();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

class DocumentAttachments extends Table {
  TextColumn get id => text()();
  TextColumn get documentVersionId =>
      text().references(DocumentVersions, #id)();
  TextColumn get filePath => text()();
  TextColumn get fileName => text()();
  TextColumn get fileType => text()();
  IntColumn get sizeBytes => integer().nullable()();
  DateTimeColumn get addedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

class MaintenanceEntries extends Table {
  TextColumn get id => text()();
  TextColumn get vehicleId => text().references(Vehicles, #id)();
  TextColumn get category => text()();
  DateTimeColumn get date => dateTime()();
  RealColumn get mileage => real()();
  TextColumn get providerId => text().nullable().references(ServiceProviders, #id)();
  RealColumn get partsCost => real().withDefault(const Constant(0))();
  RealColumn get laborCost => real().withDefault(const Constant(0))();
  TextColumn get currency => text().withDefault(const Constant('MAD'))();
  IntColumn get warrantyMonths => integer().nullable()();
  TextColumn get comments => text().nullable()();
  DateTimeColumn get nextDueDate => dateTime().nullable()();
  RealColumn get nextDueMileage => real().nullable()();
  TextColumn get linkedExpenseId => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}

class MaintenanceParts extends Table {
  TextColumn get id => text()();
  TextColumn get maintenanceEntryId =>
      text().references(MaintenanceEntries, #id)();
  TextColumn get designation => text()();
  TextColumn get reference => text().nullable()();
  TextColumn get brand => text().nullable()();
  RealColumn get quantity => real().withDefault(const Constant(1))();
  RealColumn get unitPrice => real().withDefault(const Constant(0))();
  TextColumn get comments => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

class Expenses extends Table {
  TextColumn get id => text()();
  TextColumn get vehicleId => text().references(Vehicles, #id)();
  TextColumn get category => text()();
  DateTimeColumn get date => dateTime()();
  RealColumn get amount => real()();
  TextColumn get currency => text().withDefault(const Constant('MAD'))();
  TextColumn get providerId => text().nullable().references(ServiceProviders, #id)();
  RealColumn get mileage => real().nullable()();
  TextColumn get paymentMethod => text().nullable()();
  TextColumn get comments => text().nullable()();
  TextColumn get linkedMaintenanceId =>
      text().nullable().references(MaintenanceEntries, #id)();
  TextColumn get linkedFuelId => text().nullable()();
  TextColumn get linkedDocumentVersionId =>
      text().nullable().references(DocumentVersions, #id)();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}

class FuelEntries extends Table {
  TextColumn get id => text()();
  TextColumn get vehicleId => text().references(Vehicles, #id)();
  DateTimeColumn get date => dateTime()();
  RealColumn get mileage => real()();
  TextColumn get providerId => text().nullable().references(ServiceProviders, #id)();
  TextColumn get fuelType => text()();
  RealColumn get quantityLiters => real()();
  RealColumn get pricePerLiter => real()();
  RealColumn get totalAmount => real()();
  BoolColumn get isFullTank => boolean().withDefault(const Constant(true))();
  TextColumn get comments => text().nullable()();
  TextColumn get linkedExpenseId => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}

/// Aggregation only - never written to directly by the UI, always produced
/// by the owning module's repository (RG-TIME-001/002).
class TimelineEvents extends Table {
  TextColumn get id => text()();
  TextColumn get vehicleId => text().references(Vehicles, #id)();
  TextColumn get moduleOrigin => text()();
  TextColumn get eventType => text()();
  TextColumn get title => text()();
  TextColumn get description => text().nullable()();
  DateTimeColumn get occurredAt => dateTime()();
  TextColumn get importance => text().withDefault(const Constant('normal'))();
  TextColumn get linkedEntityId => text().nullable()();
  TextColumn get linkedEntityType => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Technical/CRUD trail (bloc "Journal d'audit") - deliberately separate
/// from [TimelineEvents]: a vehicle being created, its sheet being edited,
/// or its mileage being corrected are data-entry facts, not automobile
/// interventions, and must never mix into the business history the driver
/// sees on the vehicle dashboard.
class AuditEvents extends Table {
  TextColumn get id => text()();
  TextColumn get vehicleId => text().nullable().references(Vehicles, #id)();
  TextColumn get entityType => text()(); // vehicle, maintenance, fuel, expense, document...
  TextColumn get entityId => text().nullable()();
  TextColumn get action => text()(); // created, updated, status_changed, deleted...
  TextColumn get summary => text()();
  DateTimeColumn get occurredAt => dateTime()();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

/// A per-vehicle, per-category frequency the owner has explicitly
/// confirmed (RG: "ne jamais modifier automatiquement une fréquence
/// configurée sans son accord") - takes priority over
/// [OperationRecurrenceRules]'s built-in defaults.
class OperationFrequencyPreferences extends Table {
  TextColumn get id => text()();
  TextColumn get vehicleId => text().references(Vehicles, #id)();
  TextColumn get category => text()();
  RealColumn get frequencyKm => real().nullable()();
  IntColumn get frequencyMonths => integer().nullable()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

enum ReminderStatus { active, snoozed, done, dismissed }

/// Central reminder engine storage (RG-ALR-001/002): every module writes
/// here instead of managing its own notifications.
class Reminders extends Table {
  TextColumn get id => text()();
  TextColumn get vehicleId => text().references(Vehicles, #id)();
  TextColumn get sourceType => text()(); // document, maintenance, custom
  TextColumn get sourceId => text()();
  TextColumn get title => text()();
  DateTimeColumn get dueDate => dateTime().nullable()();
  RealColumn get dueMileage => real().nullable()();
  TextColumn get priority => text().withDefault(const Constant('normal'))();
  TextColumn get status =>
      textEnum<ReminderStatus>().withDefault(const Constant('active'))();
  DateTimeColumn get snoozedUntil => dateTime().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}
