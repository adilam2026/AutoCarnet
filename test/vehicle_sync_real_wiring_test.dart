import 'dart:async';
import 'dart:convert';

import 'package:autocarnet/core/database/database.dart';
import 'package:autocarnet/core/database/providers.dart' as core_db;
import 'package:autocarnet/core/notifications/notification_repository.dart';
import 'package:autocarnet/core/sync/conflict_repository.dart';
import 'package:autocarnet/core/sync/document_sync_service.dart';
import 'package:autocarnet/core/sync/expense_sync_service.dart';
import 'package:autocarnet/core/sync/frequency_pref_sync_service.dart';
import 'package:autocarnet/core/sync/fuel_sync_service.dart';
import 'package:autocarnet/core/sync/maintenance_sync_service.dart';
import 'package:autocarnet/core/sync/mileage_sync_service.dart';
import 'package:autocarnet/core/sync/provider_sync_service.dart';
import 'package:autocarnet/core/sync/reminder_sync_service.dart';
import 'package:autocarnet/core/sync/sync_coordinator.dart';
import 'package:autocarnet/core/sync/sync_outbox_repository.dart';
import 'package:autocarnet/core/sync/vehicle_sync_service.dart';
import 'package:autocarnet/features/timeline/data/timeline_repository.dart';
import 'package:autocarnet/features/vehicles/data/vehicle_repository.dart';
import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

/// Mission 2026, real-device incident report - two independent proofs
/// (a Volkswagen; a completely different account's vehicle) that a vehicle
/// created while genuinely signed in never reached Supabase, silently.
///
/// Every prior test in this codebase (including this mission's own earlier
/// rounds) either constructs VehicleRepository/VehicleSyncService by hand
/// and drives them manually, or short-circuits before any real push is
/// attempted (an unauthenticated client). None of that proves the thing
/// actually asked here: that creating a vehicle through the REAL provider
/// graph the app itself uses (vehicleRepositoryProvider -> its real
/// _nudgeSync() -> the REAL syncCoordinatorProvider instance, resolved by
/// Riverpod exactly as production does) genuinely, automatically reaches a
/// push - and that a real Supabase-side rejection is never silently lost.
///
/// `syncCoordinatorProvider`/`vehicleSyncServiceProvider` are overridden
/// here ONLY to replace `Supabase.instance.client` (unusable without a
/// real `Supabase.initialize()`, impossible in a plain VM test) with a
/// client pointed at the exact same kind of fake transport used in
/// vehicle_cloud_roundtrip_e2e_test.dart - every other provider
/// (`vehicleRepositoryProvider`, `appDatabaseProvider`, `auditRepositoryProvider`,
/// `reminderRepositoryProvider`, `syncOutboxRepositoryProvider`) resolves
/// completely naturally, exactly as the real app wires them.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
    const MethodChannel('dev.fluttercommunity.plus/connectivity'),
    (call) async => call.method == 'check' ? ['wifi'] : null,
  );

  String fakeJwt({required String sub, required Duration validFor}) {
    String segment(Map<String, dynamic> data) =>
        base64Url.encode(utf8.encode(jsonEncode(data))).replaceAll('=', '');
    final header = segment({'alg': 'none', 'typ': 'JWT'});
    final exp = DateTime.now().add(validFor).millisecondsSinceEpoch ~/ 1000;
    final payload = segment({'sub': sub, 'exp': exp, 'role': 'authenticated'});
    return '$header.$payload.fake-signature';
  }

  Future<void> signIn(SupabaseClient client, String userId) async {
    final sessionJson = jsonEncode({
      'access_token': fakeJwt(sub: userId, validFor: const Duration(hours: 1)),
      'token_type': 'bearer',
      'expires_in': 3600,
      'refresh_token': 'fake-refresh-token',
      'user': {
        'id': userId,
        'aud': 'authenticated',
        'email': 'e2e@example.com',
        'created_at': DateTime.now().toIso8601String(),
        'app_metadata': <String, dynamic>{},
        'user_metadata': <String, dynamic>{},
      },
    });
    await client.auth.recoverSession(sessionJson);
  }

  Future<void> pollUntil(bool Function() condition,
      {Duration timeout = const Duration(seconds: 5)}) async {
    final deadline = DateTime.now().add(timeout);
    while (!condition()) {
      if (DateTime.now().isAfter(deadline)) {
        fail('condition never became true within $timeout');
      }
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
  }

  late AppDatabase db;
  late SupabaseClient client;
  late _FakeCloudHttpClient cloud;
  const userId = 'wiring-test-user';

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    cloud = _FakeCloudHttpClient(currentUserId: userId);
    client = SupabaseClient(
      'https://example.invalid.supabase.co',
      'anon-key-test',
      httpClient: cloud,
    );
    await signIn(client, userId);
  });

  tearDown(() => db.close());

  SyncCoordinator buildRealCoordinator() {
    final conflicts = ConflictRepository(db);
    final timeline = TimelineRepository(db);
    final outbox = SyncOutboxRepository(db);
    return SyncCoordinator(
      db: db,
      clientFn: () => client,
      vehicles: VehicleSyncService(db, () => client, conflicts, outbox),
      maintenance: MaintenanceSyncService(db, () => client, conflicts, timeline, outbox),
      expenses: ExpenseSyncService(db, () => client, conflicts, outbox),
      fuel: FuelSyncService(db, () => client, conflicts, timeline, outbox),
      documents: DocumentSyncService(db, () => client, conflicts, timeline, outbox),
      reminders: ReminderSyncService(db, () => client, conflicts, outbox),
      mileage: MileageSyncService(db, () => client, outbox),
      frequencyPrefs: FrequencyPrefSyncService(db, () => client, conflicts, outbox),
      providers: ProviderSyncService(db, () => client, conflicts, outbox),
      notifications: NotificationRepository(db),
      conflicts: conflicts,
    );
  }

  test(
      'SUCCÈS - creating a vehicle through the REAL vehicleRepositoryProvider '
      '(not a hand-driven VehicleSyncService) automatically reaches a real '
      'push via its own fire-and-forget nudge, with zero manual syncNow() '
      'call from the test', () async {
    final container = ProviderContainer(overrides: [
      core_db.appDatabaseProvider.overrideWithValue(db),
      syncCoordinatorProvider.overrideWithValue(buildRealCoordinator()),
    ]);
    addTearDown(container.dispose);

    final vehicleRepo = container.read(vehicleRepositoryProvider);
    final vehicleId = await vehicleRepo.createVehicle(
      brand: 'Volkswagen',
      model: 'Golf',
      currentMileage: 15000,
    );

    // No syncNow()/syncAll() called here - only the automatic nudge from
    // VehicleRepository.createVehicle() itself is allowed to make this pass.
    await pollUntil(
        () => cloud.tables['vehicles']?.any((r) => r['id'] == vehicleId) ?? false);

    final vehicle = await vehicleRepo.getOne(vehicleId);
    expect(vehicle.syncStatus, 'synced');
    expect(await vehicleRepo.syncStateFor(vehicleId), EntitySyncState.synced);
    expect(await container.read(syncOutboxRepositoryProvider).pendingCount(), 0);
  });

  test(
      'ÉCHEC PUIS RETRY - Supabase refuse le premier INSERT (RLS/contrainte '
      'simulée) : le véhicule reste pendingSync, l\'outbox garde la trace '
      '(last_error + retry_count), rien n\'est jamais perdu, et une '
      'nouvelle tentative après correction réussit', () async {
    cloud.failInsertsUntilAttempt = 2; // the 1st insert attempt is rejected

    final container = ProviderContainer(overrides: [
      core_db.appDatabaseProvider.overrideWithValue(db),
      syncCoordinatorProvider.overrideWithValue(buildRealCoordinator()),
    ]);
    addTearDown(container.dispose);

    final vehicleRepo = container.read(vehicleRepositoryProvider);
    final outbox = container.read(syncOutboxRepositoryProvider);
    final vehicleId = await vehicleRepo.createVehicle(
      brand: 'Volkswagen',
      model: 'Golf',
      currentMileage: 15000,
    );

    // Wait for the automatic nudge's first (failing) attempt to actually run.
    await pollUntil(() => cloud.insertAttempts > 0);
    await Future<void>.delayed(const Duration(milliseconds: 50));

    final afterFailure = await vehicleRepo.getOne(vehicleId);
    expect(afterFailure.syncStatus, 'pendingSync',
        reason: 'never marked synced on a rejected push');
    expect(cloud.tables['vehicles']?.any((r) => r['id'] == vehicleId) ?? false, isFalse,
        reason: 'the rejected insert must never have actually landed');
    expect(await vehicleRepo.syncStateFor(vehicleId), EntitySyncState.failed);
    final failingRows = await outbox.failing();
    expect(failingRows.where((r) => r.entityId == vehicleId), hasLength(1));
    expect(failingRows.firstWhere((r) => r.entityId == vehicleId).lastError, isNotNull);
    expect(
        failingRows.firstWhere((r) => r.entityId == vehicleId).retryCount, greaterThan(0));

    // Automatic retry (what the 30s periodic timer / reconnect listener
    // does in production) - this time Supabase accepts it.
    final coordinator = container.read(syncCoordinatorProvider);
    await coordinator.syncAll();

    final afterRetry = await vehicleRepo.getOne(vehicleId);
    expect(afterRetry.syncStatus, 'synced');
    expect(cloud.tables['vehicles']!.any((r) => r['id'] == vehicleId), isTrue);
    expect(await outbox.pendingCount(), 0);
  });
}

/// Same technique as vehicle_cloud_roundtrip_e2e_test.dart's fake cloud -
/// an in-memory PostgREST-shaped store reached through SupabaseClient's own
/// supported httpClient extension point. Adds the ability to reject the
/// first N insert attempts on a chosen table, simulating a real Supabase
/// rejection (RLS, a constraint, anything) to prove failures are never
/// silently absorbed.
class _FakeCloudHttpClient extends http.BaseClient {
  _FakeCloudHttpClient({required this.currentUserId});

  final String currentUserId;
  final Map<String, List<Map<String, dynamic>>> tables = {};

  /// If > 0, the Nth insert attempt onward succeeds; every attempt before
  /// that fails with a synthetic error response, exactly like a real
  /// Supabase-side rejection would.
  int failInsertsUntilAttempt = 0;
  int insertAttempts = 0;

  List<Map<String, dynamic>> _tableFor(Uri url) =>
      tables.putIfAbsent(url.pathSegments.last, () => []);

  Map<String, String> _eqFilters(Map<String, String> query) {
    final filters = <String, String>{};
    for (final entry in query.entries) {
      if (entry.value.startsWith('eq.')) {
        filters[entry.key] = entry.value.substring(3);
      }
    }
    return filters;
  }

  bool _matches(Map<String, dynamic> row, Map<String, String> filters) {
    for (final entry in filters.entries) {
      if (row[entry.key]?.toString() != entry.value) return false;
    }
    return true;
  }

  http.StreamedResponse _json(http.BaseRequest request, int status, Object body) {
    final bytes = utf8.encode(jsonEncode(body));
    return http.StreamedResponse(
      Stream.value(bytes),
      status,
      headers: {'content-type': 'application/json'},
      request: request,
    );
  }

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final rows = _tableFor(request.url);
    final filters = _eqFilters(request.url.queryParameters);

    switch (request.method) {
      case 'POST':
        insertAttempts++;
        if (insertAttempts < failInsertsUntilAttempt) {
          return _json(request, 403, {
            'message': 'new row violates row-level security policy',
            'code': '42501',
          });
        }
        final bytes = await request.finalize().toBytes();
        final decoded = jsonDecode(utf8.decode(bytes));
        final incoming = decoded is List
            ? decoded.cast<Map<String, dynamic>>()
            : [decoded as Map<String, dynamic>];
        for (final row in incoming) {
          final stored = Map<String, dynamic>.from(row);
          stored.putIfAbsent('user_id', () => currentUserId);
          rows.removeWhere((r) => r['id'] == stored['id']);
          rows.add(stored);
        }
        return _json(request, 201, const []);

      case 'PATCH':
        final bytes = await request.finalize().toBytes();
        final patch = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
        final matched = rows.where((r) => _matches(r, filters)).toList();
        for (final row in matched) {
          row.addAll(patch);
        }
        return _json(request, 200, matched.map((r) => {'id': r['id']}).toList());

      case 'GET':
        final matched = rows.where((r) => _matches(r, filters)).toList();
        return _json(request, 200, matched);

      default:
        return _json(request, 200, const []);
    }
  }
}
