import 'dart:convert';
import 'dart:io';

import 'package:autocarnet/core/database/database.dart';
import 'package:autocarnet/core/sync/conflict_repository.dart';
import 'package:autocarnet/core/sync/sync_outbox_repository.dart';
import 'package:autocarnet/core/sync/vehicle_sync_service.dart';
import 'package:autocarnet/features/audit/data/audit_repository.dart';
import 'package:autocarnet/features/reminders/data/reminder_repository.dart';
import 'package:autocarnet/features/vehicles/data/vehicle_repository.dart';
import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

/// Mission 2026, real-device incident report: a vehicle (a Volkswagen)
/// created while signed in never reappeared after uninstall/reinstall -
/// meaning it most likely never actually reached Supabase before the local
/// database (and its still-pending outbox trace) was wiped by the
/// uninstall. This test proves the exact chain requested, end to end,
/// through the REAL production code:
///
///   création (VehicleRepository.createVehicle, real Drift transaction)
///     -> push (VehicleSyncService._push -> occ_sync.pushWithOcc, real
///        insert-with-version-0 logic)
///     -> confirmation (outbox markSynced, local syncStatus -> 'synced')
///     -> suppression complète de la base SQLite locale (the file itself
///        is deleted, not just closed - genuinely simulating an uninstall)
///     -> nouvelle installation (a brand new AppDatabase over a fresh file)
///     -> pull (VehicleSyncService._pull, real newerRemoteRows logic)
///     -> the vehicle reappears.
///
/// The only thing "faked" here is the HTTP transport itself (see
/// _FakeCloudHttpClient below) - there is no live Supabase project
/// reachable from this environment, so this is the most rigorous
/// verification possible without one: every line of VehicleRepository,
/// VehicleSyncService, occ_sync.dart and vehicle_sync_mapping.dart runs
/// completely unmodified, exactly as in the real app. The fake client is a
/// real `package:http` Client (SupabaseClient's own supported extension
/// point - see its `httpClient` constructor parameter) that answers
/// PostgREST-shaped requests from an in-memory table, standing in for "the
/// current state of the Supabase project" across the simulated
/// uninstall/reinstall - it is NOT a mock of AutoCarnet's own sync code.
class _FakeCloudHttpClient extends http.BaseClient {
  _FakeCloudHttpClient({required this.currentUserId});

  /// The authenticated user's id - stands in for Postgres's own `default
  /// auth.uid()` on `vehicles.user_id`, which real Postgres fills in
  /// automatically for the column vehicleToRemoteRow deliberately never
  /// sends (see that function's own doc for why).
  final String currentUserId;

  final Map<String, List<Map<String, dynamic>>> tables = {};

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
      // postgrest's own _parseResponse reads `response.request!` - a real
      // http.Client always attaches this; a StreamedResponse built by hand
      // without it null-checks and crashes there, not anywhere in
      // AutoCarnet's own code (confirmed by isolating this directly).
      request: request,
    );
  }

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final rows = _tableFor(request.url);
    final filters = _eqFilters(request.url.queryParameters);

    switch (request.method) {
      case 'POST':
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // hasConnectivity() (VehicleSyncService.syncNow's own pre-check) goes
  // through connectivity_plus's platform channel - never available in a
  // plain `test()` VM without a fake platform implementation. Always
  // reporting "wifi" here is the equivalent of the mission's own "Internet
  // disponible" precondition for this scenario.
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
    const MethodChannel('dev.fluttercommunity.plus/connectivity'),
    (call) async => call.method == 'check' ? ['wifi'] : null,
  );

  /// A structurally valid (not cryptographically signed - nothing here
  /// verifies a signature, only decodes claims) JWT, so gotrue's own
  /// `Session.isExpired` (which decodes the access token's own `exp` claim,
  /// not any separate field on the session JSON) reports "not expired" and
  /// `recoverSession` accepts it purely locally, with no network call.
  String fakeJwt({required String sub, required Duration validFor}) {
    String segment(Map<String, dynamic> data) =>
        base64Url.encode(utf8.encode(jsonEncode(data))).replaceAll('=', '');
    final header = segment({'alg': 'none', 'typ': 'JWT'});
    final exp = DateTime.now().add(validFor).millisecondsSinceEpoch ~/ 1000;
    final payload = segment({'sub': sub, 'exp': exp, 'role': 'authenticated'});
    return '$header.$payload.fake-signature';
  }

  /// Injects a genuinely non-expired session with no network call at all -
  /// see GoTrueClient.recoverSession's source: for a non-expired session it
  /// just saves it locally and returns, the exact mechanism a real device
  /// uses restoring a session from disk on cold start.
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

  test(
      'CRÉATION -> PRÉSENCE DANS SUPABASE -> SUPPRESSION DU LOCAL -> '
      'RESTAURATION DEPUIS SUPABASE: a vehicle created while signed in is '
      'genuinely pushed, survives a real uninstall (the SQLite file itself '
      'is deleted), and reappears on a fresh install pulling from the same '
      'cloud state', () async {
    const userId = 'e2e-user-1';
    final cloud = _FakeCloudHttpClient(currentUserId: userId);
    final client = SupabaseClient(
      'https://example.invalid.supabase.co',
      'anon-key-test',
      httpClient: cloud,
    );
    await signIn(client, userId);
    expect(client.auth.currentSession, isNotNull,
        reason: 'the whole test is worthless if the fake session was not actually accepted');

    final tempDir = await Directory.systemTemp.createTemp('autocarnet_e2e_');
    addTearDown(() => tempDir.deleteSync(recursive: true));

    // ---- "Device 1", app install #1: create + push ----------------------
    final dbFile1 = File('${tempDir.path}/device1.sqlite');
    var db1 = AppDatabase(NativeDatabase(dbFile1));
    final outbox1 = SyncOutboxRepository(db1);
    final vehicles1 =
        VehicleRepository(db1, AuditRepository(db1), ReminderRepository(db1), null, outbox1);
    final conflicts1 = ConflictRepository(db1);
    final syncService1 = VehicleSyncService(db1, () => client, conflicts1, outbox1);

    final vehicleId = await vehicles1.createVehicle(
      brand: 'Volkswagen',
      model: 'Golf',
      currentMileage: 42000,
      plate: 'E2E-TEST-001',
    );

    // Sanity check requested explicitly: the write is atomic and enqueues
    // an outbox trace before any network attempt even starts.
    expect(await outbox1.pendingCount(), greaterThan(0));
    final beforePush = await vehicles1.getOne(vehicleId);
    expect(beforePush.syncStatus, 'pendingSync');

    // The actual push - real occ_sync.pushWithOcc, real Supabase client,
    // fake transport underneath.
    await syncService1.syncNow();

    final afterPush = await vehicles1.getOne(vehicleId);
    expect(afterPush.syncStatus, 'synced',
        reason: 'the push must have actually completed and been confirmed');
    expect(await vehicles1.syncStateFor(vehicleId), EntitySyncState.synced);

    // PRÉSENCE DANS SUPABASE - checked against the fake cloud's own store,
    // exactly what a `select * from vehicles where id = ...` would show on
    // the real project.
    final cloudRows = cloud.tables['vehicles']!;
    expect(cloudRows.where((r) => r['id'] == vehicleId), hasLength(1));
    expect(cloudRows.single['brand'], 'Volkswagen');
    expect(cloudRows.single['user_id'], userId);

    // SUPPRESSION DU LOCAL - not just closing the connection: the SQLite
    // file itself is deleted, exactly what an Android uninstall does to
    // the app's private storage.
    await db1.close();
    dbFile1.deleteSync();
    expect(dbFile1.existsSync(), isFalse);

    // ---- "Device 2" (or the same device, reinstalled): pull -------------
    final dbFile2 = File('${tempDir.path}/device2.sqlite');
    final db2 = AppDatabase(NativeDatabase(dbFile2));
    addTearDown(db2.close);
    final vehicles2 =
        VehicleRepository(db2, AuditRepository(db2), ReminderRepository(db2), null,
            SyncOutboxRepository(db2));
    final conflicts2 = ConflictRepository(db2);
    final syncService2 = VehicleSyncService(db2, () => client, conflicts2, SyncOutboxRepository(db2));

    // Nothing local yet - a genuinely fresh install.
    expect(await (db2.select(db2.vehicles)).get(), isEmpty);

    // RESTAURATION DEPUIS SUPABASE.
    await syncService2.syncNow();

    final restored = await vehicles2.getOne(vehicleId);
    expect(restored.brand, 'Volkswagen');
    expect(restored.model, 'Golf');
    expect(restored.plate, 'E2E-TEST-001');
    expect(restored.currentMileage, 42000);
    expect(restored.syncStatus, 'synced');
    expect(restored.isDeleted, isFalse);

    final visible = await vehicles2.watchAll(currentUserId: userId).first;
    expect(visible.any((v) => v.id == vehicleId), isTrue,
        reason: 'not just present in the table - actually visible in the normal vehicle list');
  });
}
